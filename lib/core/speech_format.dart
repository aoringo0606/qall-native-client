import 'message_content.dart';

/// Web版 (traQ_S-UI の lib/tts/format.ts) と同じ方針でメッセージを読み上げ用の文にする。
const maxSpeechLength = 140;

final _fence = RegExp(r'```[\s\S]*?(```|$)');
final _mathBlock = RegExp(r'\$\$[\s\S]*?\$\$');
final _spoiler = RegExp(r'\|\|[\s\S]*?\|\|');
final _stamp = RegExp(r':([a-zA-Z0-9_\-]{1,32})(?:\.[a-zA-Z0-9_\-.]+)?:');

String formatForSpeech({
  required String userDisplayName,
  required String content,
  required String origin,
}) {
  final withoutBlocks = content
      .replaceAll(_fence, '\nコードブロック\n')
      .replaceAll(_mathBlock, '\n数式\n')
      .replaceAll(_spoiler, ' ﾍﾟｹﾍﾟｹ ');

  final parsed = parseMessageContent(withoutBlocks, origin: origin);
  final buffer = StringBuffer();
  for (final segment in parsed.segments) {
    buffer.write(switch (segment.kind) {
      SegmentKind.text => segment.text.replaceAllMapped(
        _stamp,
        (m) => ' ${m[1]}スタンプ ',
      ),
      SegmentKind.embed => segment.text,
      SegmentKind.link => _describeUrl(segment.url!, origin),
    });
  }
  for (final _ in parsed.fileIds) {
    buffer.write(' 添付ファイル ');
  }

  var text = buffer.toString().trim();
  if (text.length > maxSpeechLength) {
    text = '${text.substring(0, maxSpeechLength)} 。以下略';
  }
  return '$userDisplayNameさん: $text';
}

String _describeUrl(String url, String origin) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return '不明なドメインのURL';
  if (url.startsWith(origin)) {
    if (uri.path.startsWith('/messages/')) return ' 添付メッセージ ';
    if (uri.path.startsWith('/files/')) return ' 添付ファイル ';
  }
  return '${uri.host}ドメインのURL';
}
