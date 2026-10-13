import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../widgets/stamp_image.dart';

final _stampHistoryProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(apiProvider).getStampHistory(),
);

/// スタンプを選ぶボトムシート。
///
/// [keepOpen] が true なら選んでも閉じない (通話中に続けてリアクションするため)。
/// false なら選んだスタンプのIDを返して閉じる。
Future<String?> showStampPicker(
  BuildContext context, {
  required String title,
  void Function(String stampId)? onSelected,
  bool keepOpen = false,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.6,
    child: _StampPicker(
      title: title,
      onSelected: (id) {
        onSelected?.call(id);
        if (!keepOpen) Navigator.of(context).pop(id);
      },
    ),
  ),
);

class _StampPicker extends ConsumerStatefulWidget {
  const _StampPicker({required this.title, required this.onSelected});

  final String title;
  final ValueChanged<String> onSelected;

  @override
  ConsumerState<_StampPicker> createState() => _StampPickerState();
}

class _StampPickerState extends ConsumerState<_StampPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final stamps = ref.watch(stampsProvider);
    final history = ref.watch(_stampHistoryProvider).value ?? const [];

    final all = stamps.value ?? const <String, Stamp>{};
    final query = _query.trim().toLowerCase();
    final List<Stamp> shown;
    if (query.isEmpty) {
      shown = [for (final id in history) ?all[id]];
    } else {
      final matches =
          all.values.where((s) => s.name.toLowerCase().contains(query)).toList()
            ..sort((a, b) {
              // 前方一致を先に、短い名前を先に
              final aPrefix = a.name.toLowerCase().startsWith(query) ? 0 : 1;
              final bPrefix = b.name.toLowerCase().startsWith(query) ? 0 : 1;
              if (aPrefix != bPrefix) return aPrefix - bPrefix;
              return a.name.length - b.name.length;
            });
      shown = matches.take(120).toList();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'スタンプを検索',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          Text(
            query.isEmpty ? '最近使ったスタンプ' : '検索結果',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: stamps.isLoading && all.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                ? Center(
                    child: Text(
                      query.isEmpty ? '最近使ったスタンプはありません。検索してください' : '見つかりません',
                    ),
                  )
                : GridView.extent(
                    maxCrossAxisExtent: 56,
                    children: [
                      for (final stamp in shown)
                        Tooltip(
                          message: ':${stamp.name}:',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => widget.onSelected(stamp.id),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: StampImage(stampId: stamp.id),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
