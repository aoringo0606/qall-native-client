import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qall/core/models.dart';
import 'package:qall/features/settings/call_settings.dart';

void main() {
  test('CallSettings survives a JSON round trip', () {
    const settings = CallSettings(
      noiseReduction: NoiseReduction.rnnoise,
      echoCancellation: false,
      masterVolume: 1.5,
      ttsEnabled: true,
      ttsVoice: 'ja-jp-x-jab-local',
      ttsRate: 1.4,
      userVolumes: {'u1': 0.5, 'u2': 2},
    );
    final restored = CallSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );
    expect(restored.noiseReduction, NoiseReduction.rnnoise);
    expect(restored.echoCancellation, isFalse);
    expect(restored.autoGainControl, isTrue);
    expect(restored.masterVolume, 1.5);
    expect(restored.ttsEnabled, isTrue);
    expect(restored.ttsVoice, 'ja-jp-x-jab-local');
    expect(restored.ttsRate, 1.4);
    expect(restored.userVolumes, {'u1': 0.5, 'u2': 2.0});
  });

  test('unknown or missing values fall back to defaults', () {
    final settings = CallSettings.fromJson({'noiseReduction': 'speex'});
    expect(settings.noiseReduction, NoiseReduction.standard);
    expect(settings.masterVolume, 1);
    expect(settings.soundEffects, isTrue);
  });

  test('effective volume combines master and per-user volume', () {
    const settings = CallSettings(masterVolume: 1.5, userVolumes: {'u1': 0.5});
    expect(settings.effectiveVolume('u1'), 0.75);
    expect(settings.effectiveVolume('u2'), 1.5);
  });

  test('SoundboardItem treats nil UUIDs as absent', () {
    final item = SoundboardItem.fromJson({
      'soundId': 's1',
      'soundName': 'ドラムロール',
      'stampId': '00000000-0000-0000-0000-000000000000',
      'creatorId': '0190a6c4-7d43-7b8e-9f21-3c5d8e1a2b4f',
    });
    expect(item.stampId, isNull);
    expect(item.creatorId, '0190a6c4-7d43-7b8e-9f21-3c5d8e1a2b4f');
  });

  test('SoundboardItem drops IDs that are not UUIDs', () {
    // スタンプIDは画像の URL のパスに入るので、`../` などを含むものは捨てる
    final item = SoundboardItem.fromJson({
      'soundId': 's1',
      'soundName': 'x',
      'stampId': '../../users/me?',
    });
    expect(item.stampId, isNull);
  });
}
