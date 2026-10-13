import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/message_content.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../widgets/user_avatar.dart';

class MessageTile extends ConsumerWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.showHeader,
  });

  final Message message;

  /// アイコンと名前を表示するか (連投の2件目以降は省略)
  final bool showHeader;

  static final _timeFormat = DateFormat('HH:mm');
  static final _dateTimeFormat = DateFormat('M/d HH:mm');

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    return (sameDay ? _timeFormat : _dateTimeFormat).format(time);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final theme = Theme.of(context);
    final content = parseMessageContent(message.content, origin: api.origin);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, showHeader ? 10 : 2, 12, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: showHeader ? UserAvatar(userId: message.userId) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader)
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          userDisplayName(ref, message.userId),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(message.createdAt),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                if (content.segments.isNotEmpty)
                  _MessageBody(segments: content.segments),
                for (final fileId in content.fileIds)
                  _Attachment(fileId: fileId),
                if (message.edited || message.stampCount > 0)
                  Text(
                    [
                      if (message.edited) '(編集済み)',
                      if (message.stampCount > 0) 'スタンプ ${message.stampCount}',
                    ].join('  '),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openUrl(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class _MessageBody extends StatefulWidget {
  const _MessageBody({required this.segments});

  final List<ContentSegment> segments;

  @override
  State<_MessageBody> createState() => _MessageBodyState();
}

class _MessageBodyState extends State<_MessageBody> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tapToOpen(String url) {
    final recognizer = TapGestureRecognizer()..onTap = () => _openUrl(url);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final scheme = Theme.of(context).colorScheme;
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final segment in widget.segments)
            switch (segment.kind) {
              SegmentKind.text => TextSpan(text: segment.text),
              SegmentKind.embed => TextSpan(
                text: segment.text,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SegmentKind.link => TextSpan(
                text: segment.text,
                style: TextStyle(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                ),
                recognizer: _tapToOpen(segment.url!),
              ),
            },
        ],
      ),
    );
  }
}

class _Attachment extends ConsumerWidget {
  const _Attachment({required this.fileId});

  final String fileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final fallback = ActionChip(
      avatar: const Icon(Icons.attach_file, size: 18),
      label: const Text('添付ファイルを開く'),
      onPressed: () => _openUrl(api.fileUrl(fileId)),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        onTap: () => _openUrl(api.fileUrl(fileId)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: api.fileThumbnailUrl(fileId),
              httpHeaders: api.authHeaders,
              fit: BoxFit.contain,
              placeholder: (_, _) => const SizedBox(
                height: 120,
                width: 160,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              // サムネイルがないファイル (画像以外) はリンクだけ出す
              errorWidget: (_, _, _) => fallback,
            ),
          ),
        ),
      ),
    );
  }
}
