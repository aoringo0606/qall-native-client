import 'package:flutter_test/flutter_test.dart';
import 'package:qall/core/speech_format.dart';

const origin = 'https://q.trap.jp';

String speak(String content) =>
    formatForSpeech(userDisplayName: 'はな', content: content, origin: origin);

void main() {
  test('prefixes the speaker name', () {
    expect(speak('こんにちは'), 'はなさん: こんにちは');
  });

  test('reads embeds by their raw text', () {
    expect(
      speak('!{"type":"user","raw":"@ryo","id":"x"} おつかれ'),
      'はなさん: @ryo おつかれ',
    );
  });

  test('describes URLs by domain, like the web client', () {
    expect(speak('見て https://example.com/a/b'), 'はなさん: 見て example.comドメインのURL');
    expect(
      speak('$origin/messages/01890f5e-2b5a-7cf3-9a8e-1c2d3e4f5a6b'),
      'はなさん: 添付メッセージ',
    );
    expect(
      speak('$origin/files/01890f5e-2b5a-7cf3-9a8e-1c2d3e4f5a6b'),
      'はなさん: 添付ファイル',
    );
  });

  test('does not treat look-alike domains as traQ links', () {
    expect(
      speak('https://q.trap.jp.evil.com/messages/x'),
      'はなさん: q.trap.jp.evil.comドメインのURL',
    );
  });

  test('removes angle brackets so engines do not parse SSML', () {
    expect(speak('<speak>hi</speak>'), 'はなさん:  speak hi /speak');
  });

  test('reads stamps, spoilers and code blocks', () {
    expect(speak(':thinking_face:'), 'はなさん: thinking_faceスタンプ');
    expect(speak(':party.large.rotate:'), 'はなさん: partyスタンプ');
    expect(speak('答えは||42||'), 'はなさん: 答えは ﾍﾟｹﾍﾟｹ');
    expect(speak('```dart\nvoid main() {}\n```'), 'はなさん: コードブロック');
  });

  test('truncates long messages', () {
    final text = speak('あ' * 200);
    expect(text, 'はなさん: ${'あ' * maxSpeechLength} 。以下略');
  });
}
