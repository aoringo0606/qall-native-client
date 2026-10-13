cmake_minimum_required(VERSION 3.22.1)
project(qall_rnnoise C)

# RNNoise と qall_denoiser のソースは iOS の Swift Package と共有している
set(DENOISER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../ios/qall_audio/Sources/qall_denoiser)

file(GLOB RNNOISE_SOURCES ${DENOISER_DIR}/rnnoise/*.c)

add_library(qall_rnnoise SHARED
  qall_audio_jni.c
  ${DENOISER_DIR}/qall_denoiser.c
  ${RNNOISE_SOURCES}
)

target_include_directories(qall_rnnoise PRIVATE
  ${DENOISER_DIR}/include
  ${DENOISER_DIR}/rnnoise
)

target_compile_options(qall_rnnoise PRIVATE -O2 -w)
target_link_libraries(qall_rnnoise m)
# Android 15 以降の 16KB ページサイズ端末に対応する
target_link_options(qall_rnnoise PRIVATE "-Wl,-z,max-page-size=16384")
