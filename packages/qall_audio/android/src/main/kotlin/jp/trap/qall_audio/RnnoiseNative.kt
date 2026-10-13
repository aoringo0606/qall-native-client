package jp.trap.qall_audio

import java.nio.ByteBuffer

/** RNNoise (qall_denoiser) の JNI バインディング。 */
internal object RnnoiseNative {
    init {
        System.loadLibrary("qall_rnnoise")
    }

    @JvmStatic external fun create(): Long

    @JvmStatic external fun destroy(handle: Long)

    /** 16bit PCM (インターリーブ) の 10ms ブロックをその場でノイズ除去する。 */
    @JvmStatic external fun processPcm16(
        handle: Long,
        buffer: ByteBuffer,
        bytes: Int,
        channels: Int,
    ): Float
}
