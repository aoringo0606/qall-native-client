# WebRtcCaptureHook がリフレクションで参照するクラス・フィールド
-keep class com.cloudwebrtc.webrtc.FlutterWebRTCPlugin { *; }
-keep class com.cloudwebrtc.webrtc.MethodCallHandlerImpl { *; }
-keep class org.webrtc.audio.** { *; }
# JNI
-keep class jp.trap.qall_audio.RnnoiseNative { *; }
