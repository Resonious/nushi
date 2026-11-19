package com.nushihq.nushi

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "nushi/android").setMethodCallHandler { call, result ->
            when (call.method) {
                "filesDir" -> result.success(applicationContext.filesDir.absolutePath)
                "deviceName" -> result.success(Build.MODEL?.trim()?.ifEmpty { "Android" } ?: "Android")
                else -> result.notImplemented()
            }
        }

        val mainHandler = Handler(Looper.getMainLooper())
        EventChannel(messenger, "nushi/android/network").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    unregisterNetwork()
                    val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                        ?: return
                    val callback = object : ConnectivityManager.NetworkCallback() {
                        override fun onAvailable(network: Network) {
                            mainHandler.post { events?.success(true) }
                        }
                    }
                    networkCallback = callback
                    try {
                        cm.registerDefaultNetworkCallback(callback)
                    } catch (_: Throwable) {
                        networkCallback = null
                    }
                }

                override fun onCancel(arguments: Any?) {
                    unregisterNetwork()
                }
            }
        )
    }

    override fun onDestroy() {
        unregisterNetwork()
        super.onDestroy()
    }

    private fun unregisterNetwork() {
        val cb = networkCallback ?: return
        networkCallback = null
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        try {
            cm.unregisterNetworkCallback(cb)
        } catch (_: Throwable) {
            // Already unregistered.
        }
    }
}
