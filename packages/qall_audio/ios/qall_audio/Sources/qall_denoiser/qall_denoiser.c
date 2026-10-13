#include "qall_denoiser.h"

#include <stdlib.h>
#include <string.h>

#include "rnnoise.h"

// RNNoise は 48kHz・480サンプル (10ms) 単位で動く。
#define RNNOISE_FRAME 480
// 10ms ブロックの最大サンプル数 (96kHz まで想定)
#define MAX_BLOCK 960

struct QallDenoiser {
  DenoiseState *state;
  float mono[MAX_BLOCK];
  float in48[RNNOISE_FRAME];
  float out48[RNNOISE_FRAME];
};

QallDenoiser *qall_denoiser_create(void) {
  QallDenoiser *d = (QallDenoiser *)calloc(1, sizeof(QallDenoiser));
  if (d == NULL) return NULL;
  d->state = rnnoise_create(NULL);
  if (d->state == NULL) {
    free(d);
    return NULL;
  }
  return d;
}

void qall_denoiser_destroy(QallDenoiser *d) {
  if (d == NULL) return;
  rnnoise_destroy(d->state);
  free(d);
}

// 線形補間で src (src_len) を dst (dst_len) に伸縮する。
static void resample_linear(const float *src, int src_len, float *dst, int dst_len) {
  if (src_len == dst_len) {
    memcpy(dst, src, sizeof(float) * (size_t)dst_len);
    return;
  }
  if (src_len == 1) {
    for (int i = 0; i < dst_len; i++) dst[i] = src[0];
    return;
  }
  const float step = (float)(src_len - 1) / (float)(dst_len - 1);
  for (int i = 0; i < dst_len; i++) {
    const float pos = step * (float)i;
    int idx = (int)pos;
    if (idx >= src_len - 1) idx = src_len - 2;
    const float frac = pos - (float)idx;
    dst[i] = src[idx] + (src[idx + 1] - src[idx]) * frac;
  }
}

// d->mono[0..frames) を RNNoise に通し、結果を d->mono に書き戻す。
// WebRTC のブロックは常に 10ms なので、サンプルレートに関係なく 480 サンプルに伸縮すればよい。
static float denoise_mono(QallDenoiser *d, int frames) {
  resample_linear(d->mono, frames, d->in48, RNNOISE_FRAME);
  const float vad = rnnoise_process_frame(d->state, d->out48, d->in48);
  resample_linear(d->out48, RNNOISE_FRAME, d->mono, frames);
  return vad;
}

static float clamp_s16(float v) {
  if (v > 32767.0f) return 32767.0f;
  if (v < -32768.0f) return -32768.0f;
  return v;
}

float qall_denoiser_process_float(QallDenoiser *d, float *const *channels,
                                  int num_channels, int frames) {
  if (d == NULL || channels == NULL || num_channels <= 0 || frames <= 1 ||
      frames > MAX_BLOCK) {
    return 0.0f;
  }
  for (int i = 0; i < frames; i++) {
    float sum = 0.0f;
    for (int ch = 0; ch < num_channels; ch++) sum += channels[ch][i];
    d->mono[i] = sum / (float)num_channels;
  }
  const float vad = denoise_mono(d, frames);
  for (int ch = 0; ch < num_channels; ch++) {
    for (int i = 0; i < frames; i++) channels[ch][i] = clamp_s16(d->mono[i]);
  }
  return vad;
}

float qall_denoiser_process_s16(QallDenoiser *d, int16_t *samples, int num_channels,
                                int frames) {
  if (d == NULL || samples == NULL || num_channels <= 0 || frames <= 1 ||
      frames > MAX_BLOCK) {
    return 0.0f;
  }
  for (int i = 0; i < frames; i++) {
    float sum = 0.0f;
    for (int ch = 0; ch < num_channels; ch++) sum += samples[i * num_channels + ch];
    d->mono[i] = sum / (float)num_channels;
  }
  const float vad = denoise_mono(d, frames);
  for (int i = 0; i < frames; i++) {
    const int16_t v = (int16_t)clamp_s16(d->mono[i]);
    for (int ch = 0; ch < num_channels; ch++) samples[i * num_channels + ch] = v;
  }
  return vad;
}
