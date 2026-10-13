import 'dart:convert';

enum SegmentKind { text, link, embed }

class ContentSegment {
  const ContentSegment(this.kind, this.text, {this.url});

  final SegmentKind kind;
  final String text;

  /// [SegmentKind.link] のときのリンク先
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is ContentSegment &&
      other.kind == kind &&
      other.text == text &&
      other.url == url;

  @override
  int get hashCode => Object.hash(kind, text, url);

  @override
  String toString() => 'ContentSegment($kind, "$text", $url)';
}

/// 表示用に分解したメッセージ本文。
class MessageContent {
  const MessageContent({required this.segments, required this.fileIds});

  final List<ContentSegment> segments;

  /// 本文中に貼られた traQ のファイルID (添付ファイルとして別表示する)
  final List<String> fileIds;

  String get plainText => segments.map((s) => s.text).join();
}

final _urlPattern = RegExp(r'https?://[^\s<>"]+');
final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// traQ のメッセージ本文を最小限パースする。
///
/// - `!{"type":"user","raw":"@name","id":"..."}` 形式の埋め込みを `raw` の表示に置き換える
/// - URL をリンクにする
/// - `{origin}/files/{id}` は本文から取り除き [MessageContent.fileIds] に入れる
///
/// Markdown やスタンプの描画はしない (このアプリはメッセージ機能を最小限にしている)。
MessageContent parseMessageContent(String content, {required String origin}) {
  final segments = <ContentSegment>[];
  final fileIds = <String>[];

  void addText(String text) {
    if (text.isEmpty) return;
    if (segments.isNotEmpty && segments.last.kind == SegmentKind.text) {
      final last = segments.removeLast();
      segments.add(ContentSegment(SegmentKind.text, last.text + text));
    } else {
      segments.add(ContentSegment(SegmentKind.text, text));
    }
  }

  void addPlain(String text) {
    var index = 0;
    for (final match in _urlPattern.allMatches(text)) {
      addText(text.substring(index, match.start));
      final url = match.group(0)!;
      final fileId = _fileIdFromUrl(url, origin);
      if (fileId != null) {
        fileIds.add(fileId);
      } else {
        segments.add(ContentSegment(SegmentKind.link, url, url: url));
      }
      index = match.end;
    }
    addText(text.substring(index));
  }

  var index = 0;
  while (index < content.length) {
    final start = content.indexOf('!{', index);
    if (start < 0) break;
    final end = _findJsonObjectEnd(content, start + 1);
    final raw = end == null
        ? null
        : _embedRaw(content.substring(start + 1, end));
    if (raw == null) {
      addPlain(content.substring(index, start + 2));
      index = start + 2;
      continue;
    }
    addPlain(content.substring(index, start));
    segments.add(ContentSegment(SegmentKind.embed, raw));
    index = end!;
  }
  addPlain(content.substring(index));

  // ファイルURLを取り除いたことで末尾に残った空白を整える
  if (fileIds.isNotEmpty &&
      segments.isNotEmpty &&
      segments.last.kind == SegmentKind.text) {
    final last = segments.removeLast();
    final trimmed = last.text.trimRight();
    if (trimmed.isNotEmpty) {
      segments.add(ContentSegment(SegmentKind.text, trimmed));
    }
  }

  return MessageContent(segments: segments, fileIds: fileIds);
}

String? _fileIdFromUrl(String url, String origin) {
  final prefix = '$origin/files/';
  if (!url.startsWith(prefix)) return null;
  final id = url.substring(prefix.length).split(RegExp(r'[/?#]')).first;
  return _uuidPattern.hasMatch(id) ? id : null;
}

/// [start] にある `{` に対応する `}` の次の位置を返す。文字列リテラル内の括弧は無視する。
int? _findJsonObjectEnd(String text, int start) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final c = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    switch (c) {
      case '"':
        inString = true;
      case '{':
        depth++;
      case '}':
        depth--;
        if (depth == 0) return i + 1;
      case '\n':
        // 埋め込みは1行に収まる
        return null;
    }
  }
  return null;
}

String? _embedRaw(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map &&
        decoded['raw'] is String &&
        decoded['type'] is String) {
      return decoded['raw'] as String;
    }
  } on FormatException {
    // 埋め込みではない
  }
  return null;
}
