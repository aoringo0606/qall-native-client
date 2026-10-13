import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/traq_api.dart';
import '../../widgets/stamp_image.dart';
import 'call_controller.dart';
import 'stamp_picker.dart';

final soundboardProvider = FutureProvider.autoDispose<List<SoundboardItem>>((
  ref,
) async {
  // 誰かが音を追加・削除したら取り直す
  final sub = ref
      .watch(traqWsProvider)
      .events
      .where((e) => e.type.startsWith('QALL_SOUNDBOARD_ITEM_'))
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return ref.watch(apiProvider).getSoundboard();
});

/// サウンドボード: 登録された短い音声を通話中のルームに流す。
Future<void> showSoundboard(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      const FractionallySizedBox(heightFactor: 0.6, child: _SoundboardSheet()),
);

class _SoundboardSheet extends ConsumerWidget {
  const _SoundboardSheet();

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    SoundboardItem item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(qallCallProvider).playSoundboard(item.soundId);
    } on CallException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(soundboardProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'サウンドボード',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.upload),
                label: const Text('音を追加'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _UploadDialog(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: switch (items) {
              AsyncData(:final value) when value.isEmpty => const Center(
                child: Text('まだ音が登録されていません'),
              ),
              AsyncData(:final value) => GridView.extent(
                maxCrossAxisExtent: 120,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.3,
                children: [
                  for (final item in value)
                    Card.outlined(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _play(context, ref, item),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (item.stampId case final stampId?)
                                StampImage(stampId: stampId)
                              else
                                const Icon(Icons.music_note, size: 32),
                              const SizedBox(height: 4),
                              Text(
                                item.soundName,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              AsyncError(:final error) => Center(
                child: Text('読み込めませんでした\n$error', textAlign: TextAlign.center),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _UploadDialog extends ConsumerStatefulWidget {
  const _UploadDialog();

  @override
  ConsumerState<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends ConsumerState<_UploadDialog> {
  final _name = TextEditingController();
  PlatformFile? _file;
  int _fileSize = 0;
  String? _stampId;
  bool _uploading = false;
  String? _error;

  /// サーバーは 15〜20秒程度の短い音声を想定している
  static const _maxBytes = 2 * 1024 * 1024;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus'],
    );
    if (file == null) return;
    final size = await file.length() ?? 0;
    setState(() {
      _file = file;
      _fileSize = size;
      _error = size > _maxBytes ? 'ファイルが大きすぎます (2MBまで)' : null;
      if (_name.text.isEmpty) {
        _name.text = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      }
    });
  }

  Future<void> _upload() async {
    final file = _file;
    if (file == null || _name.text.trim().isEmpty) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      await ref
          .read(apiProvider)
          .uploadSoundboard(
            bytes: bytes,
            fileName: file.name,
            name: _name.text.trim(),
            creatorId: ref.read(sessionProvider).me.id,
            stampId: _stampId,
          );
      ref.invalidate(soundboardProvider);
      if (mounted) Navigator.of(context).pop();
    } on TraqApiException catch (e) {
      setState(() => _error = 'アップロードできませんでした: ${e.message}');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    final canUpload =
        file != null &&
        _fileSize <= _maxBytes &&
        _name.text.trim().isNotEmpty &&
        !_uploading;
    return AlertDialog(
      title: const Text('サウンドボードに音を追加'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.audio_file),
            label: Text(file?.name ?? '音声ファイルを選ぶ (20秒以内)'),
            onPressed: _uploading ? null : _pickFile,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名前',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('アイコン'),
              const SizedBox(width: 12),
              if (_stampId case final id?) StampImage(stampId: id),
              const Spacer(),
              TextButton(
                onPressed: _uploading
                    ? null
                    : () async {
                        final id = await showStampPicker(
                          context,
                          title: 'アイコンにするスタンプ',
                        );
                        if (id != null) setState(() => _stampId = id);
                      },
                child: Text(_stampId == null ? 'スタンプを選ぶ' : '変更'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: canUpload ? _upload : null,
          child: _uploading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('追加'),
        ),
      ],
    );
  }
}
