package com.vpn.candyconnect

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val CHANNEL = "candyconnect/vpn"
    private val VPN_REQUEST_CODE = 24

    private var vpnPrepareResult: ((Boolean) -> Unit)? = null
    private var activeTunReceiver: BroadcastReceiver? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, rawResult ->
                val replied = AtomicBoolean(false)

                fun safeSuccess(value: Any?) {
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.post {
                            try {
                                rawResult.success(value)
                            } catch (_: Throwable) {}
                        }
                    }
                }

                when (call.method) {
                    "prepareVpn" -> {
                        try {
                            val prepareIntent = VpnService.prepare(this)
                            if (prepareIntent != null) {
                                // در صورت وجود درخواست قبلیِ معلق، آن را با false ببند تا قفل نشود
                                vpnPrepareResult?.invoke(false)
                                vpnPrepareResult = { granted ->
                                    safeSuccess(granted)
                                }
                                startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                            } else {
                                safeSuccess(true)
                            }
                        } catch (e: Exception) {
                            safeSuccess(false)
                        }
                    }

                    "startVpn" -> {
                        val proxyMode = call.argument<Int>("proxyMode") ?: 0
                        val selectedApps = call.argument<List<String>>("selectedApps") ?: emptyList()

                        cleanupPendingTunReceiver()

                        val timeoutRunnable = Runnable {
                            CandyVpnService.onTunFdReady = null
                            cleanupPendingTunReceiver()
                            safeSuccess(-1)
                        }
                        mainHandler.postDelayed(timeoutRunnable, 6000L)

                        // ۱. کالبک مستقیم درون‌پروسه‌ای (سریع‌ترین مسیر بدون تاخیر Broadcast)
                        CandyVpnService.onTunFdReady = { fd ->
                            mainHandler.removeCallbacks(timeoutRunnable)
                            CandyVpnService.onTunFdReady = null
                            cleanupPendingTunReceiver()
                            safeSuccess(fd)
                        }

                        // ۲. گیرنده Broadcast به عنوان پشتیبان
                        val receiver = object : BroadcastReceiver() {
                            override fun onReceive(context: Context, broadcastIntent: Intent) {
                                val fd = broadcastIntent.getIntExtra("fd", -1)
                                mainHandler.removeCallbacks(timeoutRunnable)
                                CandyVpnService.onTunFdReady = null
                                cleanupPendingTunReceiver()
                                safeSuccess(fd)
                            }
                        }
                        activeTunReceiver = receiver

                        ContextCompat.registerReceiver(
                            this,
                            receiver,
                            IntentFilter(CandyVpnService.ACTION_TUN_FD_BROADCAST),
                            ContextCompat.RECEIVER_NOT_EXPORTED
                        )

                        val serviceIntent = Intent(this, CandyVpnService::class.java).apply {
                            action = CandyVpnService.ACTION_START_VPN
                            putExtra("proxyMode", proxyMode)
                            putStringArrayListExtra("selectedApps", ArrayList(selectedApps))
                        }

                        try {
                            ContextCompat.startForegroundService(this, serviceIntent)
                        } catch (_: Exception) {
                            try {
                                startService(serviceIntent)
                            } catch (_: Exception) {
                                mainHandler.removeCallbacks(timeoutRunnable)
                                CandyVpnService.onTunFdReady = null
                                cleanupPendingTunReceiver()
                                safeSuccess(-1)
                            }
                        }
                    }

                    "stopVpn" -> {
                        CandyVpnService.onTunFdReady = null
                        cleanupPendingTunReceiver()
                        CandyVpnService.stopActiveTunnel(this)
                        safeSuccess(true)
                    }

                    else -> {
                        if (replied.compareAndSet(false, true)) {
                            rawResult.notImplemented()
                        }
                    }
                }
            }
    }

    private fun cleanupPendingTunReceiver() {
        activeTunReceiver?.let { receiver ->
            try {
                unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
            } catch (_: Throwable) {}
        }
        activeTunReceiver = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VPN_REQUEST_CODE) {
            val callback = vpnPrepareResult
            vpnPrepareResult = null
            callback?.invoke(resultCode == Activity.RESULT_OK)
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        CandyVpnService.onTunFdReady = null
        cleanupPendingTunReceiver()
        vpnPrepareResult?.invoke(false)
        vpnPrepareResult = null
        super.onDestroy()
    }
}