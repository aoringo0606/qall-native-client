import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../widgets/user_avatar.dart';
import '../messages/channel_page.dart';
import 'call_controller.dart';

class CallPage extends ConsumerStatefulWidget {
  const CallPage({super.key});

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage> {
  late final QallCallController _call;
  StreamSubscription<StampReaction>? _reactionSub;
  final _reactions = <(Key, StampReaction)>[];
  bool _wasInCall = false;

  @override
  void initState() {
    super.initState();
    _call = ref.read(qallCallProvider);
    _wasInCall = _call.inCall;
    _call.addListener(_onCallChanged);
    _reactionSub = _call.reactions.listen(_showReaction);
  }

  @override
  void dispose() {
    _call.removeListener(_onCallChanged);
    _reactionSub?.cancel();
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

  void _showReaction(StampReaction reaction) {
    final key = UniqueKey();
    setState(() => _reactions.add((key, reaction)));
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _reactions.removeWhere((r) => r.$1 == key));
    });
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
    return ListenableBuilder(
      listenable: _call,
      builder: (context, _) {
        final channelId = _call.channelId;
        final videos = _call.videos;
        final participants = _call.participants;
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
                  CallStatus.connected => '${participants.length}人が参加中',
                }, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            actions: [
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
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: switch (_call.status) {
                        CallStatus.idle || CallStatus.connecting
                            when participants.isEmpty =>
                          const Center(child: CircularProgressIndicator()),
                        _ when videos.isNotEmpty => _VideoStage(videos: videos),
                        _ => _ParticipantGrid(participants: participants),
                      },
                    ),
                    if (videos.isNotEmpty)
                      SizedBox(
                        height: 88,
                        child: _ParticipantStrip(participants: participants),
                      ),
                    _Controls(call: _call, run: _run),
                  ],
                ),
                for (final (key, reaction) in _reactions)
                  _FloatingStamp(key: key, reaction: reaction),
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
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          _ControlButton(
            icon: call.isMicEnabled ? Icons.mic : Icons.mic_off,
            label: call.isMicEnabled ? 'ミュート' : 'ミュート解除',
            active: call.isMicEnabled,
            onPressed: canPublish ? () => run(call.toggleMicrophone) : null,
          ),
          _ControlButton(
            icon: call.isSpeakerOn ? Icons.volume_up : Icons.hearing,
            label: call.isSpeakerOn ? 'スピーカー' : '受話口',
            active: call.isSpeakerOn,
            onPressed: connected
                ? () => run(() => call.setSpeakerOn(!call.isSpeakerOn))
                : null,
          ),
          _ControlButton(
            icon: call.isScreenSharing
                ? Icons.stop_screen_share
                : Icons.screen_share,
            label: call.isScreenSharing ? '共有を停止' : '画面共有',
            active: call.isScreenSharing,
            onPressed: canPublish ? () => run(call.toggleScreenShare) : null,
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

  final List<Participant> participants;

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

  final List<Participant> participants;

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

  final Participant participant;
  final double avatarRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = userIdFromIdentity(participant.identity);
    final muted = !participant.isMicrophoneEnabled();
    final scheme = Theme.of(context).colorScheme;
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
            if (participant.isScreenShareEnabled())
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
            '${userDisplayName(ref, userIdFromIdentity(videos[page].participant.identity))}'
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

/// 他の参加者が送ったスタンプを数秒間浮かべる。
class _FloatingStamp extends ConsumerWidget {
  const _FloatingStamp({super.key, required this.reaction});

  final StampReaction reaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final left = (reaction.stampId.hashCode % 60 + 20) / 100;
    return Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(seconds: 3),
          builder: (context, t, child) => Align(
            alignment: Alignment(left * 2 - 1, 0.6 - t * 1.2),
            child: Opacity(opacity: t < 0.8 ? 1 : (1 - t) * 5, child: child),
          ),
          child: CachedNetworkImage(
            imageUrl: api.stampImageUrl(reaction.stampId),
            httpHeaders: api.authHeaders,
            width: 48,
            height: 48,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
