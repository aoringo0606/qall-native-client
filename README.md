# Qall Native Client

[traQ](https://github.com/traPtitech/traQ) の **Qall (通話)** を中心にした iPhone / iPad / Android 向けネイティブクライアントです。Flutter で1つのコードベースから両OSをビルドします。

メッセージ機能は最小限にとどめ、Qall は Web版 (traQ_S-UI) の機能・設定をひととおり取り込んでいます。

| 機能 | 内容 |
| --- | --- |
| 通話 | Qall ルームへの参加・退出、ウェビナーモードでの開始、ミュート、スピーカー/受話口 (Android は出力先も選択可)、参加者と発話中の表示 |
| バックグラウンド通話 | アプリを閉じても、画面がスリープしても通話が続く |
| 画面共有 | 端末の画面全体を共有 (Android: MediaProjection / iOS: Broadcast Upload Extension)、他の人の画面共有・カメラ映像の視聴 (ピンチで拡大可) |
| カメラ | カメラ映像の送信、前面/背面の切り替え |
| リアクション | スタンプでリアクション (最近使ったもの + 検索)、サウンドボード (再生・音の追加) |
| 弾幕 | 通話中のチャンネルへの投稿とスタンプを画面に流す (ON/OFF) |
| 音声 | ノイズ除去 (標準 / RNNoise / なし)、エコーキャンセル、自動音量調整、iOS のマイクモード (声を分離)、マスターボリューム、参加者ごとの音量、入退室の効果音、メッセージの読み上げ (声・ピッチ・速さ・音量) |
| メッセージ | 購読中のチャンネル一覧 (未読数つき)、メッセージの閲覧・送信 (WebSocket でリアルタイム更新) |
| その他 | 通話中のルーム一覧、iPad / タブレットでは2ペイン表示 |

## スクリーンショット

ダミーデータで描画したものです (`tool/screenshots/` で生成)。

| ログイン | チャンネル一覧 | メッセージ | 通話 | 通話 (ダーク) |
| --- | --- | --- | --- | --- |
| <img src="docs/screenshots/01_login.png" width="160"> | <img src="docs/screenshots/02_channels.png" width="160"> | <img src="docs/screenshots/03_messages.png" width="160"> | <img src="docs/screenshots/04_call.png" width="160"> | <img src="docs/screenshots/05_call_dark.png" width="160"> |

| 弾幕 | 通話の設定 |
| --- | --- |
| <img src="docs/screenshots/07_call_danmaku.png" width="160"> | <img src="docs/screenshots/08_settings.png" width="160"> |

iPad (横向き・2ペイン)

<img src="docs/screenshots/06_ipad.png" width="640">

## 動かし方

```sh
flutter pub get
flutter run            # 接続中の実機 / シミュレータで起動
```

- Flutter 3.47 (stable) で開発しています
- ログインは traQ の ID とパスワードです。接続先は既定で `https://q.trap.jp`、ログイン画面の「詳細設定」で変更できます
- 通話・画面共有は実機で確認してください (シミュレータ / エミュレータではマイクや画面キャプチャが制限されます)

### iOS の初回セットアップ

`ios/Runner.xcworkspace` を Xcode で開き、以下を行ってください。

1. `Runner` と `BroadcastExtension` の両ターゲットで *Signing & Capabilities* の Team を設定する
2. 両ターゲットに App Group `group.jp.trap.qall` が付いていることを確認する (自動署名なら Xcode が登録します)

Bundle ID を変える場合は、プロジェクト (PROJECT > Runner) のビルド設定で次の3つをそろえて変更してください。Info.plist と entitlements はここから展開されます。

| ビルド設定 | 既定値 |
| --- | --- |
| `PRODUCT_BUNDLE_IDENTIFIER` (Runner ターゲット) | `jp.trap.qall` |
| `BROADCAST_EXTENSION_BUNDLE_IDENTIFIER` | `jp.trap.qall.BroadcastExtension` |
| `APP_GROUP_IDENTIFIER` | `group.jp.trap.qall` |

Android の applicationId は `android/app/build.gradle.kts` にあります。

## 設計メモ

### 認証: OAuth2 ではなくセッションCookie

traQ の Qall API (`/api/v3/qall/*`) は `WebRTC` 権限を要求しますが、OAuth2 の `read` / `write` スコープにはこの権限が含まれていません (traQ `service/rbac/role/{read,write}.go`)。そのため、Web 版と同じく `POST /api/v3/login` で得たセッションCookie `r_session` を使います。

- Cookie は Keychain / Android Keystore (`flutter_secure_storage`) に保存
- traQ はセッションを期限前に再発行することがあるので、全レスポンスの `Set-Cookie` を見て更新します (`lib/core/traq_api.dart`)
- WebSocket (`/api/v3/ws`) にも同じ Cookie を付けて接続します

### Qall (LiveKit) と Web 版との互換性

traQ の Qall は [LiveKit](https://livekit.io) で動いています。traQ_S-UI (Web版) と同じルールで接続するので、Web版の参加者と同じ通話に入れます。

- ルーム名 = チャンネルID。`GET /qall/endpoints` で LiveKit の URL、`GET /qall/token?roomId=` でトークンを取得
- 参加者の identity は `{traQユーザーID}_{ランダムUUID}`。末尾37文字を落としてユーザーIDを得ます
- **マイクのトラックは必ず publish します**。Web版の参加者一覧はマイクトラックの有無で表示を決めているため、ミュート中も (無音の) トラックは出し続けます
- ルームの参加者一覧は `GET /qall/rooms` と WebSocket の `QALL_ROOM_STATE_CHANGED` で更新
- スタンプリアクションは data メッセージ `{"type":"stamp","message":"<stampId>"}`

### スリープしても通話を続ける仕組み

| | 仕組み |
| --- | --- |
| Android | 通話中は `microphone` タイプのフォアグラウンドサービス (`flutter_foreground_task`) を起動し、WakeLock / WifiLock を保持。通知に「ミュート」「退出」ボタン。画面共有中は `mediaProjection` タイプも付与 |
| iOS | `UIBackgroundModes` に `audio` / `voip`。ミュート中もマイクのキャプチャを止めない (`stopAudioCaptureOnMute: false`) ことで音声セッションを動かし続け、OS にサスペンドされないようにしています |

Android でバッテリー最適化が強い端末 (一部の国内メーカー端末など) では、設定からこのアプリを「最適化しない」にすると安定します。

### 画面共有

- **Android**: `Helper.requestCapturePermission()` で許可を得てから、`mediaProjection` タイプのフォアグラウンドサービスを開始し、LiveKit で publish します (Android 14 以降はこの順番が必須)
- **iOS**: `ios/BroadcastExtension` の Broadcast Upload Extension が ReplayKit で画面を取得し、App Group 内の UNIX ソケット経由で本体アプリへ渡します。共有ボタンを押すとシステムの「画面収録」ピッカーが出ます。コントロールセンターから止めても連動します
- いずれも端末の音声 (アプリの音) は共有しません

### ノイズ除去

設定の「ノイズ除去」で3つから選べます (Web版の Rnnoise / Speex / 無効 に相当)。

| 方式 | 中身 |
| --- | --- |
| 標準 (既定) | WebRTC のノイズ抑制 + 端末のハードウェア処理。iOS ではさらにユーザーが「マイクモード → 声を分離」を選べる (アプリからは変更できず、設定画面からシステムの画面を開ける) |
| RNNoise | [RNNoise](https://gitlab.xiph.org/xiph/rnnoise) (v0.1.1, BSD-3-Clause) をソースからビルドして組み込み。二重にかからないよう WebRTC 標準のノイズ抑制は切る |
| なし | 処理なし (エコーキャンセルと自動音量調整は個別に ON/OFF) |

RNNoise は `packages/qall_audio` (アプリ内のプラグイン) で動かしています。

- Android: flutter_webrtc の録音スレッド (`WebRtcAudioRecord`) が WebRTC に PCM を渡す直前の `AudioBufferCallback` にリフレクションで差し込む (WebRTC の帯域分割前の全帯域で処理するため)
- iOS: flutter_webrtc の `AudioManager.capturePostProcessingAdapter` に登録する

参考: Discord は Krisp (商用 SDK)、Teams・Google Meet・LINE は自社の機械学習モデルを使っている。LiveKit 公式の Krisp フィルタ (`livekit_noise_filter`) は LiveKit Cloud 専用で、traQ のような自前ホストの LiveKit では使えない。

### 読み上げ・効果音

読み上げ (Android: TextToSpeech / iOS: AVSpeechSynthesizer) と効果音の再生も `qall_audio` に実装しています。通話中の音声経路 (スピーカー / 受話口 / イヤホン) を乱さないよう、Android は `USAGE_VOICE_COMMUNICATION` で鳴らし、iOS はアプリの音声セッションをそのまま使います。読み上げる文の作り方は Web版 (`lib/tts/format.ts`) に合わせています。効果音は traQ_S-UI のもの (MIT License, `assets/se/NOTICE`) です。

### 依存関係のメモ

- サウンドボードへの音の追加は、API 定義 (`audio` / `soundName`) と traQ サーバーの実装 (`file` / `name`) でフィールド名が食い違っているため、両方の名前で送っています

- `permission_handler` は `^12` に固定しています。13 系 (permission_handler_android 14) は compileSdk 37 を要求し、Flutter テンプレートの AGP 9.1 では `android-37` を解決できないためです。Flutter のテンプレートが追いついたら上げてください
- iOS の画面共有の停止に使う `BroadcastManager` は livekit_client の公開APIから export されていないため、`package:livekit_client/src/...` を直接 import しています。livekit_client を上げるときはこの import が壊れていないか確認してください

## ディレクトリ構成

```
lib/
  core/                 traQ API / WebSocket / 認証 / モデル
  features/
    auth/               ログイン画面
    home/               トップ (スマホ: 1ペイン、iPad: 2ペイン)
    channels/           購読チャンネル一覧・通話中ルーム一覧
    messages/           メッセージ一覧・送信
    qall/               通話 (LiveKit 制御、バックグラウンド維持、通話画面、弾幕、スタンプ、サウンドボード)
  settings/           通話の設定
ios/BroadcastExtension/ iOS の画面共有用 Extension
packages/qall_audio/    RNNoise・読み上げ・効果音・iOS マイクモードのネイティブ実装
```

## テスト / CI

```sh
flutter analyze
flutter test
```

GitHub Actions (`.github/workflows/ci.yml`) で analyze・test・Android の debug APK・iOS (署名なし) のビルドを行います。

スクリーンショットの更新 (Noto Sans JP の Regular / Medium / Bold の `.ttf` を置いたディレクトリを指定):

```sh
QALL_SCREENSHOT_FONT_DIR=/path/to/fonts flutter test tool/screenshots
```

## 今後やりたいこと

- カメラの背景ぼかし・背景画像 (Web版にはある。端末ごとに人物の切り抜き処理をネイティブで実装する必要がある)
- 画面共有で端末の音も流す (flutter_webrtc がモバイルで未対応)
- 通話への招待・着信通知 (CallKit / FCM)
- traQ の外部ログイン (OAuth 連携アカウント) への対応
- メッセージの Markdown 表示・スタンプ表示
