import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/channel_tree.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../widgets/user_avatar.dart';
import '../qall/call_actions.dart';
import '../qall/call_controller.dart';

/// 通話中のルームと、購読しているチャンネルの一覧。
class ChannelList extends ConsumerWidget {
  const ChannelList({
    super.key,
    required this.onSelect,
    this.selectedChannelId,
  });

  final void Function(String channelId) onSelect;
  final String? selectedChannelId;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(subscriptionsProvider);
    ref.invalidate(unreadProvider);
    ref.invalidate(qallRoomsProvider);
    await Future.wait([
      ref.read(subscriptionsProvider.future),
      ref.read(unreadProvider.future),
      ref.read(qallRoomsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(channelTreeProvider);
    final subscriptions = ref.watch(subscriptionsProvider);
    final unread = ref.watch(unreadProvider).value ?? const {};
    final rooms = ref.watch(qallRoomsProvider).value ?? const {};

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

    final activeRooms =
        rooms.values.where((r) => channelTree[r.roomId] != null).toList()..sort(
          (a, b) => channelTree
              .path(a.roomId)!
              .compareTo(channelTree.path(b.roomId)!),
        );
    final channels =
        subscribed.entries
            .where((e) => e.value != SubscriptionLevel.none)
            .map((e) => channelTree[e.key])
            .whereType<Channel>()
            .where((c) => !c.archived)
            .toList()
          ..sort(
            (a, b) =>
                channelTree.path(a.id)!.compareTo(channelTree.path(b.id)!),
          );

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
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
                selected: activeRooms[i].roomId == selectedChannelId,
                onTap: () => onSelect(activeRooms[i].roomId),
              ),
            ),
          ],
          const _SectionHeader(icon: Icons.tag, title: '購読チャンネル'),
          if (channels.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('購読しているチャンネルがありません。traQ のWeb版でチャンネルを購読してください。'),
              ),
            ),
          SliverList.builder(
            itemCount: channels.length,
            itemBuilder: (context, i) {
              final channel = channels[i];
              return _ChannelTile(
                title: channelTree.displayName(channel.id),
                unread: unread[channel.id],
                inCall: rooms.containsKey(channel.id),
                selected: channel.id == selectedChannelId,
                onTap: () => onSelect(channel.id),
              );
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
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

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.title,
    required this.unread,
    required this.inCall,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final UnreadChannel? unread;
  final bool inCall;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = unread?.count ?? 0;
    final theme = Theme.of(context);
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
        ],
      ),
      onTap: onTap,
    );
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
