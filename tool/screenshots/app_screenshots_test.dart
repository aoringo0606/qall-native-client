// UI のスクリーンショットをダミーデータで生成する。実サーバーには接続しない。
//
// 日本語フォント (Noto Sans JP の Regular/Medium/Bold の .ttf) を置いたディレクトリを指定して実行する:
//
//   QALL_SCREENSHOT_FONT_DIR=/path/to/fonts flutter test tool/screenshots
//
// 画像は docs/screenshots/ に実機と同じ解像度 (スマホ 3倍 / iPad 2倍) で出力される。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qall/app.dart';
import 'package:qall/core/models.dart';
import 'package:qall/core/providers.dart';
import 'package:qall/core/session_store.dart';
import 'package:qall/core/traq_api.dart';
import 'package:qall/core/traq_ws.dart';
import 'package:qall/features/qall/call_controller.dart';
import 'package:qall/features/settings/call_settings.dart';
import 'package:qall/widgets/stamp_image.dart';
import 'package:qall/widgets/user_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---- ダミーデータ ----

const _me = Me(id: 'u-me', name: 'kaito', displayName: 'かいと');

const _users = [
  User(id: 'u-me', name: 'kaito', displayName: 'かいと', bot: false),
  User(id: 'u-hana', name: 'hana', displayName: 'はな', bot: false),
  User(id: 'u-ryo', name: 'ryo', displayName: 'りょう', bot: false),
  User(id: 'u-mio', name: 'mio', displayName: 'みお', bot: false),
  User(id: 'u-ken', name: 'kenta', displayName: 'けんた', bot: false),
  User(id: 'u-yuki', name: 'yuki', displayName: 'ゆき', bot: false),
  User(id: 'u-sora', name: 'sora', displayName: 'そら', bot: false),
];

const _channels = [
  Channel(id: 'c-general', parentId: null, name: 'general', archived: false),
  Channel(id: 'c-random', parentId: null, name: 'random', archived: false),
  Channel(id: 'c-team', parentId: null, name: 'team', archived: false),
  Channel(
    id: 'c-qall',
    parentId: 'c-team',
    name: 'qall-native',
    archived: false,
    topic: 'Qall ネイティブクライアント開発',
  ),
  Channel(id: 'c-sysad', parentId: 'c-team', name: 'SysAd', archived: false),
  Channel(id: 'c-event', parentId: null, name: 'event', archived: false),
  Channel(
    id: 'c-hack',
    parentId: 'c-event',
    name: 'hackathon',
    archived: false,
  ),
  Channel(id: 'c-gps', parentId: null, name: 'gps', archived: false),
  Channel(id: 'c-times', parentId: 'c-gps', name: 'times', archived: false),
  Channel(id: 'c-mytimes', parentId: 'c-times', name: 'kaito', archived: false),
];

const _callChannel = 'c-qall';

String _identity(String userId, int n) =>
    '${userId}_01890f5e-2b5a-7cf3-9a8e-${n.toString().padLeft(12, '0')}';

QallParticipant _participant(String userId, int n) => QallParticipant(
  identity: _identity(userId, n),
  joinedAt: DateTime(2026),
  canPublish: true,
);

final _rooms = [
  QallRoom(
    roomId: _callChannel,
    isWebinar: false,
    participants: [
      _participant('u-me', 1),
      _participant('u-hana', 2),
      _participant('u-ryo', 3),
      _participant('u-mio', 4),
    ],
  ),
  QallRoom(
    roomId: 'c-hack',
    isWebinar: false,
    participants: [
      for (final (i, u) in ['u-ken', 'u-yuki', 'u-sora'].indexed)
        _participant(u, 10 + i),
    ],
  ),
];

