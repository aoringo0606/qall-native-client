import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const defaultTraqOrigin = 'https://q.trap.jp';

/// 既定の OAuth2 クライアントID (q.trap.jp に登録した公開クライアント)。
/// 別のクライアントを使うときは `--dart-define=TRAQ_CLIENT_ID=...` で上書きする。
const defaultTraqClientId = String.fromEnvironment(
  'TRAQ_CLIENT_ID',
  defaultValue: 'SVi9KL1akUgMRgEN0G9ItOgzngcrf6QAvM8B',
);

/// `q.trap.jp/` や `https://q.trap.jp/channels/gps` を `https://q.trap.jp` にそろえる。
String normalizeOrigin(String input) {
  var origin = input.trim();
  if (!origin.startsWith(RegExp('https?://'))) origin = 'https://$origin';
  final uri = Uri.parse(origin);
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString();
}

class StoredSession {
  const StoredSession({required this.origin, required this.token});

  final String origin;

  /// OAuth2 のアクセストークン。
  final String token;
}

/// ログイン画面の「詳細設定」の値。
class LoginSettings {
  const LoginSettings({required this.origin, required this.clientId});

  final String origin;
  final String clientId;
}

/// アクセストークンを Keychain / Android Keystore に保存する。
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _originKey = 'traq_origin';
  static const _clientIdKey = 'traq_client_id';
  static const _tokenKey = 'traq_access_token';

  /// 以前のバージョンが保存していたセッションCookie。
  static const _legacySessionKey = 'traq_session';

  Future<StoredSession?> load() async {
    // セッションCookieでのログインはやめたので、残っていれば消して再ログインしてもらう
    await _storage.delete(key: _legacySessionKey);
    final origin = await _storage.read(key: _originKey);
    final token = await _storage.read(key: _tokenKey);
    if (origin == null || token == null) return null;
    return StoredSession(origin: origin, token: token);
  }

  Future<LoginSettings> loginSettings() async {
    final clientId = await _storage.read(key: _clientIdKey);
    return LoginSettings(
      origin: await _storage.read(key: _originKey) ?? defaultTraqOrigin,
      clientId: (clientId == null || clientId.isEmpty)
          ? defaultTraqClientId
          : clientId,
    );
  }

  Future<void> save(StoredSession session, {required String clientId}) async {
    await _storage.write(key: _originKey, value: session.origin);
    await _storage.write(key: _clientIdKey, value: clientId);
    await _storage.write(key: _tokenKey, value: session.token);
  }

  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
