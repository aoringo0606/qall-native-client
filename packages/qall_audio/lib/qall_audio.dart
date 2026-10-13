import 'package:flutter/services.dart';

/// 読み上げに使える声。
class TtsVoice {
  const TtsVoice({required this.id, required this.name});

  final String id;
  final String name;
}

/// iOS のマイクモード (コントロールセンターの「マイクモード」)。
enum MicrophoneMode { standard, voiceIsolation, wideSpectrum, unknown }

/// Qall の通話音声まわりのネイティブ機能。
abstract final class QallAudio {
  static const _channel = MethodChannel('jp.trap.qall/audio');

  /// マイク音声に RNNoise (AI ノイズ除去) をかけるかどうかを切り替える。
  ///
  /// WebRTC が初期化された後 (通話に接続した後) に呼ぶこと。
  /// 有効にできなかった場合は false を返す。
  static Future<bool> setNoiseSuppression(bool enabled) async =>
      await _channel.invokeMethod<bool>('setNoiseSuppression', {
        'enabled': enabled,
      }) ??
      false;

  /// iOS: マイクモード (声を分離 / ワイドスペクトル) を選ぶシステム画面を開く。
  /// 通話中 (マイク使用中) のみ有効。Android では何もしないで false を返す。
  static Future<bool> showMicrophoneModes() async =>
      await _channel.invokeMethod<bool>('showMicrophoneModes') ?? false;

  /// iOS: 現在のマイクモード。Android では null。
  static Future<MicrophoneMode?> microphoneMode() async {
    final mode = await _channel.invokeMethod<String>('microphoneMode');
    if (mode == null) return null;
    return MicrophoneMode.values.asNameMap()[mode] ?? MicrophoneMode.unknown;
  }

  /// 通話と同じ音声経路で [text] を読み上げる (キューに追加)。
  /// [rate] は 1.0 が標準の速さ。
  static Future<void> speak(
    String text, {
    String? voice,
    double pitch = 1,
    double rate = 1,
    double volume = 1,
  }) => _channel.invokeMethod('speak', {
    'text': text,
    'voice': voice,
    'pitch': pitch,
    'rate': rate,
    'volume': volume,
  });

  static Future<void> stopSpeaking() => _channel.invokeMethod('stopSpeaking');

  /// 日本語の読み上げ音声の一覧。
  static Future<List<TtsVoice>> voices() async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'voices',
    );
    return [
      for (final v in list ?? const <Map<Object?, Object?>>[])
        TtsVoice(id: v['id']! as String, name: v['name']! as String),
    ];
  }

  /// Flutter のアセット ([asset] は pubspec に書いたパス) を通話と同じ音声経路で鳴らす。
  static Future<void> playSound(String asset, {double volume = 1}) =>
      _channel.invokeMethod('playSound', {'asset': asset, 'volume': volume});
}
