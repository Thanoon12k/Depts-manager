# shared_preferences_android reaches its Kotlin API from Dart through JNI, looking methods up
# by name and signature. R8 must not rename those classes, or the types in their signatures
# (e.g. kotlin.coroutines.Continuation), or the app can't read its saved data on launch.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class kotlin.coroutines.Continuation
-keep class kotlin.Result { *; }
-keep class kotlin.Unit
