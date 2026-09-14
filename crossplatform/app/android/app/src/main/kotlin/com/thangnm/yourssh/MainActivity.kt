package com.thangnm.yourssh

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var serial: SerialChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        serial = SerialChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onStop() {
        serial?.suspendConnections()
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        serial?.dispose()
        serial = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
