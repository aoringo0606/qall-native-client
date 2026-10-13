import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/traq_api.dart';
import '../../core/traq_ws.dart';

class MessagesState {
  const MessagesState({
    required this.messages,
    required this.hasMore,
    this.loadingMore = false,
  });

  /// 新しい順
  final List<Message> messages;
  final bool hasMore;
  final bool loadingMore;

  MessagesState copyWith({
    List<Message>? messages,
    bool? hasMore,
    bool? loadingMore,
  }) => MessagesState(
    messages: messages ?? this.messages,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

final messagesProvider = AsyncNotifierProvider.autoDispose
    .family<MessagesNotifier, MessagesState, String>(MessagesNotifier.new);

/// 1チャンネル分のメッセージ。画面を開いている間だけ WebSocket で更新を受け取る。
class MessagesNotifier extends AsyncNotifier<MessagesState> {
  MessagesNotifier(this.channelId);

  final String channelId;

  static const _pageSize = 50;

  Timer? _readDebounce;

  TraqApi get _api => ref.read(apiProvider);

  @override
  Future<MessagesState> build() async {
    final ws = ref.watch(traqWsProvider);
    final unwatch = ws.watchChannel(channelId);
    final sub = ws.events.listen(_onEvent);
    ref.onDispose(() {
      unwatch();
      sub.cancel();
      _readDebounce?.cancel();
    });

    final messages = await ref.watch(apiProvider).getMessages(channelId);
    _markRead();
    return MessagesState(
      messages: messages,
      hasMore: messages.length >= _pageSize,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    if (current.messages.isEmpty) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final older = await _api.getMessages(
        channelId,
        until: current.messages.last.createdAt,
      );
      if (!ref.mounted) return;
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          messages: _merge(latest.messages, older),
          hasMore: older.length >= _pageSize,
          loadingMore: false,
        ),
      );
    } on TraqApiException {
      if (!ref.mounted) return;
      state = AsyncData((state.value ?? current).copyWith(loadingMore: false));
      rethrow;
    }
  }

  Future<void> send(String content) async {
    final message = await _api.postMessage(channelId, content);
    if (ref.mounted) _upsert(message);
  }

  void _onEvent(TraqEvent event) {
    final id = event.body['id'];
    switch (event.type) {
      case 'MESSAGE_CREATED' || 'MESSAGE_UPDATED' when id is String:
        unawaited(
          _fetchAndUpsert(id, onlyIfKnown: event.type != 'MESSAGE_CREATED'),
        );
      case 'MESSAGE_DELETED' when id is String:
        final current = state.value;
        if (current == null) return;
        state = AsyncData(
          current.copyWith(
            messages: current.messages.where((m) => m.id != id).toList(),
          ),
        );
      case TraqEvent.connected:
        unawaited(_catchUp());
    }
  }

  Future<void> _fetchAndUpsert(String id, {required bool onlyIfKnown}) async {
    final current = state.value;
    if (current == null) return;
    if (onlyIfKnown && !current.messages.any((m) => m.id == id)) return;
    try {
      final message = await _api.getMessage(id);
      if (!ref.mounted || message.channelId != channelId) return;
      _upsert(message);
      _markRead();
    } on TraqApiException {
      // 取れなかったものは表示しない
    }
  }

  /// 再接続時に、切断中に投稿されたメッセージを取り直す。
  Future<void> _catchUp() async {
    final current = state.value;
    if (current == null) return;
    try {
      final latest = await _api.getMessages(channelId);
      if (!ref.mounted) return;
      final now = state.value ?? current;
      state = AsyncData(now.copyWith(messages: _merge(now.messages, latest)));
    } on TraqApiException {
      // 次の再接続で取り直す
    }
  }

  void _upsert(Message message) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(messages: _merge(current.messages, [message])),
    );
  }

  static List<Message> _merge(List<Message> base, List<Message> incoming) {
    final byId = {for (final m in base) m.id: m};
    for (final m in incoming) {
      byId[m.id] = m;
    }
    return byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void _markRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(unreadProvider.notifier).markRead(channelId);
    });
  }
}
