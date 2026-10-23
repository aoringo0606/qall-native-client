import 'package:flutter_test/flutter_test.dart';
import 'package:qall/core/message_content.dart';

const origin = 'https://q.trap.jp';

void main() {
  group('parseMessageContent', () {
    test('plain text stays as a single segment', () {
      final c = parseMessageContent('こんにちは\n2行目', origin: origin);
      expect(c.segments, [
        const ContentSegment(SegmentKind.text, 'こんにちは\n2行目'),
      ]);
      expect(c.fileIds, isEmpty);
    });

    test('user / channel embeds are replaced with their raw text', () {
      final c = parseMessageContent(
        'hi !{"type":"user","raw":"@takashi","id":"0d5b5d5e-0000-0000-0000-000000000000"}'
        ' see !{"type":"channel","raw":"#gps/times","id":"x"}',
        origin: origin,
      );
      expect(c.segments, [
        const ContentSegment(SegmentKind.text, 'hi '),
        const ContentSegment(SegmentKind.embed, '@takashi'),
        const ContentSegment(SegmentKind.text, ' see '),
        const ContentSegment(SegmentKind.embed, '#gps/times'),
      ]);
    });

    test('braces inside JSON strings do not end the embed', () {
      final c = parseMessageContent(
        '!{"type":"user","raw":"@a}b{","id":"x"}!',
        origin: origin,
      );
      expect(c.segments, [
        const ContentSegment(SegmentKind.embed, '@a}b{'),
        const ContentSegment(SegmentKind.text, '!'),
      ]);
    });

    test('text that only looks like an embed is kept', () {
      final c = parseMessageContent('!{not json} and !{"a":1}', origin: origin);
      expect(c.plainText, '!{not json} and !{"a":1}');
      expect(c.segments.every((s) => s.kind == SegmentKind.text), isTrue);
    });

    test('URLs become links', () {
      final c = parseMessageContent(
        'docs: https://example.com/a?b=c done',
        origin: origin,
      );
      expect(c.segments, [
        const ContentSegment(SegmentKind.text, 'docs: '),
        const ContentSegment(
          SegmentKind.link,
          'https://example.com/a?b=c',
          url: 'https://example.com/a?b=c',
        ),
        const ContentSegment(SegmentKind.text, ' done'),
      ]);
    });

    test('traQ file URLs are extracted as attachments', () {
      const id = '01890f5e-2b5a-7cf3-9a8e-1c2d3e4f5a6b';
      final c = parseMessageContent(
        'スクショです\n$origin/files/$id\n',
        origin: origin,
      );
      expect(c.fileIds, [id]);
      expect(c.segments, [const ContentSegment(SegmentKind.text, 'スクショです')]);
    });

    test('file URLs of other servers are plain links', () {
      const url =
          'https://other.example/files/01890f5e-2b5a-7cf3-9a8e-1c2d3e4f5a6b';
      final c = parseMessageContent(url, origin: origin);
      expect(c.fileIds, isEmpty);
      expect(c.segments.single.kind, SegmentKind.link);
    });
  });

  test('strips bidi control characters that can disguise links', () {
    final parsed = parseMessageContent(
      '\u202Ehttps://evil.com/moc.elgoog//:sptth',
      origin: 'https://q.trap.jp',
    );
    expect(parsed.plainText, 'https://evil.com/moc.elgoog//:sptth');
    expect(parsed.segments.single.url, 'https://evil.com/moc.elgoog//:sptth');
  });
}
