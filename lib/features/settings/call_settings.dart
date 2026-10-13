import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// マイク音声のノイズ除去の方式。
enum NoiseReduction {
  /// WebRTC 標準のノイズ抑制 (端末のハードウェア処理も含む)
  standard,

  /// RNNoise (Web版の「Rnnoise」と同じ AI ノイズ除去)
  rnnoise,

  /// ノイズ除去なし
  off,
}

/// 通話まわりの設定。Web版 (traQ_S-UI) の「設定 > Qall」と通話画面の設定に相当する。
class CallSettings {
  const CallSettings({
    this.noiseReduction = NoiseReduction.standard,
    this.echoCancellation = true,
    this.autoGainControl = true,
    this.masterVolume = 1,
    this.soundEffects = true,
    this.danmaku = true,
    this.ttsEnabled = false,
    this.ttsVoice,
    this.ttsPitch = 1,
    this.ttsRate = 1.2,
    this.ttsVolume = 1,
    this.userVolumes = const {},
  });

  factory CallSettings.fromJson(Map<String, dynamic> json) {
    const d = CallSettings();
    double number(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    return CallSettings(
      noiseReduction:
          NoiseReduction.values.asNameMap()[json['noiseReduction']] ??
          d.noiseReduction,
      echoCancellation: json['echoCancellation'] as bool? ?? d.echoCancellation,
      autoGainControl: json['autoGainControl'] as bool? ?? d.autoGainControl,
      masterVolume: number('masterVolume', d.masterVolume),
      soundEffects: json['soundEffects'] as bool? ?? d.soundEffects,
      danmaku: json['danmaku'] as bool? ?? d.danmaku,
      ttsEnabled: json['ttsEnabled'] as bool? ?? d.ttsEnabled,
      ttsVoice: json['ttsVoice'] as String?,
      ttsPitch: number('ttsPitch', d.ttsPitch),
      ttsRate: number('ttsRate', d.ttsRate),
      ttsVolume: number('ttsVolume', d.ttsVolume),
      userVolumes: {
        for (final e
            in (json['userVolumes'] as Map<String, dynamic>? ?? const {})
                .entries)
          e.key: (e.value as num).toDouble(),
      },
    );
  }

  final NoiseReduction noiseReduction;
  final bool echoCancellation;
  final bool autoGainControl;

  /// 他の参加者の声・効果音の音量 (0〜2、1 が等倍)
  final double masterVolume;

  /// 入退室などの効果音を鳴らすか
  final bool soundEffects;

  /// 通話画面にコメントやスタンプを流すか
  final bool danmaku;

  /// 通話中のチャンネルに投稿されたメッセージを読み上げるか
  final bool ttsEnabled;
  final String? ttsVoice;
  final double ttsPitch;
  final double ttsRate;
  final double ttsVolume;

  /// 参加者ごとの音量 (ユーザーID → 0〜2)
  final Map<String, double> userVolumes;

  double userVolume(String userId) => userVolumes[userId] ?? 1;

  /// 実際に WebRTC に設定する、ある参加者の音量。
  double effectiveVolume(String userId) => masterVolume * userVolume(userId);

  CallSettings copyWith({
    NoiseReduction? noiseReduction,
    bool? echoCancellation,
    bool? autoGainControl,
    double? masterVolume,
    bool? soundEffects,
    bool? danmaku,
    bool? ttsEnabled,
    String? ttsVoice,
    double? ttsPitch,
    double? ttsRate,
    double? ttsVolume,
    Map<String, double>? userVolumes,
  }) => CallSettings(
    noiseReduction: noiseReduction ?? this.noiseReduction,
    echoCancellation: echoCancellation ?? this.echoCancellation,
    autoGainControl: autoGainControl ?? this.autoGainControl,
    masterVolume: masterVolume ?? this.masterVolume,
    soundEffects: soundEffects ?? this.soundEffects,
    danmaku: danmaku ?? this.danmaku,
    ttsEnabled: ttsEnabled ?? this.ttsEnabled,
    ttsVoice: ttsVoice ?? this.ttsVoice,
    ttsPitch: ttsPitch ?? this.ttsPitch,
    ttsRate: ttsRate ?? this.ttsRate,
    ttsVolume: ttsVolume ?? this.ttsVolume,
    userVolumes: userVolumes ?? this.userVolumes,
  );

  Map<String, dynamic> toJson() => {
    'noiseReduction': noiseReduction.name,
    'echoCancellation': echoCancellation,
    'autoGainControl': autoGainControl,
    'masterVolume': masterVolume,
    'soundEffects': soundEffects,
    'danmaku': danmaku,
    'ttsEnabled': ttsEnabled,
    'ttsVoice': ttsVoice,
    'ttsPitch': ttsPitch,
    'ttsRate': ttsRate,
    'ttsVolume': ttsVolume,
    'userVolumes': userVolumes,
  };
}

/// `main()` で読み込んだものを override して渡す。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override in main()'),
);

final callSettingsProvider =
    NotifierProvider<CallSettingsNotifier, CallSettings>(
      CallSettingsNotifier.new,
    );

class CallSettingsNotifier extends Notifier<CallSettings> {
  static const _key = 'call_settings';

  @override
  CallSettings build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const CallSettings();
    try {
      return CallSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const CallSettings();
    }
  }

  void update(CallSettings Function(CallSettings) change) {
    state = change(state);
    ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode(state.toJson()));
  }

  void setUserVolume(String userId, double volume) => update(
    (s) => s.copyWith(userVolumes: {...s.userVolumes, userId: volume}),
  );

  void resetUserVolumes() => update((s) => s.copyWith(userVolumes: const {}));
}
