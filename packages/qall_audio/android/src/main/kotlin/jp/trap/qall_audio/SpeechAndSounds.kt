package jp.trap.qall_audio

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.util.Log
import java.util.Locale
import java.util.UUID

/**
 * 通話中の読み上げと効果音。
 *
 * どちらも通話と同じ音声経路 (スピーカー / 受話口 / ヘッドセット) で鳴るよう
 * USAGE_VOICE_COMMUNICATION で再生し、オーディオモードや音声フォーカスには触らない。
 */
internal class SpeechAndSounds(
    private val context: Context,
    private val assetPath: (String) -> String,
) {
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val pending = mutableListOf<(TextToSpeech?) -> Unit>()

    /** 初期化を待って [action] を呼ぶ。読み上げエンジンが使えなければ null を渡す。 */
    private fun withTts(action: (TextToSpeech?) -> Unit) {
        val engine = tts
        if (engine != null && ttsReady) {
            action(engine)
            return
        }
        pending += action
        if (engine != null) return
        tts = TextToSpeech(context) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (!ttsReady) Log.w(TAG, "TextToSpeech init failed: $status")
            val actions = pending.toList()
            pending.clear()
            actions.forEach { it(if (ttsReady) tts else null) }
        }.apply { setAudioAttributes(attributes) }
    }

    fun speak(text: String, voice: String?, pitch: Double, rate: Double, volume: Double) =
        withTts { engine ->
            if (engine == null) return@withTts
            val selected = voice?.let { name -> engine.voices?.firstOrNull { it.name == name } }
            if (selected != null) engine.voice = selected else engine.language = Locale.JAPANESE
            engine.setPitch(pitch.toFloat())
            engine.setSpeechRate(rate.toFloat())
            val params = Bundle().apply {
                putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume.toFloat().coerceIn(0f, 1f))
            }
            engine.speak(text, TextToSpeech.QUEUE_ADD, params, UUID.randomUUID().toString())
        }

    fun stopSpeaking() {
        tts?.stop()
    }

    /** 日本語の声の一覧 (id = name)。 */
    fun voices(callback: (List<Map<String, String>>) -> Unit) = withTts { engine ->
        val list = engine?.voices.orEmpty()
            .filter { it.locale.language == Locale.JAPANESE.language }
            .sortedBy { it.name }
            .map { mapOf("id" to it.name, "name" to it.name) }
        callback(list)
    }

    fun playSound(asset: String, volume: Double) {
        try {
            val fd = context.assets.openFd(assetPath(asset))
            val player = MediaPlayer()
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            player.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
            fd.close()
            val v = volume.toFloat().coerceIn(0f, 1f)
            player.setVolume(v, v)
            player.setOnCompletionListener { it.release() }
            player.setOnErrorListener { mp, _, _ -> mp.release(); true }
            player.setOnPreparedListener { it.start() }
            player.prepareAsync()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to play $asset", e)
        }
    }

    fun dispose() {
        tts?.shutdown()
        tts = null
        ttsReady = false
    }

    companion object {
        private const val TAG = "QallAudio"
    }
}
