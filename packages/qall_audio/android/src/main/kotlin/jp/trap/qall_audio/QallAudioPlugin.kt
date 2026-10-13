package jp.trap.qall_audio

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Qall の通話音声まわりのネイティブ機能。 */
class QallAudioPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var speechAndSounds: SpeechAndSounds
    private val captureHook = WebRtcCaptureHook()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "jp.trap.qall/audio")
        channel.setMethodCallHandler(this)
        speechAndSounds = SpeechAndSounds(binding.applicationContext) {
            binding.flutterAssets.getAssetFilePathByName(it)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "setNoiseSuppression" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                result.success(captureHook.setNoiseSuppression(enabled))
            }
            // マイクモード (声を分離など) は iOS のみ
            "showMicrophoneModes" -> result.success(false)
            "microphoneMode" -> result.success(null)
            "speak" -> {
                speechAndSounds.speak(
                    text = call.argument<String>("text") ?: "",
                    voice = call.argument<String>("voice"),
                    pitch = call.argument<Double>("pitch") ?: 1.0,
                    rate = call.argument<Double>("rate") ?: 1.0,
                    volume = call.argument<Double>("volume") ?: 1.0,
                )
                result.success(null)
            }
            "stopSpeaking" -> {
                speechAndSounds.stopSpeaking()
                result.success(null)
            }
            "voices" -> speechAndSounds.voices { result.success(it) }
            "playSound" -> {
                speechAndSounds.playSound(
                    asset = call.argument<String>("asset") ?: "",
                    volume = call.argument<Double>("volume") ?: 1.0,
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        captureHook.setNoiseSuppression(false)
        speechAndSounds.dispose()
    }
}
