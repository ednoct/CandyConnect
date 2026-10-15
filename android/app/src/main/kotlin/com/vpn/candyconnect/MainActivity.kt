package com.vpn.candyconnect

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "candyconnect/vpn"
    private val VPN_REQUEST_CODE = 24

    private var vpnPrepareResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        vpnPrepareResult = result
                        startActivityForResult(intent, VPN_REQUEST_CODE)
                    } else {
                        // Already granted
                        result.success(true)
                    }
                }
                "startVpn" -> {
                    val proxyMode = call.argument<Int>("proxyMode") ?: 0
                    val selectedApps = call.argument<List<String>>("selectedApps") ?: emptyList()

                    val intent = Intent(this, CandyVpnService::class.java).apply {
                        putExtra("proxyMode", proxyMode)
                        putStringArrayListExtra("selectedApps", ArrayList(selectedApps))
                    }

                    // Register one-shot receiver to get the TUN fd back
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context, broadcastIntent: Intent) {
                            val fd = broadcastIntent.getIntExtra("fd", -1)
                            result.success(fd)
                            context.unregisterReceiver(this)
                        }
                    }
                    
                    ContextCompat.registerReceiver(
                        this,
                        receiver,
                        IntentFilter("com.vpn.candyconnect.TUN_FD_BROADCAST"),
                        ContextCompat.RECEIVER_NOT_EXPORTED
                    )

                    startService(intent)
                }
                "stopVpn" -> {
                    stopService(Intent(this, CandyVpnService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                vpnPrepareResult?.success(true)
            } else {
                vpnPrepareResult?.success(false)
            }
            vpnPrepareResult = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
