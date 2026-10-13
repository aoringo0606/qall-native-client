import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/providers.dart';
import '../../widgets/user_avatar.dart';
import '../messages/channel_page.dart';
import '../settings/call_settings.dart';
import '../settings/settings_page.dart';
import 'call_controller.dart';
import 'danmaku.dart';
import 'participant_volume_sheet.dart';
import 'soundboard_sheet.dart';
import 'stamp_picker.dart';

class CallPage extends ConsumerStatefulWidget {
  const CallPage({super.key});

  /// 通話画面が開いているか。画面が破棄されたら (閉じる以外の理由でも) 戻る。
  static bool isOpen = false;

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage> {
  late final QallCallController _call;
  bool _wasInCall = false;

  @override
  void initState() {
    super.initState();
    _call = ref.read(qallCallProvider);
    _wasInCall = _call.inCall;
    _call.addListener(_onCallChanged);
  }

  @override
  void dispose() {
    CallPage.isOpen = false;
    _call.removeListener(_onCallChanged);
    super.dispose();
  }

  void _onCallChanged() {
    // 通話が終わったら (退出・切断・接続失敗) 画面を閉じる
    if (_wasInCall && !_call.inCall && mounted) {
      // 通話画面の上にチャット画面などが積まれていても、通話画面だけを閉じる
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        if (route.isCurrent) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).removeRoute(route);
        }
      }
    }
    _wasInCall = _call.inCall;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on CallException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(channelTreeProvider).value;
    final danmaku = ref.watch(callSettingsProvider.select((s) => s.danmaku));
    return ListenableBuilder(
      listenable: _call,
      builder: (context, _) {
        final channelId = _call.channelId;
        final videos = _call.videos;
        final participants = _call.participants;
        final listenOnly =
            _call.status == CallStatus.connected && !_call.canPublish;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channelId == null
                      ? 'Qall'
                      : tree?.displayName(channelId) ?? 'Qall',
                  overflow: TextOverflow.ellipsis,
                ),
                Text(switch (_call.status) {
                  CallStatus.idle => '通話していません',
                  CallStatus.connecting => '接続中…',
                  CallStatus.reconnecting => '再接続中…',
                  CallStatus.connected =>
                    '${_call.isWebinar ? 'ウェビナー・' : ''}'
                        '${participants.length}人が参加中',
                }, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            actions: [
              IconButton(
                tooltip: danmaku ? 'コメントを流さない' : 'コメントを流す',
                icon: Icon(danmaku ? Icons.subtitles : Icons.subtitles_off),
                onPressed: () => ref
                    .read(callSettingsProvider.notifier)
                    .update((s) => s.copyWith(danmaku: !danmaku)),
              ),
              if (channelId != null)
                IconButton(
                  tooltip: 'チャット',
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChannelPage(channelId: channelId),
                    ),
                  ),
                ),
              IconButton(
                tooltip: '通話の設定',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (listenOnly)
                  MaterialBanner(
                    content: const Text('ウェビナーのため発言権限がありません (視聴のみ)'),
                    leading: const Icon(Icons.headphones),
                    actions: const [SizedBox.shrink()],
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: switch (_call.status) {
                          CallStatus.idle || CallStatus.connecting
                              when participants.isEmpty =>
                            const Center(child: CircularProgressIndicator()),
                          _ when videos.isNotEmpty => _VideoStage(
                            videos: videos,
                          ),
                          _ => _ParticipantGrid(participants: participants),
                        },
                      ),
                      if (danmaku)
                        Positioned.fill(child: DanmakuOverlay(call: _call)),
                    ],
                  ),
                ),
                if (videos.isNotEmpty)
                  SizedBox(
                    height: 88,
                    child: _ParticipantStrip(participants: participants),
                  ),
                _Controls(call: _call, run: _run),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.call, required this.run});

  final QallCallController call;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = call.status == CallStatus.connected;
    final canPublish = connected && call.canPublish;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              _SmallButton(
                icon: Icons.add_reaction_outlined,
                tooltip: 'スタンプでリアクション',
                onPressed: connected
                    ? () => showStampPicker(
                        context,
                        title: 'リアクション',
                        keepOpen: true,
                        onSelected: (id) => run(() => call.sendStamp(id)),
                      )
                    : null,
              ),
              _SmallButton(
                icon: Icons.graphic_eq,
                tooltip: 'サウンドボード',
                onPressed: connected ? () => showSoundboard(context) : null,
              ),
              _SmallButton(
                icon: call.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                tooltip: call.isSpeakerOn
                    ? 'スピーカー (タップで受話口)'
                    : '受話口 (タップでスピーカー)',
                onPressed: connected
                    ? () => run(() => call.setSpeakerOn(!call.isSpeakerOn))
                    : null,
              ),
              if (Platform.isAndroid)
                _SmallButton(
                  icon: Icons.speaker_group_outlined,
                  tooltip: '音声の出力先',
                  onPressed: connected
                      ? () => _showOutputPicker(context, call)
                      : null,
                ),
              if (call.isCameraEnabled)
                _SmallButton(
                  icon: Icons.cameraswitch_outlined,
                  tooltip: 'カメラを切り替え',
                  onPressed: () => run(call.switchCamera),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              _ControlButton(
                icon: call.isMicEnabled ? Icons.mic : Icons.mic_off,
                label: call.isMicEnabled ? 'ミュート' : 'ミュート解除',
                active: call.isMicEnabled,
                onPressed: canPublish ? () => run(call.toggleMicrophone) : null,
              ),
              _ControlButton(
                icon: call.isCameraEnabled
                    ? Icons.videocam
                    : Icons.videocam_off_outlined,
                label: call.isCameraEnabled ? 'カメラ停止' : 'カメラ',
                active: call.isCameraEnabled,
                onPressed: canPublish ? () => run(call.toggleCamera) : null,
              ),
              _ControlButton(
                icon: call.isScreenSharing
                    ? Icons.stop_screen_share
                    : Icons.screen_share,
                label: call.isScreenSharing ? '共有を停止' : '画面共有',
                active: call.isScreenSharing,
                onPressed: canPublish
                    ? () => run(call.toggleScreenShare)
                    : null,
              ),
              _ControlButton(
                icon: Icons.call_end,
                label: '退出',
                color: scheme.error,
                foreground: scheme.onError,
                onPressed: () => run(call.leave),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showOutputPicker(
    BuildContext context,
    QallCallController call,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: FutureBuilder<List<MediaDevice>>(
        future: call.audioOutputs(),
        builder: (context, snapshot) {
          final devices = snapshot.data;
          if (devices == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('音声の出力先')),
              for (final d in devices)
                ListTile(
                  leading: const Icon(Icons.speaker),
                  title: Text(d.label.isEmpty ? d.deviceId : d.label),
                  onTap: () {
                    run(() => call.selectAudioOutput(d));
                    Navigator.of(context).pop();
                  },
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.color,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            iconSize: 28,
            padding: const EdgeInsets.all(14),
            style: IconButton.styleFrom(
              backgroundColor:
                  color ??
                  (active ? scheme.primary : scheme.surfaceContainerHighest),
              foregroundColor:
                  foreground ??
                  (active ? scheme.onPrimary : scheme.onSurfaceVariant),
            ),
            icon: Icon(icon),
            onPressed: onPressed,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 映像がないときの参加者表示。
class _ParticipantGrid extends StatelessWidget {
  const _ParticipantGrid({required this.participants});

  final List<CallParticipant> participants;

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return const Center(child: Text('参加者を待っています'));
    }
    return GridView.extent(
      maxCrossAxisExtent: 140,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        for (final p in participants)
          _ParticipantTile(participant: p, avatarRadius: 36),
      ],
    );
  }
}

class _ParticipantStrip extends StatelessWidget {
  const _ParticipantStrip({required this.participants});

  final List<CallParticipant> participants;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (final p in participants)
          SizedBox(
            width: 72,
            child: _ParticipantTile(participant: p, avatarRadius: 22),
          ),
      ],
    );
  }
}

