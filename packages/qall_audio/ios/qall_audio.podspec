#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint qall_audio.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'qall_audio'
  s.version          = '0.0.1'
  s.summary          = 'Native audio helpers for Qall (RNNoise noise suppression, iOS microphone modes)'
  s.description      = <<-DESC
Native audio helpers for Qall (RNNoise noise suppression, iOS microphone modes)
                       DESC
  s.homepage         = 'https://github.com/kaitoyama/qall-native-client'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'qall-native-client' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  # SwiftPM が既定。CocoaPods でビルドする場合も RNNoise を同じソースから組み込む
  s.source_files = 'qall_audio/Sources/qall_audio/**/*.swift',
                   'qall_audio/Sources/qall_denoiser/**/*.{c,h}'
  s.public_header_files = 'qall_audio/Sources/qall_denoiser/include/qall_denoiser.h'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/qall_audio/Sources/qall_denoiser/include" "${PODS_TARGET_SRCROOT}/qall_audio/Sources/qall_denoiser/rnnoise"',
  }
  s.swift_version = '5.0'

end
