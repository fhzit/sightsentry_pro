package com.sightsentry.pro

import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebSettings
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {

    companion object {
        init {
            try {
                System.loadLibrary("sightsentry_pro_lib")
            } catch (e: UnsatisfiedLinkError) {
                android.util.Log.e("SightSentry", "Failed to load native library", e)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val webView = findViewById<WebView>(R.id.webview)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            setSupportZoom(false)
            builtInZoomControls = false
            useWideViewPort = true
            loadWithOverviewMode = true
            if (BuildConfig.DEBUG) {
                WebView.setWebContentsDebuggingEnabled(true)
            }
        }

        webView.addJavascriptInterface(NativeBridge(), "__nativeBridge")
        webView.webViewClient = WebViewClient()
        webView.webChromeClient = WebChromeClient()

        webView.loadUrl("file:///android_asset/index.html")
    }

    inner class NativeBridge {
        @JavascriptInterface
        fun callNative(message: String): String {
            val result = handleNativeMessage(message)
            return result ?: "{\"error\":\"native_no_response\"}"
        }

        @JavascriptInterface
        fun getNativeInfo(): String {
            return "{\"platform\":\"android\",\"version\":\"${BuildConfig.VERSION_NAME}\"}"
        }
    }

    private external fun handleNativeMessage(message: String): String

    override fun onDestroy() {
        super.onDestroy()
    }
}
