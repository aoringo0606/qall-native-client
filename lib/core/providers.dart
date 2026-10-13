import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'channel_tree.dart';
import 'models.dart';
import 'session_store.dart';
import 'traq_api.dart';
import 'traq_ws.dart';

// ---- 認証 ----

class AuthSession {
  const AuthSession({required this.api, required this.me});

  final TraqApi api;
  final Me me;
}

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    final store = ref.read(sessionStoreProvider);
    final saved = await store.load();
    if (saved == null) return null;

    final api = _createApi(saved.origin, saved.token);
    try {
      return AuthSession(api: api, me: await api.getMe());
    } on TraqApiException catch (e) {
      if (!e.isUnauthorized) rethrow;
      await store.clearToken();
      return null;
    }
  }

  TraqApi _createApi(String origin, String? token) {
    final store = ref.read(sessionStoreProvider);
    return TraqApi(
      origin: origin,
      sessionToken: token,
      onSessionTokenChanged: (newToken) =>
          store.save(StoredSession(origin: origin, token: newToken)),
      onUnauthorized: _handleUnauthorized,
    );
  }

  /// 失敗したら [TraqApiException] を投げる (状態は変えない)。
  Future<void> login({
    required String origin,
    required String name,
    required String password,
  }) async {
    final api = _createApi(origin, null);
    await api.login(name: name, password: password);
    final me = await api.getMe();
    state = AsyncData(AuthSession(api: api, me: me));
  }

  Future<void> logout() async {
    final session = state.value;
    try {
      await session?.api.logout();
    } on TraqApiException {
      // オフラインでもローカルのセッションは消す
    }
    await ref.read(sessionStoreProvider).clearToken();
    state = const AsyncData(null);
  }

  void _handleUnauthorized() {
    if (state.value == null) return;
    ref.read(sessionStoreProvider).clearToken();
    state = const AsyncData(null);
  }
}

/// ログイン済みの画面からのみ読むこと。
final sessionProvider = Provider<AuthSession>((ref) {
  final session = ref.watch(authControllerProvider).value;
  if (session == null) throw StateError('ログインしていません');
  return session;
});

final apiProvider = Provider<TraqApi>((ref) => ref.watch(sessionProvider).api);

final traqWsProvider = Provider<TraqWebSocket>((ref) {
  final ws = TraqWebSocket(ref.watch(apiProvider));
  ws.connect();
  ref.onDispose(ws.dispose);
  return ws;
});

/// WebSocket の特定イベントを受けたらプロバイダーを再取得させる。
void _refreshOn(Ref ref, Set<String> eventTypes) {
  final sub = ref
      .watch(traqWsProvider)
      .events
      .where((e) => eventTypes.contains(e.type))
      .listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
}

// ---- マスターデータ ----

final usersProvider = FutureProvider<Map<String, User>>((ref) async {
  _refreshOn(ref, {'USER_JOINED', 'USER_UPDATED'});
  final users = await ref.watch(apiProvider).getUsers();
  return {for (final u in users) u.id: u};
});

final channelTreeProvider = FutureProvider<ChannelTree>((ref) async {
  _refreshOn(ref, {'CHANNEL_CREATED', 'CHANNEL_UPDATED', 'CHANNEL_DELETED'});
  return ChannelTree(await ref.watch(apiProvider).getChannels());
});

final subscriptionsProvider = FutureProvider<Map<String, SubscriptionLevel>>((
  ref,
) async {
  _refreshOn(ref, {TraqEvent.connected});
  return ref.watch(apiProvider).getSubscriptions();
});

// ---- 未読 ----

final unreadProvider =
    AsyncNotifierProvider<UnreadNotifier, Map<String, UnreadChannel>>(
      UnreadNotifier.new,
    );

class UnreadNotifier extends AsyncNotifier<Map<String, UnreadChannel>> {
  Timer? _debounce;

  @override
  Future<Map<String, UnreadChannel>> build() async {
    final ws = ref.watch(traqWsProvider);
    final sub = ws.events.listen((event) {
      switch (event.type) {
        case 'MESSAGE_CREATED' || TraqEvent.connected:
          _scheduleRefresh();
        case 'MESSAGE_READ':
          if (event.body['id'] case final String channelId) _remove(channelId);
      }
    });
    ref.onDispose(() {
      sub.cancel();
      _debounce?.cancel();
    });
    return _fetch();
  }

  Future<Map<String, UnreadChannel>> _fetch() async {
    final list = await ref.read(apiProvider).getUnreadChannels();
    return {for (final u in list) u.channelId: u};
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () async {
      try {
        state = AsyncData(await _fetch());
      } on TraqApiException {
        // 次のイベントで取り直す
      }
    });
  }

  void _remove(String channelId) {
    final current = state.value;
    if (current == null || !current.containsKey(channelId)) return;
    state = AsyncData({...current}..remove(channelId));
  }

  Future<void> markRead(String channelId) async {
    _remove(channelId);
    try {
      await ref.read(apiProvider).markChannelRead(channelId);
    } on TraqApiException {
      // 既読化の失敗は致命的ではない
    }
  }
}

// ---- Qall ルーム一覧 ----

final qallRoomsProvider =
    AsyncNotifierProvider<QallRoomsNotifier, Map<String, QallRoom>>(
      QallRoomsNotifier.new,
    );

/// 参加者がいるルーム (= 通話中のチャンネル) をチャンネルIDで引けるようにしたもの。
class QallRoomsNotifier extends AsyncNotifier<Map<String, QallRoom>> {
  @override
  Future<Map<String, QallRoom>> build() async {
    final ws = ref.watch(traqWsProvider);
    final sub = ws.events.listen((event) async {
      switch (event.type) {
        case 'QALL_ROOM_STATE_CHANGED':
          final rooms = (event.body['roomStates'] as List<dynamic>? ?? const [])
              .map((r) => QallRoom.fromJson(r as Map<String, dynamic>));
          state = AsyncData(_index(rooms));
        case TraqEvent.connected:
          try {
            state = AsyncData(
              _index(await ref.read(apiProvider).getQallRooms()),
            );
          } on TraqApiException {
            // 次のイベントで更新される
          }
      }
    });
    ref.onDispose(sub.cancel);
    return _index(await ref.read(apiProvider).getQallRooms());
  }

  static Map<String, QallRoom> _index(Iterable<QallRoom> rooms) => {
    for (final room in rooms)
      if (room.participants.isNotEmpty) room.roomId: room,
  };
}
