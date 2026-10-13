import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import 'traq_api.dart';

/// traQ の WebSocket から届くイベント。
class TraqEvent {
  const TraqEvent(this.type, this.body);

  /// (再)接続に成功したときに流す疑似イベント。
  /// 切断中に取りこぼした変更を取り直すために使う。
  static const connected = '_CONNECTED';

  final String type;
  final Map<String, dynamic> body;
}

/// `/api/v3/ws` への接続を管理し、切断時は自動で再接続する。
class TraqWebSocket {
  TraqWebSocket(this._api);

  final TraqApi _api;
  final _events = StreamController<TraqEvent>.broadcast();
  final _random = Random();

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _disposed = false;
  bool _connecting = false;
  final List<(Object, String)> _viewers = [];
  String? _sentViewState;

  Stream<TraqEvent> get events => _events.stream;

  Stream<TraqEvent> on(String type) => events.where((e) => e.type == type);

  bool get isConnected => _channel != null && !_connecting;

  Future<void> connect() async {
    if (_disposed || _connecting || _channel != null) return;
    _connecting = true;
    _reconnectTimer?.cancel();
    try {
      final channel = IOWebSocketChannel.connect(
        _api.webSocketUri,
        headers: _api.authHeaders,
        pingInterval: const Duration(seconds: 30),
        connectTimeout: const Duration(seconds: 15),
      );
      await channel.ready;
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _sentViewState = null;
      _attempt = 0;
      _subscription = channel.stream.listen(
        _handleMessage,
        onDone: _handleClosed,
        onError: (Object _) => _handleClosed(),
        cancelOnError: true,
      );
      _sendViewState();
      _events.add(const TraqEvent(TraqEvent.connected, {}));
    } catch (e) {
      debugPrint('traQ WebSocket connect failed: $e');
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  /// アプリ復帰時などに、切れていれば即座につなぎ直す。
  void ensureConnected() {
    if (_channel == null && !_connecting) {
      _attempt = 0;
      connect();
    }
  }

  /// チャンネルを閲覧中にする。そのチャンネルの
  /// `MESSAGE_CREATED` / `MESSAGE_UPDATED` / `MESSAGE_DELETED` が届くようになる。
  ///
  /// traQ の仕様上 1接続につき1チャンネルまでなので、複数の画面から呼ばれた場合は
  /// 最後に呼んだもの (が閉じられたらその前のもの) が有効になる。
  /// 戻り値の関数を呼ぶと閲覧をやめる。
  void Function() watchChannel(String channelId) {
    final token = Object();
    _viewers.add((token, channelId));
    _sendViewState();
    return () {
      _viewers.removeWhere((v) => identical(v.$1, token));
      _sendViewState();
    };
  }

  String? get viewingChannelId => _viewers.isEmpty ? null : _viewers.last.$2;

  void _sendViewState() {
    final id = viewingChannelId;
    if (id == _sentViewState) return;
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(id == null ? 'viewstate:' : 'viewstate:$id:monitoring');
    _sentViewState = id;
  }

  void _handleMessage(dynamic data) {
    if (data is! String) return;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type == null) return;
      final body = json['body'];
      _events.add(TraqEvent(type, body is Map<String, dynamic> ? body : {}));
    } on FormatException {
      // 不正なメッセージは無視
    }
  }

  void _handleClosed() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    // 1, 2, 4, ... 最大30秒 + ジッター
    final seconds = min(30, 1 << min(_attempt, 5));
    _attempt++;
    _reconnectTimer = Timer(
      Duration(milliseconds: seconds * 1000 + _random.nextInt(1000)),
      connect,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    await _events.close();
  }
}
