package com.example.karass

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Override onActivityResult to catch "Reply already submitted" crash
    // from flutter_ble_peripheral plugin. The plugin's onActivityResult handler
    // can crash when receiving activity results from unrelated activities
    // (e.g., OAuth browser Chrome Custom Tab).
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        try {
            super.onActivityResult(requestCode, resultCode, data)
        } catch (e: IllegalStateException) {
            // Swallow "Reply already submitted" errors from BLE plugin
            android.util.Log.w("MainActivity", "Caught IllegalStateException in onActivityResult: ${e.message}")
        }
    }
}
