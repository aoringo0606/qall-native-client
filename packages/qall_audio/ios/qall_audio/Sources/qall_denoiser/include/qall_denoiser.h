// RNNoise を WebRTC の 10ms 単位の音声ブロックに適用するための薄いラッパー。
// Android (JNI) と iOS (Swift) の両方から使う。
#ifndef QALL_DENOISER_H
#define QALL_DENOISER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct QallDenoiser QallDenoiser;

QallDenoiser *qall_denoiser_create(void);
void qall_denoiser_destroy(QallDenoiser *denoiser);

// 1ブロック (10ms 分) の非インターリーブ float 音声をその場でノイズ除去する。
// 値の範囲は int16 相当 ([-32768, 32767])。複数チャンネルはモノラルに混ぜて処理し、
// 全チャンネルに同じ結果を書き戻す。frames は 1チャンネルあたりのサンプル数。
// 戻り値は RNNoise の推定した「声である確率」(0〜1)。
float qall_denoiser_process_float(QallDenoiser *denoiser, float *const *channels,
                                  int num_channels, int frames);

// 1ブロック (10ms 分) のインターリーブ int16 音声をその場でノイズ除去する。
float qall_denoiser_process_s16(QallDenoiser *denoiser, int16_t *samples,
                                int num_channels, int frames);

#ifdef __cplusplus
}
#endif

#endif  // QALL_DENOISER_H
