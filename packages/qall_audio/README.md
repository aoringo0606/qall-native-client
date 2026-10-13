# qall_audio

Qall ネイティブクライアント用の音声まわりのプラグイン (アプリ内でのみ使用)。

- **RNNoise によるノイズ除去**: マイク音声が WebRTC に送られる直前に [RNNoise](https://gitlab.xiph.org/xiph/rnnoise) (v0.1.1, BSD-3-Clause) をかける
  - Android: flutter_webrtc の録音スレッド (`WebRtcAudioRecord`) の `AudioBufferCallback` にリフレクションで差し込む
  - iOS: flutter_webrtc の `AudioManager.capturePostProcessingAdapter` に登録する
- **iOS のマイクモード**: 「声を分離」などを選ぶシステム画面を開く / 現在のモードを取得する

RNNoise と WebRTC の 10ms ブロックに合わせるラッパー (`qall_denoiser`) のソースは
`ios/qall_audio/Sources/qall_denoiser/` にあり、Android の CMake からも同じものを参照している。
