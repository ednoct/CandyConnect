import Flutter
import UIKit
import NetworkExtension
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private static let vpnChannelName = "candyconnect/vpn"
  private var vpnMethodChannel: FlutterMethodChannel?
  private var isChannelConfigured = false

  /// تضمین حفظ سیمبل‌های CGoInvoke و CGoFree در جدول سیمبل‌های باینری Release
  /// تا فراخوانی DynamicLibrary.process().lookupFunction در دارت هرگز با خطای dlsym مواجه نشود
  @objc public func keepXraySymbolsAlive() -> UnsafeMutableRawPointer? {
    let invokePtr = unsafeBitCast(
      CGoInvoke as @convention(c) (UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>?,
      to: UnsafeMutableRawPointer.self
    )
    let freePtr = unsafeBitCast(
      CGoFree as @convention(c) (UnsafeMutablePointer<CChar>?) -> Void,
      to: UnsafeMutableRawPointer.self
    )
    if Int(bitPattern: invokePtr) == 1 && Int(bitPattern: freePtr) == 1 {
      _ = CGoInvoke(nil)
      CGoFree(nil)
    }
    return invokePtr
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // بهینه‌سازی مصرف حافظه گاربج‌کالکتور Go در iOS
    setenv("GOGC", "50", 1)

    // نگه داشتن مرجع سیمبل‌های CGo در زمان راه‌اندازی
    _ = keepXraySymbolsAlive()

    let res = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // پشتیبانی همزمان از معماری کلاسیک AppDelegate و معماری جدید ImplicitEngine
    if !isChannelConfigured, let registrar = self.registrar(forPlugin: "CandyConnectVpnBridge") {
      setupVpnChannel(messenger: registrar.messenger())
    }

    return res
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if !isChannelConfigured,
       let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CandyConnectVpnBridge") {
      setupVpnChannel(messenger: registrar.messenger())
    }
  }

  // MARK: - MethodChannel ("candyconnect/vpn")

  private func setupVpnChannel(messenger: FlutterBinaryMessenger) {
    guard !isChannelConfigured else { return }
    isChannelConfigured = true

    let channel = FlutterMethodChannel(
      name: AppDelegate.vpnChannelName,
      binaryMessenger: messenger
    )
    self.vpnMethodChannel = channel

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, rawResult: @escaping FlutterResult) in
      guard let self = self else {
        rawResult(FlutterError(code: "DEALLOCATED", message: "AppDelegate deallocated", details: nil))
        return
      }

      // گارد اتمیک برای جلوگیری از فراخوانی مضاعف FlutterResult یا قفل شدن await در دارت
      let lock = NSLock()
      var hasReplied = false
      let safeReply: (Any?) -> Void = { value in
        lock.lock()
        let shouldSend = !hasReplied
        hasReplied = true
        lock.unlock()
        if shouldSend {
          DispatchQueue.main.async {
            rawResult(value)
          }
        }
      }

      switch call.method {
      case "prepareVpn":
        self.prepareVpnProfile(completion: safeReply)

      case "startVpn":
        self.startVpnTunnel(completion: safeReply)

      case "stopVpn":
        self.stopVpnTunnel(completion: safeReply)

      default:
        safeReply(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - NETunnelProviderManager Lifecycle

  private func prepareVpnProfile(completion: @escaping (Any?) -> Void) {
    // تایم‌اوت ایمن ۴ ثانیه‌ای تا رابط کاربری هرگز قفل نشود
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
      completion(true)
    }

    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error = error {
        NSLog("[CandyConnect iOS] loadAllFromPreferences warning: \(error.localizedDescription)")
        completion(true)
        return
      }

      let manager = managers?.first ?? NETunnelProviderManager()
      self.configureManager(manager)

      manager.saveToPreferences { saveError in
        if let saveError = saveError {
          // در بیلدهای Unsigned یا بدون Entitlement، خطا را لاگ کن و اجازه بده هسته لوکال Xray کار کند
          NSLog("[CandyConnect iOS] saveToPreferences skipped/unsupported: \(saveError.localizedDescription)")
        }
        completion(true)
      }
    }
  }

  private func startVpnTunnel(completion: @escaping (Any?) -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
      completion(-1)
    }

    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error = error {
        NSLog("[CandyConnect iOS] startVpn loadAll error: \(error.localizedDescription)")
        completion(-1)
        return
      }

      let manager = managers?.first ?? NETunnelProviderManager()
      self.configureManager(manager)

      manager.saveToPreferences { saveError in
        if let saveError = saveError {
          NSLog("[CandyConnect iOS] startVpn save error (running in local proxy mode): \(saveError.localizedDescription)")
          completion(-1)
          return
        }

        manager.loadFromPreferences { loadError in
          if let loadError = loadError {
            NSLog("[CandyConnect iOS] startVpn reload error: \(loadError.localizedDescription)")
            completion(-1)
            return
          }

          do {
            try manager.connection.startVPNTunnel()
            NSLog("[CandyConnect iOS] System VPN tunnel start requested successfully.")
          } catch let startErr {
            NSLog("[CandyConnect iOS] startVPNTunnel failed: \(startErr.localizedDescription)")
          }
          // در iOS، هسته Xray با xray.tun.fd = -1 اجرا می‌شود
          completion(-1)
        }
      }
    }
  }

  private func stopVpnTunnel(completion: @escaping (Any?) -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
      completion(true)
    }

    NETunnelProviderManager.loadAllFromPreferences { managers, _ in
      if let managers = managers {
        for manager in managers {
          let status = manager.connection.status
          if status != .disconnected && status != .invalid {
            manager.connection.stopVPNTunnel()
          }
        }
      }
      completion(true)
    }
  }

  private func configureManager(_ manager: NETunnelProviderManager) {
    let bundleId = Bundle.main.bundleIdentifier ?? "online.candyconnect.candyconnect"
    let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
    proto.providerBundleIdentifier = "\(bundleId).PacketTunnel"
    proto.serverAddress = "CandyConnect Secure Core"
    proto.disconnectOnSleep = false

    manager.protocolConfiguration = proto
    manager.localizedDescription = "CandyConnect"
    manager.isEnabled = true
  }
}