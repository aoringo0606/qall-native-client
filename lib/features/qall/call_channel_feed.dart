import 'dart:async';

import '../../core/models.dart';
import '../../core/traq_api.dart';
import '../../core/traq_ws.dart';

/// 通話中のチャンネルに投稿されたメッセージを受け取る。
///
/// traQ の WebSocket は1接続につき1チャンネルしか「閲覧中」にできないため、
/// 画面で別のチャンネルを開いていても弾幕・読み上げが動くよう、通話専用の接続を張る。
class CallChannelFeed {
  CallChannelFeed(TraqApi api, this.channelId) : _api = api {
    _ws = TraqWebSocket(api);
    _unwatch = _ws.watchChannel(channelId);
    _subscription = _ws.on('MESSAGE_CREATED').listen(_onCreated);
    _ws.connect();
  }

  final TraqApi _api;
  final String channelId;
  late final TraqWebSocket _ws;
  late final void Function() _unwatch;
  late final StreamSubscription<TraqEvent> _subscription;
  final _messages = StreamController<Message>.broadcast();

  Stream<Message> get messages => _messages.stream;

  Future<void> _onCreated(TraqEvent event) async {
    final id = event.body['id'];
    if (id is! String) return;
    try {
      final message = await _api.getMessage(id);
      if (message.channelId == channelId && !_messages.isClosed) {
        _messages.add(message);
      }
    } on TraqApiException {
      // 取れなかったものは流さない
    }
  }

  Future<void> dispose() async {
    _unwatch();
    await _subscription.cancel();
    await _ws.dispose();
    await _messages.close();
  }
}
