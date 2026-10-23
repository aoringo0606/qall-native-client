import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'traq_api.dart';

/// OAuth2 のリダイレクト先に使う URI スキーム。
///
/// Bundle ID / applicationId とは切り離した固定値にしている。フォークやビルドごとに
/// Bundle ID を変えても、同じ OAuth2 クライアント (= 同じコールバックURL) を使える。
/// 変える場合は android/app/src/main/AndroidManifest.xml の CallbackActivity と、
/// traQ に登録したクライアントのコールバックURLもそろえること。
const oauthRedirectScheme = 'io.github.kaitoyama.qall';
const oauthRedirectUri = '$oauthRedirectScheme:/oauth2/callback';

/// read: メッセージ・WebSocket など / write: 投稿・既読化 / qall: Qall (WebRTC)
const oauthScopes = ['read', 'write', 'qall'];

/// ユーザーがブラウザを閉じてログインをやめた。
class OAuthCanceledException implements Exception {
  const OAuthCanceledException();
}

/// traQ の OAuth2 (認可コード + PKCE) でアクセストークンを取得する。
///
/// traQ は http(s) 以外のリダイレクト先に対して S256 の PKCE を必須にしている。
class TraqOAuth {
  TraqOAuth({required this.origin, required this.clientId});

  /// 例: `https://q.trap.jp`
  final String origin;
  final String clientId;

  static final _random = Random.secure();

  /// ブラウザ (iOS: ASWebAuthenticationSession / Android: Custom Tabs) で
  /// 認可画面を開き、アクセストークンを返す。
  ///
  /// やめた場合は [OAuthCanceledException]、それ以外の失敗は [TraqApiException] を投げる。
  Future<String> authorize() async {
    final verifier = _randomString(32);
    final state = _randomString(16);
    final authorizeUri = Uri.parse('$origin/api/v3/oauth2/authorize').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': oauthRedirectUri,
        'scope': oauthScopes.join(' '),
        'state': state,
        'code_challenge': _codeChallenge(verifier),
        'code_challenge_method': 'S256',
      },
    );

    final String result;
    try {
      // Safari / Chrome のログイン状態を使えるよう、ephemeral にはしない
      result = await FlutterWebAuth2.authenticate(
        url: authorizeUri.toString(),
        callbackUrlScheme: oauthRedirectScheme,
      );
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') throw const OAuthCanceledException();
      throw TraqApiException('ログイン画面を開けませんでした (${e.message ?? e.code})');
    }

    final params = Uri.parse(result).queryParameters;
    if (params['state'] != state) {
      throw const TraqApiException('ログインに失敗しました (state が一致しません)');
    }
    if (params['error'] case final error?) {
      if (error == 'access_denied') throw const OAuthCanceledException();
      throw TraqApiException(
        _describeError(error, params['error_description']),
      );
    }
    final code = params['code'];
    if (code == null || code.isEmpty) {
      throw const TraqApiException('ログインに失敗しました (認可コードがありません)');
    }
    return _exchangeCode(code, verifier);
  }

  Future<String> _exchangeCode(String code, String verifier) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    try {
      final res = await dio.post<Map<String, dynamic>>(
        '$origin/api/v3/oauth2/token',
        data: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': oauthRedirectUri,
          'client_id': clientId,
          'code_verifier': verifier,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final token = res.data?['access_token'];
      if (token is! String || token.isEmpty) {
        throw const TraqApiException('アクセストークンを取得できませんでした');
      }
      // traQ はクライアントに登録されていないスコープを黙って外し、
      // 要求と違うときだけ scope を返す
      if (res.data?['scope'] case final String granted) {
        final missing = oauthScopes.toSet().difference(
          granted.split(' ').toSet(),
        );
        if (missing.isNotEmpty) {
          throw TraqApiException(
            'OAuth2 クライアントに必要なスコープ (${missing.join(', ')}) がありません',
          );
        }
      }
      return token;
    } on DioException catch (e) {
      final data = e.response?.data;
      final error = data is Map ? data['error'] as String? : null;
      throw TraqApiException(
        error != null
            ? _describeError(error, data['error_description'] as String?)
            : 'サーバーに接続できませんでした',
        statusCode: e.response?.statusCode,
      );
    } finally {
      dio.close();
    }
  }

  static String _describeError(String error, String? description) =>
      switch (error) {
        'invalid_client' || 'unauthorized_client' => 'OAuth2 クライアントIDが正しくありません',
        'invalid_scope' => 'OAuth2 クライアントに必要なスコープ (read, write, qall) がありません',
        _ =>
          'ログインに失敗しました ($error${description != null ? ': $description' : ''})',
      };

  /// [bytes] バイトの乱数を base64url (パディングなし) にしたもの。
  static String _randomString(int bytes) => base64Url
      .encode(List<int>.generate(bytes, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  static String _codeChallenge(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');
}
