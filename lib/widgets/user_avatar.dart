import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

/// traQ のユーザーアイコン。`/public/icon/{name}` は認証不要。
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    this.radius = 18,
    this.highlight = false,
  });

  final String? userId;
  final double radius;

  /// 発話中などの強調表示
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiProvider);
    final user = ref.watch(usersProvider).value?[userId];
    final scheme = Theme.of(context).colorScheme;

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.surfaceContainerHighest,
      foregroundImage: user == null
          ? null
          : CachedNetworkImageProvider(api.userIconUrl(user.name)),
      child: Text(
        (user?.displayName ?? '?').characters.first,
        style: TextStyle(fontSize: radius * 0.8),
      ),
    );
    if (!highlight) return avatar;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.greenAccent.shade400, width: 2.5),
      ),
      child: avatar,
    );
  }
}

/// ユーザーIDから表示名を引く。
String userDisplayName(WidgetRef ref, String? userId) {
  if (userId == null) return '不明なユーザー';
  return ref.watch(usersProvider).value?[userId]?.displayName ?? '不明なユーザー';
}