List<Message> _messages() {
  final today = DateTime.now();
  DateTime at(int h, int m) =>
      DateTime(today.year, today.month, today.day, h, m);
  var n = 0;
  Message msg(String user, DateTime time, String content, {int stamps = 0}) =>
      Message(
        id: 'm${n++}',
        userId: user,
        channelId: _callChannel,
        content: content,
        createdAt: time,
        updatedAt: time,
        stampCount: stamps,
      );
  return [
    msg('u-mio', at(21, 14), '今から画面共有しますね〜', stamps: 2),
    msg('u-ryo', at(21, 12), '了解、Qall 入ります'),
    msg(
      'u-hana',
      at(21, 10),
      '!{"type":"user","raw":"@ryo","id":"u-ryo"} 21時から動作確認しよう！',
    ),
    msg('u-hana', at(21, 9), 'iPad の2ペイン表示いい感じ'),
    msg(
      'u-me',
      at(20, 58),
      'Android でスリープしても通話が切れないのを確認しました！\n'
          '詳細: https://github.com/kaitoyama/qall-native-client',
      stamps: 5,
    ),
    msg('u-ryo', at(20, 41), 'iOS の Broadcast Extension のビルド通った？'),
    msg('u-me', at(20, 40), 'CI で確認中です'),
  ];
}

// ---- フェイク ----

class _FakeApi extends TraqApi {
  _FakeApi() : super(origin: defaultTraqOrigin, sessionToken: 'dummy');

  @override
  Future<Me> getMe() async => _me;

  @override
  Future<List<User>> getUsers() async => _users;

  @override
  Future<List<Channel>> getChannels() async => _channels;

  @override
  Future<Map<String, SubscriptionLevel>> getSubscriptions() async => {
    for (final id in [
      'c-general',
      'c-random',
      'c-qall',
      'c-sysad',
      'c-hack',
      'c-mytimes',
    ])
      id: SubscriptionLevel.subscribed,
  };

  @override
  Future<List<UnreadChannel>> getUnreadChannels() async => const [
    UnreadChannel(channelId: 'c-general', count: 3, noticeable: false),
    UnreadChannel(channelId: 'c-sysad', count: 12, noticeable: true),
    UnreadChannel(channelId: 'c-hack', count: 1, noticeable: false),
  ];

  @override
  Future<void> markChannelRead(String channelId) async {}

  @override
  Future<List<Message>> getMessages(
    String channelId, {
    int limit = 50,
    DateTime? until,
  }) async => channelId == _callChannel && until == null ? _messages() : [];

  @override
  Future<List<QallRoom>> getQallRooms() async => _rooms;
}

class _FakeWebSocket extends TraqWebSocket {
  _FakeWebSocket(super.api);

  @override
  Future<void> connect() async {}
}

class _FakeAuth extends AuthController {
  _FakeAuth(this.api);

  final TraqApi api;

  @override
  Future<AuthSession?> build() async => AuthSession(api: api, me: _me);
}

class _NoSession extends SessionStore {
  @override
  Future<StoredSession?> load() async => null;

  @override
  Future<String> lastOrigin() async => defaultTraqOrigin;
}

class _FakeCall extends QallCallController {
  _FakeCall(TraqApi api) : super(api: api, channelName: (_) => '');

  /// 弾幕に流すメッセージを外から入れる
  final comments = StreamController<Message>.broadcast();

  @override
  Stream<Message> get channelMessages => comments.stream;

  @override
  String? get channelId => _callChannel;

  @override
  CallStatus get status => CallStatus.connected;

  @override
  bool get canPublish => true;

  @override
  bool get isMicEnabled => true;

  @override
  List<CallParticipant> get participants => const [
    CallParticipant(userId: 'u-me', isLocal: true),
    CallParticipant(userId: 'u-hana', isLocal: false, isSpeaking: true),
    CallParticipant(userId: 'u-ryo', isLocal: false, isMuted: true),
    CallParticipant(userId: 'u-mio', isLocal: false, isScreenSharing: true),
  ];

  @override
  List<CallVideo> get videos => const [];
}

// ---- セットアップ ----

