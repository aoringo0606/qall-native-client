import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:livekit_client/livekit_client.dart';
// BroadcastManager (iOS の画面共有の開始/停止) は公開APIから export されていない
// ignore: implementation_imports
import 'package:livekit_client/src/managers/broadcast_manager.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/traq_api.dart';
import 'call_background.dart';

enum CallStatus { idle, connecting, connected, reconnecting }

/// 画面に表示する映像トラック (画面共有 or カメラ)。
class CallVideo {
  const CallVideo({
    required this.participant,
    required this.track,
    required this.isScreenShare,
  });

  final Participant participant;
  final VideoTrack track;
  final bool isScreenShare;

  String get id => track.sid ?? track.mediaStreamTrack.id ?? '';
}

/// 他の参加者から届いたスタンプリアクション。
class StampReaction {
  const StampReaction({required this.stampId, required this.userId});

  final String stampId;
  final String? userId;
}

class CallException implements Exception {
  const CallException(this.message);

  final String message;

  @override
  String toString() => message;
}

final qallCallProvider = Provider<QallCallController>((ref) {
  final controller = QallCallController(
    api: ref.watch(apiProvider),
    channelName: (id) =>
        ref.read(channelTreeProvider).value?.displayName(id) ?? 'Qall',
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Qall (LiveKit) の通話を1つ管理する。
///
/// traQ Web版 (traQ_S-UI) との互換性のために以下を守る:
/// - ルーム名はチャンネルID。トークンは `GET /qall/token?roomId=` で取得する
/// - マイクのトラックを必ず publish する (Web版の参加者一覧はマイクトラックの有無で判定している)
/// - スタンプリアクションは `{"type":"stamp","message":stampId}` の data メッセージ
class QallCallController extends ChangeNotifier {
  QallCallController({required this.api, required this.channelName}) {
    _background = CallBackgroundService(
      onNotificationAction: _onNotificationAction,
    );
  }

  final TraqApi api;
  final String Function(String channelId) channelName;
  late final CallBackgroundService _background;

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  String? _channelId;
  CallStatus _status = CallStatus.idle;
  bool _speakerOn = true;
  bool _disposed = false;
  int _attempt = 0;
  final _reactions = StreamController<StampReaction>.broadcast();

  static const _micOptions = AudioCaptureOptions(
    // ミュート中もマイクのキャプチャを止めない。
    // iOS で音声セッションを動かし続け、バックグラウンドで停止されないようにするため。
    stopAudioCaptureOnMute: false,
  );

  static const _roomOptions = RoomOptions(
    adaptiveStream: true,
    dynacast: true,
    defaultAudioCaptureOptions: _micOptions,
    defaultAudioPublishOptions: AudioPublishOptions(dtx: false),
    defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
      // iOS: 他のアプリの画面も共有できるよう Broadcast Upload Extension を使う
      useiOSBroadcastExtension: true,
    ),
  );

  String? get channelId => _channelId;
  CallStatus get status => _status;
  bool get inCall => _status != CallStatus.idle;
  Room? get room => _room;
  Stream<StampReaction> get reactions => _reactions.stream;

  LocalParticipant? get _local => _room?.localParticipant;
  bool get canPublish => _local?.permissions.canPublish ?? false;
  bool get isMicEnabled => _local?.isMicrophoneEnabled() ?? false;
  bool get isScreenSharing => _local?.isScreenShareEnabled() ?? false;
  bool get isSpeakerOn => _speakerOn;

  /// 自分を先頭にした参加者一覧 (サウンドボードの再生用参加者は除く)。
  List<Participant> get participants {
    final room = _room;
    if (room == null) return const [];
    return <Participant>[
      ?room.localParticipant,
      ...room.remoteParticipants.values,
    ].where((p) => userIdFromIdentity(p.identity) != null).toList();
  }

  /// 表示可能な映像。画面共有を先に並べる。
  List<CallVideo> get videos {
    final result = <CallVideo>[];
    for (final participant in participants) {
      for (final pub in participant.videoTrackPublications) {
        final track = pub.track;
        if (track is! VideoTrack || pub.muted) continue;
        result.add(
          CallVideo(
            participant: participant,
            track: track,
            isScreenShare: pub.source == TrackSource.screenShareVideo,
          ),
        );
      }
    }
    result.sort(
      (a, b) => (a.isScreenShare ? 0 : 1) - (b.isScreenShare ? 0 : 1),
    );
    return result;
  }

  // ---- 参加 / 退出 ----

  Future<void> join(String channelId) async {
    if (_channelId == channelId && inCall) return;
    if (inCall) await leave();

    // 接続中に leave() されたら、この join は以降何もしない
    final attempt = ++_attempt;
    bool cancelled() => attempt != _attempt;

    _channelId = channelId;
    _status = CallStatus.connecting;
    _notify();

    try {
      final micGranted = await _requestMicrophonePermission();
      final endpoint = await api.getQallEndpoint();
      final token = await api.getQallToken(channelId);
      if (cancelled()) return;

      // Android: 接続前に前面サービスを開始し、以降スリープしても切れないようにする
      await _background.start(
        channelName: channelName(channelId),
        useMicrophone: micGranted,
      );
      if (cancelled()) {
        await _background.stop();
        return;
      }

      final room = Room(roomOptions: _roomOptions);
      _room = room;
      _listener = room.createListener()..listen(_onRoomEvent);
      await room.connect(endpoint, token);
      if (cancelled()) return;

      if (canPublish && micGranted) {
        await room.localParticipant?.setMicrophoneEnabled(
          true,
          audioCaptureOptions: _micOptions,
        );
      }
      await AudioManager.instance.setSpeakerOutputPreferred(_speakerOn);
      if (cancelled()) return;
      _status = CallStatus.connected;
      await _updateNotification();
    } catch (e) {
      if (cancelled()) return;
      debugPrint('Qall join failed: $e');
      await _teardown();
      throw CallException(
        '通話に参加できませんでした: ${e is TraqApiException ? e.message : e}',
      );
    } finally {
      _notify();
    }
  }

  Future<void> leave() async {
    if (!inCall) return;
    await _teardown();
    _notify();
  }

  Future<void> _teardown() async {
    _attempt++;
    final room = _room;
    final listener = _listener;
    _room = null;
    _listener = null;
    _channelId = null;
    _status = CallStatus.idle;

    if (Platform.isIOS && BroadcastManager().isBroadcasting) {
      await BroadcastManager().requestStop();
    }
    await listener?.dispose();
    try {
      await room?.disconnect();
    } catch (e) {
      debugPrint('Qall disconnect failed: $e');
    }
    await room?.dispose();
    await _background.stop();
  }

  // ---- 操作 ----

  Future<void> setMicrophoneEnabled(bool enabled) async {
    final local = _local;
    if (local == null) return;
    if (!canPublish) throw const CallException('このルームでは発言権限がありません');
    if (enabled && !await _requestMicrophonePermission()) {
      throw const CallException('マイクの使用が許可されていません');
    }
    await local.setMicrophoneEnabled(enabled, audioCaptureOptions: _micOptions);
    await _updateNotification();
    _notify();
  }

  Future<void> toggleMicrophone() => setMicrophoneEnabled(!isMicEnabled);

  Future<void> setSpeakerOn(bool on) async {
    _speakerOn = on;
    await AudioManager.instance.setSpeakerOutputPreferred(on);
    _notify();
  }

  /// 画面共有を開始/停止する。
  ///
  /// - Android: MediaProjection の許可ダイアログを出し、許可されたら共有する
  /// - iOS: 画面収録 (ブロードキャスト) の開始ピッカーを出す。ユーザーが開始すると
  ///   LiveKit が自動で publish する
  Future<void> setScreenShareEnabled(bool enabled) async {
    final local = _local;
    final channelId = _channelId;
    if (local == null || channelId == null) return;
    if (!canPublish) throw const CallException('このルームでは発言権限がありません');

    if (!enabled) {
      if (Platform.isIOS && BroadcastManager().isBroadcasting) {
        // ブロードキャストが終わると LiveKit がトラックを unpublish する
        await BroadcastManager().requestStop();
      } else {
        await local.setScreenShareEnabled(false);
      }
      await _background.setScreenSharing(false);
      await _updateNotification();
      _notify();
      return;
    }

    if (Platform.isAndroid) {
      final granted = await Helper.requestCapturePermission();
      if (!granted) return;
      // Android 14+: 許可を得た後に mediaProjection タイプのサービスを開始する必要がある
      await _background.setScreenSharing(true);
    }
    try {
      await local.setScreenShareEnabled(true);
    } catch (e) {
      await _background.setScreenSharing(false);
      throw CallException('画面共有を開始できませんでした: $e');
    }
    await _updateNotification();
    _notify();
  }

  Future<void> toggleScreenShare() => setScreenShareEnabled(!isScreenSharing);

  // ---- 内部 ----

  Future<bool> _requestMicrophonePermission() async {
    final statuses = await [
      Permission.microphone,
      // Android 12+: Bluetooth ヘッドセットに音声を流すのに必要 (拒否されても通話はできる)
      if (Platform.isAndroid) Permission.bluetoothConnect,
    ].request();
    final mic = statuses[Permission.microphone];
    return mic != null && (mic.isGranted || mic.isLimited);
  }

  void _onRoomEvent(RoomEvent event) {
    switch (event) {
      case RoomReconnectingEvent() || RoomAttemptReconnectEvent():
        _status = CallStatus.reconnecting;
      case RoomReconnectedEvent():
        _status = CallStatus.connected;
      case RoomDisconnectedEvent():
        // 自分で leave() した場合は _listener が先に破棄されるのでここには来ない
        unawaited(_teardown().whenComplete(_notify));
        return;
      case DataReceivedEvent():
        _handleData(event);
      case LocalTrackUnpublishedEvent(:final publication)
          when publication.source == TrackSource.screenShareVideo:
        // iOS のコントロールセンター等から共有を止めた場合
        unawaited(_background.setScreenSharing(false));
        unawaited(_updateNotification());
      default:
        break;
    }
    _notify();
  }

  void _handleData(DataReceivedEvent event) {
    try {
      final json = jsonDecode(utf8.decode(event.data));
      if (json is Map && json['type'] == 'stamp' && json['message'] is String) {
        _reactions.add(
          StampReaction(
            stampId: json['message'] as String,
            userId: userIdFromIdentity(event.participant?.identity ?? ''),
          ),
        );
      }
    } on FormatException {
      // 知らない形式のデータは無視
    }
  }

  void _onNotificationAction(String action) {
    switch (action) {
      case CallNotificationAction.toggleMute:
        unawaited(toggleMicrophone().catchError((Object _) {}));
      case CallNotificationAction.hangUp:
        unawaited(leave());
    }
  }

  Future<void> _updateNotification() async {
    final channelId = _channelId;
    if (channelId == null) return;
    await _background.update(
      channelName: channelName(channelId),
      muted: !isMicEnabled,
      screenSharing: isScreenSharing,
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_teardown());
    _reactions.close();
    super.dispose();
  }
}
