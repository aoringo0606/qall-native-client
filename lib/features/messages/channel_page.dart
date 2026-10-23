import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/traq_api.dart';
import '../channels/favorite_channels.dart';
import '../qall/call_actions.dart';
import '../qall/call_bar.dart';
import '../qall/call_controller.dart';
import 'message_tile.dart';
import 'messages_controller.dart';

/// チャンネルのメッセージ一覧と投稿欄。
class ChannelPage extends ConsumerWidget {
  const ChannelPage({
    super.key,
    required this.channelId,
    this.showCallBar = true,
  });

  final String channelId;

  /// 2ペイン表示で親が通話バーを出している場合は false
  final bool showCallBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(channelTreeProvider).value;
    final channel = tree?[channelId];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tree?.displayName(channelId) ?? '',
              overflow: TextOverflow.ellipsis,
            ),
            if (channel != null && channel.topic.isNotEmpty)
              Text(
                channel.topic,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          FavoriteChannelButton(channelId: channelId),
          _CallButton(channelId: channelId),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _MessageList(channelId: channelId)),
          const Divider(height: 1),
          _Composer(channelId: channelId),
          if (showCallBar) const CallBar(),
        ],
      ),
    );
  }
}

class _CallButton extends ConsumerWidget {
  const _CallButton({required this.channelId});

  final String channelId;

  Future<void> _start(
    BuildContext context,
    WidgetRef ref, {
    required bool webinar,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(webinar ? 'ウェビナーを開始しますか？' : '通話を開始しますか？'),
        content: Text(
          webinar
              ? 'このチャンネルでウェビナーモードの Qall を開始します。'
                    '後から参加した人は発言権限なし (視聴のみ) で参加します。'
              : 'このチャンネルで Qall を開始します。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('開始'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await joinCallAndOpen(context, ref, channelId, webinar: webinar);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(qallCallProvider);
    final room = ref.watch(qallRoomsProvider).value?[channelId];
    return ListenableBuilder(
      listenable: call,
      builder: (context, _) {
        if (call.channelId == channelId) {
          return IconButton(
            tooltip: '通話画面',
            icon: const Icon(Icons.graphic_eq),
            onPressed: () => openCallPage(Navigator.of(context)),
          );
        }
        if (room != null) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.call, size: 18),
              label: Text('参加 (${room.userIds.length})'),
              onPressed: () => joinCallAndOpen(context, ref, channelId),
            ),
          );
        }
        return PopupMenuButton<bool>(
          tooltip: '通話を開始',
          icon: const Icon(Icons.add_call),
          onSelected: (webinar) => _start(context, ref, webinar: webinar),
          itemBuilder: (context) => const [
            PopupMenuItem(value: false, child: Text('Qall を開始')),
            PopupMenuItem(value: true, child: Text('ウェビナーモードで Qall を開始')),
          ],
        );
      },
    );
  }
}

class _MessageList extends ConsumerWidget {
  const _MessageList({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = messagesProvider(channelId);
    final state = ref.watch(provider);
    return switch (state) {
      AsyncData(value: final data) || AsyncLoading(value: final data?) =>
        data.messages.isEmpty
            ? const Center(child: Text('メッセージはまだありません'))
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: data.messages.length + (data.hasMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == data.messages.length) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      ref.read(provider.notifier).loadMore().catchError((_) {});
                    });
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final message = data.messages[i];
                  final older = i + 1 < data.messages.length
                      ? data.messages[i + 1]
                      : null;
                  return MessageTile(
                    message: message,
                    showHeader: _startsGroup(message, older),
                  );
                },
              ),
      AsyncError(:final error) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('メッセージを読み込めませんでした\n$error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.invalidate(provider),
              child: const Text('再試行'),
            ),
          ],
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  /// 同じ人の連投 (5分以内) はアイコンと名前を省略する。
  static bool _startsGroup(Message message, Message? older) =>
      older == null ||
      older.userId != message.userId ||
      message.createdAt.difference(older.createdAt) >
          const Duration(minutes: 5);
}

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.channelId});

  final String channelId;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(messagesProvider(widget.channelId).notifier).send(text);
      _controller.clear();
    } on TraqApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('送信できませんでした: ${e.message}')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'メッセージを入力',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => IconButton(
                tooltip: '送信',
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                onPressed: _controller.text.trim().isEmpty || _sending
                    ? null
                    : _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
