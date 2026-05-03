# Keep native methods for JNI
-keepclassmembers class com.sightsentry.pro.MainActivity {
    native <methods>;
}

# Keep JavaScript interface methods
-keepclassmembers class com.sightsentry.pro.MainActivity$NativeBridge {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep WebView related classes
-keep class * extends android.webkit.WebViewClient
-keep class * extends android.webkit.WebChromeClient
