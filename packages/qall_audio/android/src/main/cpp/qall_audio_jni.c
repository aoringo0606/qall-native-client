#include <jni.h>
#include <stdint.h>

#include "qall_denoiser.h"

JNIEXPORT jlong JNICALL
Java_io_github_kaitoyama_qall_1audio_RnnoiseNative_create(JNIEnv *env, jclass clazz) {
  return (jlong)(intptr_t)qall_denoiser_create();
}

JNIEXPORT void JNICALL
Java_io_github_kaitoyama_qall_1audio_RnnoiseNative_destroy(JNIEnv *env, jclass clazz, jlong handle) {
  qall_denoiser_destroy((QallDenoiser *)(intptr_t)handle);
}

// buffer は WebRTC の録音スレッドが使っている DirectByteBuffer (16bit PCM, インターリーブ)。
JNIEXPORT jfloat JNICALL
Java_io_github_kaitoyama_qall_1audio_RnnoiseNative_processPcm16(JNIEnv *env, jclass clazz, jlong handle,
                                                     jobject buffer, jint bytes,
                                                     jint channels) {
  if (handle == 0 || channels <= 0 || channels > QALL_DENOISER_MAX_CHANNELS || bytes <= 0) {
    return 0.0f;
  }
  int16_t *samples = (int16_t *)(*env)->GetDirectBufferAddress(env, buffer);
  if (samples == NULL) return 0.0f;
  // 渡された長さがバッファを超えていたら書き込まない
  const jlong capacity = (*env)->GetDirectBufferCapacity(env, buffer);
  if (capacity < 0 || (jlong)bytes > capacity) return 0.0f;
  const int frames = bytes / (2 * channels);
  return qall_denoiser_process_s16((QallDenoiser *)(intptr_t)handle, samples, channels, frames);
}