Future<void> _loadFonts(String jpFontDir) async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable)
          .parent
          .parent
          .parent
          .parent
          .parent
          .parent
          .path;
  final materialFonts = '$flutterRoot/bin/cache/artifacts/material_fonts';

  Future<ByteData> read(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  // 本文は Noto Sans JP で描画する (テーマの既定フォント名 Roboto に割り当てる)
  final text = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    text.addFont(read('$jpFontDir/NotoSansJP-$weight.ttf'));
  }
  await text.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(read('$materialFonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

final _boundary = GlobalKey();

_FakeCall? _currentCall;

Future<void> _pumpApp(
  WidgetTester tester, {
  required Size size,
  double dpr = 3,
  // ステータスバーとホームインジケーターの領域 (iPhone 15 相当)
  (double, double) safeArea = (47, 34),
  bool loggedIn = true,
  bool inCall = true,
  Brightness brightness = Brightness.light,
}) async {
  tester.view
    ..physicalSize = size * dpr
    ..devicePixelRatio = dpr
    ..padding = FakeViewPadding(
      top: safeArea.$1 * dpr,
      bottom: safeArea.$2 * dpr,
    )
    ..viewPadding = FakeViewPadding(
      top: safeArea.$1 * dpr,
      bottom: safeArea.$2 * dpr,
    );
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

  final api = _FakeApi();
  // tool/ 以下はアナライザーにテストと見なされないが、flutter test で実行するテスト
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: ProviderScope(
        overrides: [
          if (loggedIn)
            authControllerProvider.overrideWith(() => _FakeAuth(api))
          else
            sessionStoreProvider.overrideWithValue(_NoSession()),
          traqWsProvider.overrideWith((ref) => _FakeWebSocket(api)),
          if (inCall)
            qallCallProvider.overrideWith(
              (ref) => _currentCall = _FakeCall(api),
            ),
          userIconImageProvider.overrideWithValue((_) => null),
          stampImageProvider.overrideWithValue((_) => null),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const QallApp(),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // 既読化のデバウンスなどのタイマーを消化する
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/screenshots/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  });
}

const _phone = Size(390, 844);
const _ipadLandscape = Size(1180, 820);

void main() {
  final fontDir = Platform.environment['QALL_SCREENSHOT_FONT_DIR'];

  setUpAll(() async {
    if (fontDir != null) await _loadFonts(fontDir);
  });

  group(
    'screenshots',
    skip: fontDir == null ? 'QALL_SCREENSHOT_FONT_DIR is not set' : false,
    () {
      testWidgets('login', (tester) async {
        await _pumpApp(tester, size: _phone, loggedIn: false, inCall: false);
        await _capture(tester, '01_login');
      });

      testWidgets('channel list', (tester) async {
        await _pumpApp(tester, size: _phone);
        await _capture(tester, '02_channels');
      });

      testWidgets('messages', (tester) async {
        await _pumpApp(tester, size: _phone);
        await tester.tap(
          find.widgetWithText(ListTile, '#team/qall-native').last,
        );
        await _settle(tester);
        await _capture(tester, '03_messages');
      });

      testWidgets('call', (tester) async {
        await _pumpApp(tester, size: _phone);
        await tester.tap(find.text('通話中 (4人)'));
        await _settle(tester);
        await _capture(tester, '04_call');
      });

      testWidgets('call (dark)', (tester) async {
        await _pumpApp(tester, size: _phone, brightness: Brightness.dark);
        await tester.tap(find.text('通話中 (4人)'));
        await _settle(tester);
        await _capture(tester, '05_call_dark');
      });

      testWidgets('call with danmaku', (tester) async {
        await _pumpApp(tester, size: _phone);
        await tester.tap(find.text('通話中 (4人)'));
        await _settle(tester);
        final call = _currentCall!;
        for (final (i, (user, text)) in [
          ('u-ryo', 'いま画面共有見えてます！'),
          ('u-hana', 'スリープしても切れないのすごい'),
          ('u-mio', '音質いい感じ'),
        ].indexed) {
          call.comments.add(
            Message(
              id: 'd$i',
              userId: user,
              channelId: _callChannel,
              content: text,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          );
          await tester.pump(const Duration(milliseconds: 900));
        }
        await tester.pump(const Duration(milliseconds: 600));
        await _capture(tester, '07_call_danmaku');
        // 流し終えてタイマーを消化する
        await tester.pump(const Duration(seconds: 8));
      });

      testWidgets('settings', (tester) async {
        await _pumpApp(tester, size: _phone, inCall: false);
        await tester.tap(find.byTooltip('アカウント'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('通話の設定'));
        await tester.pumpAndSettle();
        await _capture(tester, '08_settings');
      });

      testWidgets('iPad two-pane', (tester) async {
        await _pumpApp(
          tester,
          size: _ipadLandscape,
          dpr: 2,
          safeArea: (24, 20),
        );
        await tester.tap(
          find.widgetWithText(ListTile, '#team/qall-native').last,
        );
        await _settle(tester);
        await _capture(tester, '06_ipad');
      });
    },
  );
}
