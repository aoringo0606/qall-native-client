import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qall_audio/qall_audio.dart';

import 'call_settings.dart';

/// 通話の設定 (Web版の「設定 > Qall」に相当)。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(callSettingsProvider);
    final notifier = ref.read(callSettingsProvider.notifier);
    void update(CallSettings Function(CallSettings) change) =>
        notifier.update(change);

    return Scaffold(
      appBar: AppBar(title: const Text('通話の設定')),
      body: ListView(
        children: [
          const _Header('ノイズ除去'),
          RadioGroup<NoiseReduction>(
            groupValue: settings.noiseReduction,
            onChanged: (v) => update((s) => s.copyWith(noiseReduction: v)),
            child: const Column(
              children: [
                RadioListTile(
                  value: NoiseReduction.standard,
                  title: Text('標準'),
                  subtitle: Text('WebRTC と端末のノイズ抑制。電池への負担が最も少ない'),
                ),
                RadioListTile(
                  value: NoiseReduction.rnnoise,
                  title: Text('RNNoise (AI)'),
                  subtitle: Text('Web版の「Rnnoise」と同じ方式。キーボード音や生活音にも強い'),
                ),
                RadioListTile(
                  value: NoiseReduction.off,
                  title: Text('なし'),
                  subtitle: Text('楽器の演奏など、音をそのまま届けたいとき'),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('エコーキャンセル'),
            subtitle: const Text('スピーカーの音がマイクに回り込むのを防ぐ'),
            value: settings.echoCancellation,
            onChanged: (v) => update((s) => s.copyWith(echoCancellation: v)),
          ),
          SwitchListTile(
            title: const Text('自動音量調整'),
            subtitle: const Text('マイクの音量を自動でそろえる'),
            value: settings.autoGainControl,
            onChanged: (v) => update((s) => s.copyWith(autoGainControl: v)),
          ),
          if (Platform.isIOS) const _MicrophoneModeTile(),
          const Divider(),
          const _Header('音量'),
          _SliderTile(
            title: 'マスターボリューム',
            subtitle: '他の参加者の声と効果音の音量',
            value: settings.masterVolume,
            max: 2,
            label: '${(settings.masterVolume * 100).round()}%',
            onChanged: (v) => update((s) => s.copyWith(masterVolume: v)),
          ),
          SwitchListTile(
            title: const Text('効果音'),
            subtitle: const Text('通話の開始・終了と、参加者の入退室で音を鳴らす'),
            value: settings.soundEffects,
            onChanged: (v) => update((s) => s.copyWith(soundEffects: v)),
          ),
          ListTile(
            title: const Text('参加者ごとの音量をリセット'),
            subtitle: Text(
              settings.userVolumes.isEmpty
                  ? '個別に調整した参加者はいません'
                  : '${settings.userVolumes.length}人分の設定があります',
            ),
            enabled: settings.userVolumes.isNotEmpty,
            onTap: notifier.resetUserVolumes,
          ),
          const Divider(),
          const _Header('通話画面'),
          SwitchListTile(
            title: const Text('コメントとスタンプを流す'),
            subtitle: const Text('通話中のチャンネルへの投稿やスタンプを画面に流す (弾幕)'),
            value: settings.danmaku,
            onChanged: (v) => update((s) => s.copyWith(danmaku: v)),
          ),
          const Divider(),
          const _Header('メッセージの読み上げ'),
          SwitchListTile(
            title: const Text('読み上げる'),
            subtitle: const Text('通話中のチャンネルに投稿されたメッセージを読み上げる'),
            value: settings.ttsEnabled,
            onChanged: (v) => update((s) => s.copyWith(ttsEnabled: v)),
          ),
          if (settings.ttsEnabled) ...[
            _VoiceTile(
              selected: settings.ttsVoice,
              onChanged: (v) => update((s) => s.copyWith(ttsVoice: v)),
            ),
            _SliderTile(
              title: 'ピッチ',
              value: settings.ttsPitch,
              min: 0.5,
              max: 2,
              label: settings.ttsPitch.toStringAsFixed(1),
              onChanged: (v) => update((s) => s.copyWith(ttsPitch: v)),
            ),
            _SliderTile(
              title: '速さ',
              value: settings.ttsRate,
              min: 0.5,
              max: 2,
              label: settings.ttsRate.toStringAsFixed(1),
              onChanged: (v) => update((s) => s.copyWith(ttsRate: v)),
            ),
            _SliderTile(
              title: '音量',
              value: settings.ttsVolume,
              max: 1,
              label: '${(settings.ttsVolume * 100).round()}%',
              onChanged: (v) => update((s) => s.copyWith(ttsVolume: v)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.record_voice_over),
                  label: const Text('試しに読み上げる'),
                  onPressed: () => QallAudio.speak(
                    'はなさん、読み上げのテストです',
                    voice: settings.ttsVoice,
                    pitch: settings.ttsPitch,
                    rate: settings.ttsRate,
                    volume: settings.ttsVolume,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.label,
    required this.onChanged,
    this.subtitle,
    this.min = 0,
    required this.max,
  });

  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(title)),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) Text(subtitle!),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TtsVoice>>(
      future: QallAudio.voices(),
      builder: (context, snapshot) {
        final voices = snapshot.data ?? const <TtsVoice>[];
        return ListTile(
          title: const Text('声の種類'),
          subtitle: voices.isEmpty
              ? Text(
                  snapshot.connectionState == ConnectionState.done
                      ? '日本語の声が見つかりませんでした (端末の既定の声を使います)'
                      : '読み込み中…',
                )
              : DropdownButton<String?>(
                  isExpanded: true,
                  value: voices.any((v) => v.id == selected) ? selected : null,
                  hint: const Text('端末の既定'),
                  items: [
                    const DropdownMenuItem(child: Text('端末の既定')),
                    for (final v in voices)
                      DropdownMenuItem(value: v.id, child: Text(v.name)),
                  ],
                  onChanged: onChanged,
                ),
        );
      },
    );
  }
}

/// iOS の「マイクモード」(声を分離など)。アプリからは変更できず、OS の画面を開くだけ。
class _MicrophoneModeTile extends StatefulWidget {
  const _MicrophoneModeTile();

  @override
  State<_MicrophoneModeTile> createState() => _MicrophoneModeTileState();
}

class _MicrophoneModeTileState extends State<_MicrophoneModeTile>
    with WidgetsBindingObserver {
  MicrophoneMode? _mode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // コントロールセンターから戻ってきたら反映する
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final mode = await QallAudio.microphoneMode();
    if (mounted) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_mode) {
      MicrophoneMode.voiceIsolation => '声を分離',
      MicrophoneMode.wideSpectrum => 'ワイドスペクトル',
      MicrophoneMode.standard => '標準',
      _ => '不明',
    };
    return ListTile(
      title: const Text('マイクモード (iOS)'),
      subtitle: Text(
        '現在: $label\n'
        '「声を分離」にすると iOS が周囲の音を強力に取り除きます。'
        '通話中にコントロールセンターから変更できます。',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.open_in_new),
      onTap: QallAudio.showMicrophoneModes,
    );
  }
}
