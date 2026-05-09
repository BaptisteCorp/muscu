# Flutter / Android FileProvider — utilisé par image_picker pour la caméra.
# R8 obscurcit FileProvider sans préserver son contrat XmlPullParser, ce qui
# provoque IncompatibleClassChangeError au runtime.
-keep class androidx.core.content.FileProvider { *; }
-keep class androidx.core.content.FileProvider$** { *; }
-keep class * extends androidx.core.content.FileProvider { *; }

# XmlPullParser API — appelée par FileProvider lors du parsing des
# file_paths.xml. À garder telle quelle pour éviter les
# IncompatibleClassChangeError.
-keep interface org.xmlpull.v1.** { *; }
-keep class org.xmlpull.v1.** { *; }
-dontwarn org.xmlpull.v1.**

# Plugin image_picker_android — méthodes appelées via reflection / JNI.
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**