class _ParticipantTile extends ConsumerWidget {
  const _ParticipantTile({
    required this.participant,
    required this.avatarRadius,
  });

  final CallParticipant participant;
  final double avatarRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = participant.userId;
    final muted = participant.isMuted;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      // 他の参加者をタップすると、その人の音量を調整できる
      onTap: participant.isLocal
          ? null
          : () => showParticipantVolume(context, userId),
      child: _tileBody(context, ref, userId, muted, scheme),
    );
  }

  Widget _tileBody(
    BuildContext context,
    WidgetRef ref,
    String userId,
    bool muted,
    ColorScheme scheme,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            UserAvatar(
              userId: userId,
              radius: avatarRadius,
              highlight: participant.isSpeaking && !muted,
            ),
            if (muted)
              Positioned(
                right: -2,
                bottom: -2,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: scheme.errorContainer,
                  child: Icon(
                    Icons.mic_off,
                    size: 14,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            if (participant.isScreenSharing)
              Positioned(
                left: -2,
                bottom: -2,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.screen_share,
                    size: 14,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          userDisplayName(ref, userId),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

/// 画面共有・カメラ映像の表示。複数あるときは横スワイプで切り替える。
class _VideoStage extends ConsumerStatefulWidget {
  const _VideoStage({required this.videos});

  final List<CallVideo> videos;

  @override
  ConsumerState<_VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends ConsumerState<_VideoStage> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videos = widget.videos;
    final page = _page.clamp(0, videos.length - 1);
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: videos.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final video = videos[i];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => _FullscreenVideoPage(video: video),
                  ),
                ),
                child: Container(
                  color: Colors.black,
                  child: VideoTrackRenderer(
                    video.track,
                    key: ValueKey(video.id),
                    fit: VideoViewFit.contain,
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '${videos[page].isScreenShare ? '画面共有' : 'カメラ'}: '
            '${userDisplayName(ref, videos[page].userId)}'
            '${videos.length > 1 ? '  (${page + 1}/${videos.length})' : ''}'
            '  ・タップで全画面',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// 全画面表示。ピンチで拡大できるのでスマホでも画面共有の文字が読める。
class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({required this.video});

  final CallVideo video;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 6,
              child: VideoTrackRenderer(
                widget.video.track,
                fit: VideoViewFit.contain,
              ),
            ),
          ),
          SafeArea(
            child: IconButton(
              color: Colors.white,
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
