import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 通知ボタンのID
abstract final class CallNotificationAction {
  static const toggleMute = 'toggle_mute';
  static const hangUp = 'hang_up';
}

/// 通話中にアプリがバックグラウンドに回ったり画面がスリープしても
/// 通話が切れないようにする仕組み。
///
/// - Android: `microphone` (画面共有中は `mediaProjection` も) タイプの
///   フォアグラウンドサービスを起動し、WakeLock / WifiLock を保持する。
/// - iOS: `UIBackgroundModes: audio, voip` により、音声セッションが有効な間は
///   OS がアプリを停止しないので何もしない (Info.plist を参照)。
class CallBackgroundService {
  CallBackgroundService({required this.onNotificationAction});

  /// 通知のボタンが押されたとき (Android のみ)
  final void Function(String action) onNotificationAction;

  bool _running = false;
  String _channelName = '';
  bool _useMicrophone = true;
  bool _muted = false;
  bool _screenSharing = false;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// `main()` で一度だけ呼ぶ。
  static void initialize() {
    if (!_supported) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'qall_call',
        channelName: '通話',
        channelDescription: 'Qallで通話中であることを表示します',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        // アプリのプロセスが落ちたら通話も終わっているので復活させない
        allowAutoRestart: false,
        stopWithTask: true,
      ),
    );
  }

  /// 通話開始時に呼ぶ。[useMicrophone] はマイク権限があるかどうか
  /// (Android 14 以降、権限なしで `microphone` タイプのサービスは開始できない)。
  Future<void> start({
    required String channelName,
    required bool useMicrophone,
  }) async {
    if (!_supported) return;
    _channelName = channelName;
    _useMicrophone = useMicrophone;
    _muted = !useMicrophone;
    _screenSharing = false;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    await FlutterForegroundTask.requestNotificationPermission();
    await _startService();
  }

  /// 画面共有の開始/終了に合わせてサービスタイプを切り替える。
  ///
  /// Android 14 以降は `mediaProjection` タイプのサービスを、ユーザーが
  /// 画面キャプチャを許可した *後* に開始する必要があるため、
  /// `Helper.requestCapturePermission()` の後に呼ぶこと。
  Future<void> setScreenSharing(bool sharing) async {
    if (!_supported || sharing == _screenSharing) return;
    _screenSharing = sharing;
    if (!_running) return;
    await FlutterForegroundTask.stopService();
    _running = false;
    await _startService();
  }

  /// 通知の表示内容を更新する。
  Future<void> update({
    required String channelName,
    required bool muted,
    required bool screenSharing,
  }) async {
    if (!_supported || !_running) return;
    _channelName = channelName;
    _muted = muted;
    await FlutterForegroundTask.updateService(
      notificationTitle: _title,
      notificationText: _text(screenSharing: screenSharing),
      notificationButtons: _buttons,
    );
  }

  Future<void> stop() async {
    if (!_supported) return;
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _screenSharing = false;
    if (_running || await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    _running = false;
  }

  Future<void> _startService() async {
    final result = await FlutterForegroundTask.startService(
      serviceId: 2001,
      serviceTypes: [
        _useMicrophone
            ? ForegroundServiceTypes.microphone
            : ForegroundServiceTypes.mediaPlayback,
        if (_screenSharing) ForegroundServiceTypes.mediaProjection,
      ],
      notificationTitle: _title,
      notificationText: _text(screenSharing: _screenSharing),
      notificationButtons: _buttons,
      callback: startCallTaskHandler,
    );
    if (result is ServiceRequestFailure) {
      debugPrint('Failed to start foreground service: ${result.error}');
      return;
    }
    _running = true;
  }

  String get _title => '$_channelName で通話中';

  String _text({required bool screenSharing}) =>
      screenSharing ? '画面を共有しています' : (_muted ? 'ミュート中' : 'マイクオン');

  List<NotificationButton> get _buttons => [
    if (_useMicrophone)
      NotificationButton(
        id: CallNotificationAction.toggleMute,
        text: _muted ? 'ミュート解除' : 'ミュート',
      ),
    const NotificationButton(id: CallNotificationAction.hangUp, text: '退出'),
  ];

  void _onTaskData(Object data) {
    if (data is String) onNotificationAction(data);
  }
}

/// フォアグラウンドサービス側の isolate のエントリポイント。
@pragma('vm:entry-point')
void startCallTaskHandler() {
  FlutterForegroundTask.setTaskHandler(_CallTaskHandler());
}

class _CallTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    // 通話の実体はメイン isolate にあるので、そちらに転送する
    FlutterForegroundTask.sendDataToMain(id);
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}
