import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/channel_tree.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../widgets/user_avatar.dart';
import '../qall/call_actions.dart';
import '../qall/call_controller.dart';
import 'favorite_channels.dart';

/// 通話中のルーム、お気に入り、購読しているチャンネルの一覧と、チャンネル検索。
class ChannelList extends ConsumerStatefulWidget {
  const ChannelList({
    super.key,
    required this.onSelect,
    this.selectedChannelId,
  });

  final void Function(String channelId) onSelect;
  final String? selectedChannelId;

  @override
  ConsumerState<ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends ConsumerState<ChannelList> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(subscriptionsProvider);
    ref.invalidate(unreadProvider);
    ref.invalidate(qallRoomsProvider);
    await Future.wait([
      ref.read(subscriptionsProvider.future),
      ref.read(unreadProvider.future),
      ref.read(qallRoomsProvider.future),
    ]);
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  void _select(String channelId) {
    if (_query.isNotEmpty) {
      _clearSearch();
      FocusScope.of(context).unfocus();
    }
    widget.onSelect(channelId);
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(channelTreeProvider);
    final subscriptions = ref.watch(subscriptionsProvider);

    if (tree.hasError || subscriptions.hasError) {
      return _ErrorView(
        error: tree.error ?? subscriptions.error!,
        onRetry: () {
          ref.invalidate(channelTreeProvider);
          ref.invalidate(subscriptionsProvider);
        },
      );
    }
    final channelTree = tree.value;
    final subscribed = subscriptions.value;
    if (channelTree == null || subscribed == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SearchBar(
            controller: _search,
            hintText: 'チャンネルを検索',
            leading: const Icon(Icons.search),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  tooltip: 'クリア',
                  icon: const Icon(Icons.close),
                  onPressed: _clearSearch,
                ),
            ],
            elevation: const WidgetStatePropertyAll(0),
            constraints: const BoxConstraints(minHeight: 44),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: _query.isEmpty
              ? _buildSections(channelTree, subscribed)
              : _buildSearchResults(channelTree),
        ),
      ],
    );
  }

  Widget _buildSections(
    ChannelTree channelTree,
    Map<String, SubscriptionLevel> subscribed,
  ) {
    final unread = ref.watch(unreadProvider).value ?? const {};
    final rooms = ref.watch(qallRoomsProvider).value ?? const {};
    final favoriteIds = ref.watch(favoriteChannelsProvider);
    int byPath(Channel a, Channel b) =>
        channelTree.path(a.id)!.compareTo(channelTree.path(b.id)!);

    final activeRooms =
        rooms.values.where((r) => channelTree[r.roomId] != null).toList()..sort(
          (a, b) => channelTree
              .path(a.roomId)!
              .compareTo(channelTree.path(b.roomId)!),
        );
    // 見つからないID (削除・別サーバー) は表示しない
    final favorites =
        favoriteIds.map((id) => channelTree[id]).whereType<Channel>().toList()
          ..sort(byPath);
    final channels =
        subscribed.entries
            .where((e) => e.value != SubscriptionLevel.none)
            .where((e) => !favoriteIds.contains(e.key))
            .map((e) => channelTree[e.key])
            .whereType<Channel>()
            .where((c) => !c.archived)
            .toList()
          ..sort(byPath);

    Widget channelTile(Channel channel) => _ChannelTile(
      channelId: channel.id,
      title: channelTree.displayName(channel.id),
      unread: unread[channel.id],
      inCall: rooms.containsKey(channel.id),
      selected: channel.id == widget.selectedChannelId,
      onTap: () => _select(channel.id),
    );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (activeRooms.isNotEmpty) ...[
            const _SectionHeader(icon: Icons.graphic_eq, title: '通話中'),
            SliverList.builder(
              itemCount: activeRooms.length,
              itemBuilder: (context, i) => _RoomTile(
                room: activeRooms[i],
                tree: channelTree,
                selected: activeRooms[i].roomId == widget.selectedChannelId,
                onTap: () => _select(activeRooms[i].roomId),
              ),
            ),
          ],
          if (favorites.isNotEmpty) ...[
            const _SectionHeader(icon: Icons.star, title: 'お気に入り'),
            SliverList.builder(
              itemCount: favorites.length,
              itemBuilder: (context, i) => channelTile(favorites[i]),
            ),
          ],
          const _SectionHeader(icon: Icons.tag, title: '購読チャンネル'),
          if (channels.isEmpty && favorites.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('購読しているチャンネルがありません。上の検索からチャンネルを探せます。'),
              ),
            ),
          SliverList.builder(
            itemCount: channels.length,
            itemBuilder: (context, i) => channelTile(channels[i]),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ChannelTree channelTree) {
    final unread = ref.watch(unreadProvider).value ?? const {};
    final rooms = ref.watch(qallRoomsProvider).value ?? const {};
    final results = channelTree.search(_query);
    if (results.isEmpty) {
      return const Center(child: Text('見つかりませんでした'));
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length,
      itemBuilder: (context, i) {
        final channel = results[i];
        return _ChannelTile(
          channelId: channel.id,
          title: channelTree.displayName(channel.id),
          unread: unread[channel.id],
          inCall: rooms.containsKey(channel.id),
          selected: channel.id == widget.selectedChannelId,
          showFavoriteButton: true,
          onTap: () => _select(channel.id),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelTile extends ConsumerWidget {
  const _ChannelTile({
    required this.channelId,
    required this.title,
    required this.unread,
    required this.inCall,
    required this.selected,
    required this.onTap,
    this.showFavoriteButton = false,
  });

  final String channelId;
  final String title;
  final UnreadChannel? unread;
  final bool inCall;
  final bool selected;
  final VoidCallback onTap;

  /// 検索結果では星ボタンを出して、その場でお気に入りにできるようにする。
  final bool showFavoriteButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = unread?.count ?? 0;
    final theme = Theme.of(context);
    final favorite = ref.watch(
      favoriteChannelsProvider.select((ids) => ids.contains(channelId)),
    );
    return ListTile(
      dense: true,
      selected: selected,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: count > 0 ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inCall)
            Icon(Icons.graphic_eq, size: 18, color: theme.colorScheme.primary),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Badge(
              label: Text(count > 99 ? '99+' : '$count'),
              backgroundColor: unread!.noticeable
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
            ),
          ],
          if (showFavoriteButton) FavoriteChannelButton(channelId: channelId),
        ],
      ),
      onTap: onTap,
      onLongPress: () => _showMenu(context, ref, favorite),
    );
  }

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    bool favorite,
  ) async {
    final toggle = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              enabled: false,
            ),
            ListTile(
              leading: Icon(favorite ? Icons.star_outline : Icons.star),
              title: Text(favorite ? 'お気に入りから外す' : 'お気に入りに追加'),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (toggle == true) {
      ref.read(favoriteChannelsProvider.notifier).toggle(channelId);
    }
  }
}

class _RoomTile extends ConsumerWidget {
  const _RoomTile({
    required this.room,
    required this.tree,
    required this.selected,
    required this.onTap,
  });

  final QallRoom room;
  final ChannelTree tree;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(qallCallProvider);
    final userIds = room.userIds;
    return ListenableBuilder(
      listenable: call,
      builder: (context, _) {
        final joined = call.channelId == room.roomId;
        return ListTile(
          selected: selected,
          title: Text(
            tree.displayName(room.roomId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                for (final id in userIds.take(6))
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: UserAvatar(userId: id, radius: 11),
                  ),
                if (userIds.length > 6) Text('+${userIds.length - 6}'),
                if (room.isWebinar) ...[
                  const SizedBox(width: 4),
                  const Chip(
                    label: Text('ウェビナー'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
          trailing: joined
              ? const Chip(label: Text('参加中'))
              : FilledButton.tonalIcon(
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('参加'),
                  onPressed: () => joinCallAndOpen(context, ref, room.roomId),
                ),
          onTap: onTap,
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('読み込みに失敗しました\n$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('再試行')),
        ],
      ),
    );
  }
}
