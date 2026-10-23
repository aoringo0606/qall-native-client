package jp.trap.qall_audio

import android.media.AudioFormat
import android.util.Log
import java.lang.reflect.InvocationHandler
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.nio.ByteBuffer

/**
 * マイクの音声が WebRTC に渡される直前に RNNoise をかける。
 *
 * flutter_webrtc の録音スレッド (org.webrtc.audio.WebRtcAudioRecord) は、
 * 10ms ごとに読み取った PCM を AudioBufferCallback に渡してから WebRTC に送る。
 * flutter_webrtc にはこのコールバックを設定する API がないため、リフレクションで差し込む。
 * (WebRTC のノイズ抑制などの処理より前、帯域分割される前の全帯域 PCM を扱える)
 *
 * flutter_webrtc にコンパイル時依存しないよう、クラスはすべて名前で引く。
 */
internal class WebRtcCaptureHook {
    @Volatile private var enabled = false
    @Volatile private var handle = 0L
    private var hookedRecord: Any? = null

    /** 有効化できたら true。まだ WebRTC が初期化されていない場合などは false。 */
    @Synchronized
    fun setNoiseSuppression(enable: Boolean): Boolean {
        enabled = enable
        if (!enable) return true
        if (handle == 0L) handle = RnnoiseNative.create()
        if (handle == 0L) return false
        return install()
    }

    private fun install(): Boolean =
        try {
            val record = findAudioRecord()
            when {
                record == null -> false
                record === hookedRecord -> true
                else -> {
                    val field = record.javaClass.getDeclaredField("audioBufferCallback")
                    field.isAccessible = true
                    val previous = field.get(record)
                    val callbackType =
                        Class.forName("org.webrtc.audio.JavaAudioDeviceModule\$AudioBufferCallback")
                    val proxy = Proxy.newProxyInstance(
                        callbackType.classLoader,
                        arrayOf(callbackType),
                        Callback(previous),
                    )
                    field.set(record, proxy)
                    hookedRecord = record
                    true
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to install RNNoise into WebRTC capture", e)
            false
        }

    /** FlutterWebRTCPlugin → MethodCallHandlerImpl → JavaAudioDeviceModule → WebRtcAudioRecord */
    private fun findAudioRecord(): Any? {
        val pluginClass = Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
        val plugin = pluginClass.getField("sharedSingleton").get(null) ?: return null
        val handler = pluginClass.getDeclaredField("methodCallHandler")
            .apply { isAccessible = true }
            .get(plugin) ?: return null
        val adm = handler.javaClass.getDeclaredField("audioDeviceModule")
            .apply { isAccessible = true }
            .get(handler) ?: return null
        return adm.javaClass.getField("audioInput").get(adm)
    }

    private inner class Callback(private val previous: Any?) : InvocationHandler {
        override fun invoke(proxy: Any, method: Method, args: Array<out Any?>?): Any? =
            when (method.name) {
                "onBuffer" -> onBuffer(method, args!!)
                "hashCode" -> System.identityHashCode(proxy)
                "equals" -> proxy === args?.getOrNull(0)
                "toString" -> "QallRnnoiseCallback"
                else -> null
            }

        // long onBuffer(ByteBuffer buffer, int audioFormat, int channelCount,
        //               int sampleRate, int bytesRead, long captureTimestampNs)
        private fun onBuffer(method: Method, args: Array<out Any?>): Long {
            val buffer = args[0] as ByteBuffer
            val audioFormat = args[1] as Int
            val channels = args[2] as Int
            val bytesRead = args[4] as Int
            var timestamp = args[5] as Long
            val h = handle
            if (enabled && h != 0L && audioFormat == AudioFormat.ENCODING_PCM_16BIT) {
                RnnoiseNative.processPcm16(h, buffer, bytesRead, channels)
            }
            if (previous != null) timestamp = method.invoke(previous, *args) as Long
            return timestamp
        }
    }

    companion object {
        private const val TAG = "QallAudio"
    }
}
