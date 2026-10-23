import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/call_settings.dart';

/// アプリ内だけのお気に入りチャンネル (traQ には保存しない)。
///
/// チャンネルは移動・改名されることがあるので、パスではなくチャンネルID (UUID) で持つ。
/// 見つからないID (削除されたチャンネルや別サーバーのもの) も消さずに残す。
final favoriteChannelsProvider =
    NotifierProvider<FavoriteChannelsNotifier, Set<String>>(
      FavoriteChannelsNotifier.new,
    );

class FavoriteChannelsNotifier extends Notifier<Set<String>> {
  static const _key = 'favorite_channel_ids';

  @override
  Set<String> build() =>
      (ref.watch(sharedPreferencesProvider).getStringList(_key) ?? const [])
          .toSet();

  void toggle(String channelId) {
    state = state.contains(channelId)
        ? ({...state}..remove(channelId))
        : {...state, channelId};
    ref.read(sharedPreferencesProvider).setStringList(_key, state.toList());
  }
}

/// お気に入りの切り替えボタン (星)。
class FavoriteChannelButton extends ConsumerWidget {
  const FavoriteChannelButton({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorite = ref.watch(
      favoriteChannelsProvider.select((ids) => ids.contains(channelId)),
    );
    return IconButton(
      tooltip: favorite ? 'お気に入りから外す' : 'お気に入りに追加',
      icon: favorite
          ? Icon(Icons.star, color: Theme.of(context).colorScheme.primary)
          : const Icon(Icons.star_outline),
      onPressed: () =>
          ref.read(favoriteChannelsProvider.notifier).toggle(channelId),
    );
  }
}
