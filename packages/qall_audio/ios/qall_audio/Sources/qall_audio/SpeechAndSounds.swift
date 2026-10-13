import AVFoundation
import Flutter

/// 通話中の読み上げと効果音。
///
/// どちらもアプリの音声セッション (通話中は LiveKit が設定した playAndRecord) をそのまま使い、
/// カテゴリなどは変更しないので通話の音声経路を乱さない。
final class SpeechAndSounds: NSObject, AVAudioPlayerDelegate {
  private let registrar: FlutterPluginRegistrar
  private let synthesizer = AVSpeechSynthesizer()
  private var players = Set<AVAudioPlayer>()

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
    synthesizer.usesApplicationAudioSession = true
  }

  func speak(text: String, voice: String?, pitch: Double, rate: Double, volume: Double) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice =
      voice.flatMap(AVSpeechSynthesisVoice.init(identifier:))
      ?? AVSpeechSynthesisVoice(language: "ja-JP")
    utterance.pitchMultiplier = Float(min(max(pitch, 0.5), 2.0))
    utterance.rate = min(
      max(AVSpeechUtteranceDefaultSpeechRate * Float(rate), AVSpeechUtteranceMinimumSpeechRate),
      AVSpeechUtteranceMaximumSpeechRate)
    utterance.volume = Float(min(max(volume, 0), 1))
    synthesizer.speak(utterance)
  }

  func stopSpeaking() {
    synthesizer.stopSpeaking(at: .immediate)
  }

  func voices() -> [[String: String]] {
    AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language == "ja-JP" }
      .sorted { $0.name < $1.name }
      .map { ["id": $0.identifier, "name": $0.name] }
  }

  func playSound(asset: String, volume: Double) {
    let key = registrar.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
      NSLog("[QallAudio] asset not found: \(asset)")
      return
    }
    do {
      let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      player.volume = Float(min(max(volume, 0), 1))
      player.delegate = self
      players.insert(player)
      player.play()
    } catch {
      NSLog("[QallAudio] failed to play \(asset): \(error)")
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    players.remove(player)
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    players.remove(player)
  }
}
