import Foundation

#if canImport(qall_denoiser)
  import qall_denoiser
#endif

/// flutter_webrtc の ExternalAudioProcessingDelegate として振る舞い、
/// マイク音声 (WebRTC の音声処理後・全帯域) に RNNoise をかける。
///
/// RTCAudioBuffer の型を import せずに済むよう、メソッドは Objective-C ランタイムで呼ぶ。
final class RnnoiseProcessor: NSObject {
  private typealias SizeGetter = @convention(c) (AnyObject, Selector) -> Int
  private typealias RawBufferGetter =
    @convention(c) (AnyObject, Selector, Int) -> UnsafeMutablePointer<Float>?

  private static let framesSelector = NSSelectorFromString("frames")
  private static let channelsSelector = NSSelectorFromString("channels")
  private static let rawBufferSelector = NSSelectorFromString("rawBufferForChannel:")

  /// 音声スレッドから読む。多少の競合は1ブロック分の処理の有無にしか影響しない。
  var enabled = false
  private let denoiser: OpaquePointer? = qall_denoiser_create()
  private var channelPointers = [UnsafeMutablePointer<Float>?](repeating: nil, count: 8)

  deinit {
    qall_denoiser_destroy(denoiser)
  }

  @objc(audioProcessingInitializeWithSampleRate:channels:)
  func prepare(sampleRate: Int, channels: Int) {}

  @objc(audioProcessingProcess:)
  func process(_ audioBuffer: NSObject) {
    guard enabled, let denoiser else { return }
    guard let framesImp = audioBuffer.method(for: Self.framesSelector),
      let channelsImp = audioBuffer.method(for: Self.channelsSelector),
      let rawImp = audioBuffer.method(for: Self.rawBufferSelector)
    else { return }
    let frames = unsafeBitCast(framesImp, to: SizeGetter.self)(audioBuffer, Self.framesSelector)
    let channels = unsafeBitCast(channelsImp, to: SizeGetter.self)(
      audioBuffer, Self.channelsSelector)
    guard frames > 1, channels > 0, channels <= channelPointers.count else { return }

    let rawBuffer = unsafeBitCast(rawImp, to: RawBufferGetter.self)
    for channel in 0..<channels {
      guard let pointer = rawBuffer(audioBuffer, Self.rawBufferSelector, channel) else { return }
      channelPointers[channel] = pointer
    }
    channelPointers.withUnsafeMutableBufferPointer { pointers in
      _ = qall_denoiser_process_float(
        denoiser, pointers.baseAddress, Int32(channels), Int32(frames))
    }
  }

  @objc(audioProcessingRelease)
  func release() {}
}
