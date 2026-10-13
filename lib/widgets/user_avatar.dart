import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';

/// ユーザーアイコンの画像。`/public/icon/{name}` は認証不要。
/// スクリーンショット撮影時などに差し替えられるようプロバイダーにしている。
final userIconImageProvider = Provider<ImageProvider? Function(User user)>((
  ref,
) {
  final api = ref.watch(apiProvider);
  return (user) => CachedNetworkImageProvider(api.userIconUrl(user.name));
});

/// traQ のユーザーアイコン。画像が読めるまでは名前の頭文字を出す。
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
    final user = ref.watch(usersProvider).value?[userId];
    final iconImage = ref.watch(userIconImageProvider);

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: _placeholderColor(userId),
      foregroundColor: Colors.white,
      foregroundImage: user == null ? null : iconImage(user),
      child: Text(
        (user?.displayName ?? '?').characters.first,
        style: TextStyle(fontSize: radius * 0.8, fontWeight: FontWeight.bold),
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

/// アイコン読み込み前の背景色。ユーザーごとに色を変えて見分けやすくする。
Color _placeholderColor(String? userId) {
  if (userId == null) return Colors.blueGrey;
  final hue = (userId.hashCode % 360).abs().toDouble();
  return HSLColor.fromAHSL(1, hue, 0.45, 0.55).toColor();
}

/// ユーザーIDから表示名を引く。
String userDisplayName(WidgetRef ref, String? userId) {
  if (userId == null) return '不明なユーザー';
  return ref.watch(usersProvider).value?[userId]?.displayName ?? '不明なユーザー';
}
