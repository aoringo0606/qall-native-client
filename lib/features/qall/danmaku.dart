import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/message_content.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../widgets/stamp_image.dart';
import 'call_controller.dart';

/// 通話画面に重ねる弾幕。Web版の DanmakuContainer に相当し、
/// 通話中のチャンネルへの投稿が右から左へ流れ、スタンプリアクションが浮かび上がる。
class DanmakuOverlay extends ConsumerStatefulWidget {
  const DanmakuOverlay({super.key, required this.call});

  final QallCallController call;

  @override
  ConsumerState<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends ConsumerState<DanmakuOverlay> {
  static const _lanes = 6;
  static const _commentDuration = Duration(seconds: 7);
  static const _stampDuration = Duration(seconds: 3);

  final _random = Random();
  final _comments = <_Comment>[];
  final _stamps = <_Stamp>[];
  final _laneBusyUntil = List<DateTime>.filled(
    _lanes,
    DateTime.fromMillisecondsSinceEpoch(0),
  );
  late final List<StreamSubscription<Object>> _subscriptions;

  @override
  void initState() {
    super.initState();
    _subscriptions = [
      widget.call.channelMessages.listen(_addComment),
      widget.call.reactions.listen(_addStamp),
    ];
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  void _addComment(Message message) {
    final api = ref.read(apiProvider);
    var text = parseMessageContent(
      message.content,
      origin: api.origin,
    ).plainText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return;
    if (text.length > 60) text = '${text.substring(0, 60)}…';

    // 空いているレーン (なければ最も早く空くレーン) に流す
    final now = DateTime.now();
    var lane = 0;
    for (var i = 1; i < _lanes; i++) {
      if (_laneBusyUntil[i].isBefore(_laneBusyUntil[lane])) lane = i;
    }
    _laneBusyUntil[lane] = now.add(const Duration(milliseconds: 1500));

    final comment = _Comment(UniqueKey(), text, lane);
    setState(() => _comments.add(comment));
    Future<void>.delayed(_commentDuration, () {
      if (mounted) setState(() => _comments.remove(comment));
    });
  }

  void _addStamp(StampReaction reaction) {
    final stamp = _Stamp(
      UniqueKey(),
      reaction.stampId,
      0.1 + _random.nextDouble() * 0.8,
    );
    setState(() => _stamps.add(stamp));
    Future<void>.delayed(_stampDuration, () {
      if (mounted) setState(() => _stamps.remove(stamp));
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final laneHeight = min(36.0, constraints.maxHeight * 0.6 / _lanes);
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final c in _comments)
                TweenAnimationBuilder<double>(
                  key: c.key,
                  tween: Tween(begin: 0, end: 1),
                  duration: _commentDuration,
                  builder: (context, t, child) => Positioned(
                    top: 8 + c.lane * laneHeight,
                    // 画面の右端から、左端の外まで流す
                    left: constraints.maxWidth - t * (constraints.maxWidth * 2),
                    child: child!,
                  ),
                  child: _OutlinedText(c.text),
                ),
              for (final s in _stamps)
                TweenAnimationBuilder<double>(
                  key: s.key,
                  tween: Tween(begin: 0, end: 1),
                  duration: _stampDuration,
                  builder: (context, t, child) => Positioned(
                    left: s.x * (constraints.maxWidth - 56),
                    bottom: 24 + t * constraints.maxHeight * 0.5,
                    child: Opacity(
                      opacity: t < 0.8 ? 1 : (1 - t) * 5,
                      child: Transform.scale(
                        scale: t < 0.15 ? 0.6 + t / 0.15 * 0.4 : 1,
                        child: child,
                      ),
                    ),
                  ),
                  child: StampImage(stampId: s.stampId, size: 56),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Comment {
  _Comment(this.key, this.text, this.lane);

  final Key key;
  final String text;
  final int lane;
}

class _Stamp {
  _Stamp(this.key, this.stampId, this.x);

  final Key key;
  final String stampId;
  final double x;
}

/// 背景が映像でも読めるよう縁取りした文字。
class _OutlinedText extends StatelessWidget {
  const _OutlinedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
    return Stack(
      children: [
        Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = Colors.black87,
          ),
        ),
        Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: style.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}
