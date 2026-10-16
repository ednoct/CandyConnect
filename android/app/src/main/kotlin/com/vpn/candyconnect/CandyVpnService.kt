package com.vpn.candyconnect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.system.Os
import android.util.Log
import androidx.core.app.NotificationCompat

class CandyVpnService : VpnService() {

    companion object {
        private const val TAG = "CandyVpnService"
        const val ACTION_START_VPN = "com.vpn.candyconnect.START_VPN"
        const val ACTION_STOP_VPN = "com.vpn.candyconnect.STOP_VPN"
        const val ACTION_TUN_FD_BROADCAST = "com.vpn.candyconnect.TUN_FD_BROADCAST"

        private const val NOTIFICATION_CHANNEL_ID = "candyconnect_vpn_channel"
        private const val NOTIFICATION_ID = 1001

        @Volatile
        private var instance: CandyVpnService? = null

        @Volatile
        private var activeTunFd: Int = -1

        @Volatile
        var onTunFdReady: ((Int) -> Unit)? = null

        private val mainHandler = Handler(Looper.getMainLooper())

        /**
         * بستن ایمن توصیف‌گر فایل (FD) جداشده (Detached) در سطح کرنل لینوکس.
         * ابتدا از طریق /proc/self/fd بررسی می‌کند که آیا FD هنوز باز است و به اینترفیس tun اشاره دارد؛
         * اگر هسته Go (libXray.so) قبلاً آن را بسته باشد، از بستن مجدد (EBADF / fdsan) جلوگیری می‌کند.
         */
        @Synchronized
        fun closeDetachedFdSafely(fd: Int) {
            if (fd < 0) return
            try {
                val linkTarget = Os.readlink("/proc/self/fd/$fd")
                if (linkTarget.contains("tun", ignoreCase = true)) {
                    ParcelFileDescriptor.adoptFd(fd).close()
                    Log.i(TAG, "Safely closed detached TUN fd: $fd")
                }
            } catch (_: Throwable) {
                // توصیف‌گر فایل قبلاً توسط libXray.so در زمان stopXray بسته شده است
            }
        }

        /**
         * توقف فوری تونل فعال از سمت MainActivity
         */
        fun stopActiveTunnel(context: Context) {
            val capturedFd = activeTunFd
            activeTunFd = -1

            instance?.let { service ->
                service.teardownForegroundAndStop(capturedFd)
            } ?: run {
                mainHandler.postDelayed({
                    closeDetachedFdSafely(capturedFd)
                }, 380L)
                try {
                    context.stopService(Intent(context, CandyVpnService::class.java))
                } catch (_: Throwable) {}
            }
        }
    }

    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || intent.action == ACTION_STOP_VPN) {
            Log.i(TAG, "Stopping CandyConnect VpnService via intent")
            val capturedFd = activeTunFd
            activeTunFd = -1
            teardownForegroundAndStop(capturedFd)
            return START_NOT_STICKY
        }

        // ۱. ارتقای سرویس به حالت Foreground با رعایت الزامات اندروید ۱۴ و ۱۵ (API 34+)
        promoteToForeground()

        // ۲. بستن اینترفیس قبلی در صورت وجود (در سناریوی تعویض سریع سرور / Hot-Switch)
        val previousFd = activeTunFd
        activeTunFd = -1
        if (previousFd >= 0) {
            closeDetachedFdSafely(previousFd)
        }
        try {
            vpnInterface?.close()
        } catch (_: Throwable) {}
        vpnInterface = null

        val proxyMode = intent.getIntExtra("proxyMode", 0)
        val selectedApps = intent.getStringArrayListExtra("selectedApps") ?: arrayListOf()

        val builder = Builder()
            .setSession("CandyConnect")
            .setMtu(1500)
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
            .setBlocking(false)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        // ۳. اعمال قوانین Split Tunneling (پروکسی برای هر برنامه) همراه با محافظت ضدحلقه (Anti-Loop)
        when (proxyMode) {
            1 -> {
                // فقط برنامه‌های انتخاب‌شده از تونل عبور کنند
                var addedCount = 0
                for (pkg in selectedApps) {
                    val cleanPkg = pkg.trim()
                    if (cleanPkg.isEmpty() || cleanPkg == packageName) continue
                    try {
                        builder.addAllowedApplication(cleanPkg)
                        addedCount++
                    } catch (e: PackageManager.NameNotFoundException) {
                        Log.w(TAG, "addAllowedApplication: $cleanPkg not found, skipping")
                    } catch (e: Exception) {
                        Log.w(TAG, "addAllowedApplication error for $cleanPkg: ${e.message}")
                    }
                }
                // اگر لیست برنامه‌های انتخابی خالی بود، حتماً خود برنامه را مستثنی کن تا حلقه بی‌نهایت رخ ندهد
                if (addedCount == 0) {
                    try {
                        builder.addDisallowedApplication(packageName)
                    } catch (e: Exception) {
                        Log.w(TAG, "Fallback addDisallowed self failed: ${e.message}")
                    }
                }
            }
            2 -> {
                // استثنا کردن برنامه‌های انتخاب‌شده (Bypass Selected)
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (e: Exception) {
                    Log.w(TAG, "addDisallowed self failed: ${e.message}")
                }
                for (pkg in selectedApps) {
                    val cleanPkg = pkg.trim()
                    if (cleanPkg.isEmpty() || cleanPkg == packageName) continue
                    try {
                        builder.addDisallowedApplication(cleanPkg)
                    } catch (e: PackageManager.NameNotFoundException) {
                        Log.w(TAG, "addDisallowedApplication: $cleanPkg not found, skipping")
                    } catch (e: Exception) {
                        Log.w(TAG, "addDisallowedApplication error for $cleanPkg: ${e.message}")
                    }
                }
            }
            else -> {
                // حالت ۰: پروکسی کردن تمام برنامه‌ها (به جز خود CandyConnect جهت خروج مستقیم ترافیک هسته Xray)
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (e: Exception) {
                    Log.w(TAG, "addDisallowed self failed: ${e.message}")
                }
            }
        }

        // ۴. ایجاد اینترفیس TUN و تحویل FD به لایه دارت
        var establishedFd = -1
        try {
            vpnInterface = builder.establish()
            establishedFd = vpnInterface?.detachFd() ?: -1
            activeTunFd = establishedFd
            vpnInterface = null
            Log.i(TAG, "Established VPN Interface with FD: $establishedFd")
        } catch (e: Exception) {
            Log.e(TAG, "Error establishing VPN interface", e)
            establishedFd = -1
        }

        // ارسال آنی FD از طریق کالبک مستقیم و Broadcast پشتیبان
        onTunFdReady?.invoke(establishedFd)

        val broadcastIntent = Intent(ACTION_TUN_FD_BROADCAST).apply {
            setPackage(packageName)
            putExtra("fd", establishedFd)
        }
        sendBroadcast(broadcastIntent)

        if (establishedFd < 0) {
            teardownForegroundAndStop(-1)
            return START_NOT_STICKY
        }

        return START_REDELIVER_INTENT
    }

    private fun promoteToForeground() {
        try {
            val notification = buildForegroundNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to start foreground notification: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "وضعیت اتصال کندی‌کانکت",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "نمایش وضعیت فعال بودن تونل امن VPN"
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            pendingFlags
        )

        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("CandyConnect متصل است")
            .setContentText("ترافیک دستگاه شما از تونل امن عبور می‌کند")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun teardownForegroundAndStop(fdToClose: Int) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {}

        try {
            vpnInterface?.close()
        } catch (_: Throwable) {}
        vpnInterface = null

        if (fdToClose >= 0) {
            // وقفه ۳۸۰ میلی‌ثانیه‌ای تا XrayBridge.stopXray() ابتدا هسته Go را متوقف کند،
            // سپس اگر FD هنوز در کرنل باز مانده بود، به صورت ایمن بسته شود.
            mainHandler.postDelayed({
                closeDetachedFdSafely(fdToClose)
            }, 380L)
        }

        try {
            stopSelf()
        } catch (_: Throwable) {}
    }

    override fun onRevoke() {
        Log.i(TAG, "VPN permission revoked by user or system")
        val capturedFd = activeTunFd
        activeTunFd = -1
        teardownForegroundAndStop(capturedFd)
        super.onRevoke()
    }

    override fun onDestroy() {
        Log.i(TAG, "Destroying CandyConnect VpnService")
        val capturedFd = activeTunFd
        activeTunFd = -1
        if (instance === this) {
            instance = null
        }
        try {
            vpnInterface?.close()
        } catch (_: Throwable) {}
        vpnInterface = null

        if (capturedFd >= 0) {
            mainHandler.postDelayed({
                closeDetachedFdSafely(capturedFd)
            }, 380L)
        }
        super.onDestroy()
    }
}