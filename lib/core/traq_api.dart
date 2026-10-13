import 'dart:io' show Cookie;

import 'package:dio/dio.dart';

import 'models.dart';

/// traQ のセッションCookie名。
///
/// Qall 系 API (`/qall/*`) は `WebRTC` 権限を要求するが、OAuth2 の
/// read/write スコープにはこの権限が含まれない。そのためこのアプリは
/// Web版と同じくセッションCookieで認証する。
const sessionCookieName = 'r_session';

class TraqApiException implements Exception {
  const TraqApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// traQ API v3 のクライアント。
class TraqApi {
  TraqApi({
    required this.origin,
    this._sessionToken,
    this.onSessionTokenChanged,
    this.onUnauthorized,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: '$origin/api/v3',
           connectTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 30),
           followRedirects: false,
         ),
       ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers.addAll(authHeaders);
          handler.next(options);
        },
        onResponse: (response, handler) {
          _captureSessionCookie(response.headers);
          handler.next(response);
        },
        onError: (error, handler) {
          final response = error.response;
          if (response != null) {
            _captureSessionCookie(response.headers);
            if (response.statusCode == 401 && _sessionToken != null) {
              onUnauthorized?.call();
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  /// 例: `https://q.trap.jp`
  final String origin;
  final Dio _dio;
  String? _sessionToken;

  /// サーバーがセッションを再発行したときに呼ばれる (永続化用)。
  final void Function(String token)? onSessionTokenChanged;

  /// ログイン済みのはずのリクエストが 401 になったときに呼ばれる。
  void Function()? onUnauthorized;

  String? get sessionToken => _sessionToken;

  /// WebSocket や画像取得など Dio 以外の通信にも付ける認証ヘッダー。
  Map<String, String> get authHeaders => {
    if (_sessionToken case final token?) 'Cookie': '$sessionCookieName=$token',
  };

  Uri get webSocketUri {
    final base = Uri.parse(origin);
    return base.replace(
      scheme: base.scheme == 'http' ? 'ws' : 'wss',
      path: '/api/v3/ws',
    );
  }

  String userIconUrl(String userName) =>
      '$origin/api/v3/public/icon/${Uri.encodeComponent(userName)}';

  String fileThumbnailUrl(String fileId) =>
      '$origin/api/v3/files/$fileId/thumbnail';

  String fileUrl(String fileId) => '$origin/files/$fileId';

  String stampImageUrl(String stampId) =>
      '$origin/api/v3/stamps/$stampId/image';

  void _captureSessionCookie(Headers headers) {
    for (final value in headers['set-cookie'] ?? const <String>[]) {
      final Cookie cookie;
      try {
        cookie = Cookie.fromSetCookieValue(value);
      } on FormatException {
        continue;
      }
      if (cookie.name != sessionCookieName || cookie.value.isEmpty) continue;
      if (cookie.value == _sessionToken) continue;
      _sessionToken = cookie.value;
      onSessionTokenChanged?.call(cookie.value);
    }
  }

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final serverMessage = data is Map ? data['message'] as String? : null;
      throw TraqApiException(
        serverMessage ??
            switch (status) {
              null => 'サーバーに接続できませんでした',
              401 => 'ログインが必要です',
              403 => '権限がありません',
              404 => '見つかりません',
              _ => 'エラーが発生しました ($status)',
            },
        statusCode: status,
      );
    }
  }

  // ---- 認証 ----

  /// ユーザー名とパスワードでログインし、セッションCookieを取得する。
  Future<void> login({required String name, required String password}) =>
      _call(() async {
        await _dio.post<void>(
          '/login',
          data: {'name': name, 'password': password},
        );
        if (_sessionToken == null) {
          throw const TraqApiException('セッションCookieを取得できませんでした');
        }
      });

  Future<void> logout() => _call(() => _dio.post<void>('/logout'));

  // ---- ユーザー ----

  Future<Me> getMe() => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>('/users/me');
    return Me.fromJson(res.data!);
  });

  Future<List<User>> getUsers() => _call(() async {
    final res = await _dio.get<List<dynamic>>('/users');
    return res.data!
        .map((u) => User.fromJson(u as Map<String, dynamic>))
        .toList();
  });

  // ---- チャンネル ----

  Future<List<Channel>> getChannels() => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>('/channels');
    return (res.data!['public'] as List<dynamic>)
        .map((c) => Channel.fromJson(c as Map<String, dynamic>))
        .toList();
  });

  /// 購読しているチャンネルIDと購読レベル。
  Future<Map<String, SubscriptionLevel>> getSubscriptions() => _call(() async {
    final res = await _dio.get<List<dynamic>>('/users/me/subscriptions');
    return {
      for (final s in res.data!.cast<Map<String, dynamic>>())
        s['channelId'] as String: SubscriptionLevel.fromInt(
          s['level'] as int? ?? 0,
        ),
    };
  });

  Future<List<UnreadChannel>> getUnreadChannels() => _call(() async {
    final res = await _dio.get<List<dynamic>>('/users/me/unread');
    return res.data!
        .map((u) => UnreadChannel.fromJson(u as Map<String, dynamic>))
        .toList();
  });

  Future<void> markChannelRead(String channelId) =>
      _call(() => _dio.delete<void>('/users/me/unread/$channelId'));

  // ---- メッセージ ----

  /// 新しい順に [limit] 件取得する。[until] を指定するとそれより前のものを取得する。
  Future<List<Message>> getMessages(
    String channelId, {
    int limit = 50,
    DateTime? until,
  }) => _call(() async {
    final res = await _dio.get<List<dynamic>>(
      '/channels/$channelId/messages',
      queryParameters: {
        'limit': limit,
        'order': 'desc',
        if (until != null) 'until': until.toUtc().toIso8601String(),
      },
    );
    return res.data!
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList();
  });

  Future<Message> getMessage(String messageId) => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>('/messages/$messageId');
    return Message.fromJson(res.data!);
  });

  Future<Message> postMessage(String channelId, String content) =>
      _call(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/channels/$channelId/messages',
          // embed: メンションやチャンネルリンクをサーバー側で埋め込み形式に変換する
          data: {'content': content, 'embed': true},
        );
        return Message.fromJson(res.data!);
      });

  // ---- Qall ----

  /// LiveKit サーバーの URL。
  Future<String> getQallEndpoint() => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>('/qall/endpoints');
    return res.data!['endpoint'] as String;
  });

  /// ルーム (= チャンネル) に参加するための LiveKit トークン。
  Future<String> getQallToken(String roomId, {bool isWebinar = false}) =>
      _call(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          '/qall/token',
          queryParameters: {'roomId': roomId, 'isWebinar': isWebinar},
        );
        return res.data!['token'] as String;
      });

  Future<List<QallRoom>> getQallRooms() => _call(() async {
    final res = await _dio.get<List<dynamic>?>('/qall/rooms');
    return (res.data ?? const [])
        .map((r) => QallRoom.fromJson(r as Map<String, dynamic>))
        .toList();
  });
}
