import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const defaultTraqOrigin = 'https://q.trap.jp';

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
  final String token;
}

/// セッションCookieを Keychain / Android Keystore に保存する。
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _originKey = 'traq_origin';
  static const _tokenKey = 'traq_session';

  Future<StoredSession?> load() async {
    final origin = await _storage.read(key: _originKey);
    final token = await _storage.read(key: _tokenKey);
    if (origin == null || token == null) return null;
    return StoredSession(origin: origin, token: token);
  }

  Future<String> lastOrigin() async =>
      await _storage.read(key: _originKey) ?? defaultTraqOrigin;

  Future<void> save(StoredSession session) async {
    await _storage.write(key: _originKey, value: session.origin);
    await _storage.write(key: _tokenKey, value: session.token);
  }

  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
