package com.vpn.candyconnect

import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log

class CandyVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private val TAG = "CandyVpnService"

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "Starting CandyConnect VpnService")

        val proxyMode = intent?.getIntExtra("proxyMode", 0) ?: 0
        val selectedApps = intent?.getStringArrayListExtra("selectedApps") ?: arrayListOf()

        val builder = Builder()
        builder.setSession("CandyConnect")
        
        // Typical placeholder TUN address, Dart configures the actual rules for xraylib.
        builder.addAddress("172.19.0.1", 30) 
        
        // Route all traffic through the TUN interface.
        builder.addRoute("0.0.0.0", 0)
        builder.addRoute("::", 0)
        
        // DNS
        builder.addDnsServer("1.1.1.1")
        builder.addDnsServer("2606:4700:4700::1111")

        when (proxyMode) {
            1 -> { // Proxy Selected Only
                for (pkg in selectedApps) {
                    try {
                        builder.addAllowedApplication(pkg)
                    } catch (e: PackageManager.NameNotFoundException) {
                        Log.w(TAG, "addAllowed: $pkg not found, skipping")
                    }
                }
            }
            2 -> { // Bypass Selected
                for (pkg in selectedApps) {
                    try {
                        builder.addDisallowedApplication(pkg)
                    } catch (e: PackageManager.NameNotFoundException) {
                        Log.w(TAG, "addDisallowed: $pkg not found, skipping")
                    }
                }
            }
            // 0 = Proxy All -> no filter
        }

        try {
            vpnInterface = builder.establish()
            val fd = vpnInterface?.detachFd() ?: -1
            
            Log.i(TAG, "Established VPN Interface with FD: $fd")
            
            val broadcastIntent = Intent("com.vpn.candyconnect.TUN_FD_BROADCAST")
            broadcastIntent.putExtra("fd", fd)
            sendBroadcast(broadcastIntent)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error establishing VPN interface", e)
        }

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i(TAG, "Destroying CandyConnect VpnService")
        try {
            vpnInterface?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error closing VPN interface", e)
        }
        vpnInterface = null
    }
}
