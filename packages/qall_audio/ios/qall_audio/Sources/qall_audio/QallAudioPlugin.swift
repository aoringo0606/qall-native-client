import AVFoundation
import Flutter
import UIKit

/// Qall の通話音声まわりのネイティブ機能。
public class QallAudioPlugin: NSObject, FlutterPlugin {
  private let processor = RnnoiseProcessor()
  private let speechAndSounds: SpeechAndSounds
  private var installed = false

  init(registrar: FlutterPluginRegistrar) {
    speechAndSounds = SpeechAndSounds(registrar: registrar)
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.github.kaitoyama.qall/audio", binaryMessenger: registrar.messenger())
    let instance = QallAudioPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setNoiseSuppression":
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      processor.enabled = enabled
      if enabled && !installed {
        installed = installProcessor()
      }
      result(!enabled || installed)
    case "showMicrophoneModes":
      // 「声を分離」などのマイクモードは OS の画面からしか変えられない
      AVCaptureDevice.showSystemUserInterface(.microphoneModes)
      result(true)
    case "microphoneMode":
      result(Self.describe(AVCaptureDevice.activeMicrophoneMode))
    case "speak":
      let args = call.arguments as? [String: Any] ?? [:]
      speechAndSounds.speak(
        text: args["text"] as? String ?? "",
        voice: args["voice"] as? String,
        pitch: args["pitch"] as? Double ?? 1,
        rate: args["rate"] as? Double ?? 1,
        volume: args["volume"] as? Double ?? 1)
      result(nil)
    case "stopSpeaking":
      speechAndSounds.stopSpeaking()
      result(nil)
    case "voices":
      result(speechAndSounds.voices())
    case "playSound":
      let args = call.arguments as? [String: Any] ?? [:]
      speechAndSounds.playSound(
        asset: args["asset"] as? String ?? "", volume: args["volume"] as? Double ?? 1)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// flutter_webrtc の AudioManager.capturePostProcessingAdapter に登録する。
  /// flutter_webrtc にコンパイル時依存しないよう、Objective-C ランタイム経由で呼ぶ。
  private func installProcessor() -> Bool {
    var audioManager: NSObject?
    if let plugin = Self.callClassMethod("FlutterWebRTCPlugin", "sharedSingleton") {
      audioManager = plugin.value(forKey: "audioManager") as? NSObject
    }
    if audioManager == nil {
      audioManager = Self.callClassMethod("AudioManager", "sharedInstance")
    }
    guard let adapter = audioManager?.value(forKey: "capturePostProcessingAdapter") as? NSObject,
      adapter.responds(to: NSSelectorFromString("addProcessing:"))
    else {
      NSLog("[QallAudio] flutter_webrtc audio processing adapter not found")
      return false
    }
    adapter.perform(NSSelectorFromString("addProcessing:"), with: processor)
    return true
  }

  /// `[ClassName selector]` を呼んで結果のオブジェクトを返す。
  private static func callClassMethod(_ className: String, _ selectorName: String) -> NSObject? {
    guard let cls = NSClassFromString(className) else { return nil }
    let target: AnyObject = cls
    let selector = NSSelectorFromString(selectorName)
    guard target.responds(to: selector) else { return nil }
    return target.perform(selector)?.takeUnretainedValue() as? NSObject
  }

  private static func describe(_ mode: AVCaptureDevice.MicrophoneMode) -> String {
    switch mode {
    case .standard: return "standard"
    case .voiceIsolation: return "voiceIsolation"
    case .wideSpectrum: return "wideSpectrum"
    @unknown default: return "unknown"
    }
  }
}
