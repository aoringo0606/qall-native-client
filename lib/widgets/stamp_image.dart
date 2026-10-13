import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';

/// 全スタンプ (ID → スタンプ)。一度読んだらアプリを閉じるまで使い回す。
final stampsProvider = FutureProvider<Map<String, Stamp>>((ref) async {
  final stamps = await ref.watch(apiProvider).getStamps();
  return {for (final s in stamps) s.id: s};
});

/// スタンプ画像。取得には認証が必要。
/// スクリーンショット撮影時などに差し替えられるようプロバイダーにしている。
final stampImageProvider = Provider<ImageProvider? Function(String stampId)>((
  ref,
) {
  final api = ref.watch(apiProvider);
  return (id) => CachedNetworkImageProvider(
    api.stampImageUrl(id),
    headers: api.authHeaders,
  );
});

class StampImage extends ConsumerWidget {
  const StampImage({super.key, required this.stampId, this.size = 32});

  final String stampId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(stampImageProvider)(stampId);
    final fallback = _NameFallback(stampId: stampId, size: size);
    if (image == null) return fallback;
    return Image(
      image: image,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _NameFallback extends ConsumerWidget {
  const _NameFallback({required this.stampId, required this.size});

  final String stampId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(stampsProvider).value?[stampId]?.name ?? '?';
    return SizedBox.square(
      dimension: size,
      child: FittedBox(child: Text(':$name:')),
    );
  }
}
