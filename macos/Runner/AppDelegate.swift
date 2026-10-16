import Cocoa
import FlutterMacOS
import Darwin
import NetworkExtension

@_silgen_name("CGoInvoke")
private func cgoInvokeNative(_ requestJSON: UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("CGoFree")
private func cgoFreeNative(_ value: UnsafeMutablePointer<CChar>?) -> Void

@main
class AppDelegate: FlutterAppDelegate {

  /// نگه داشتن صریح آدرس توابع CGoInvoke و CGoFree در باینری نهایی macOS
  /// تا لینکر Xcode در بیلد Release آن‌ها را حذف نکند (Dead Code Stripping Bypass)
  @objc public func keepXraySymbolsAlive() -> UnsafeMutableRawPointer? {
    let invokePtr = unsafeBitCast(
      cgoInvokeNative as @convention(c) (UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>?,
      to: UnsafeMutableRawPointer.self
    )
    let freePtr = unsafeBitCast(
      cgoFreeNative as @convention(c) (UnsafeMutablePointer<CChar>?) -> Void,
      to: UnsafeMutableRawPointer.self
    )
    if Int(bitPattern: invokePtr) == 1 && Int(bitPattern: freePtr) == 1 {
      _ = cgoInvokeNative(nil)
      cgoFreeNative(nil)
    }
    return invokePtr
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    setenv("GOGC", "50", 1)
    _ = keepXraySymbolsAlive()
    super.applicationDidFinishLaunching(notification)
  }

  /// جلوگیری از بسته شدن کامل پروسه وقتی کاربر روی دکمه ضربدر (X) پنجره کلیک می‌کند
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// بازگرداندن پنجره از حالت مخفی در صورت کلیک مجدد روی آیکون برنامه در Dock
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        if window is MainFlutterWindow {
          if window.isMiniaturized {
            window.deminiaturize(self)
          }
          window.makeKeyAndOrderFront(self)
          NSApp.activate(ignoringOtherApps: true)
          break
        }
      }
    }
    return true
  }

  /// خاموش کردن پروکسی‌های سیستم در صورت خروج ناگهانی با Cmd+Q یا Force Quit
  override func applicationWillTerminate(_ notification: Notification) {
    MacOSVpnBridge.shared.disableSystemProxiesSynchronously()
    super.applicationWillTerminate(notification)
  }
}

// MARK: - macOS VPN & System Proxy Bridge ("candyconnect/vpn")

final class MacOSVpnBridge {
  static let shared = MacOSVpnBridge()
  private let channelName = "candyconnect/vpn"
  private var channel: FlutterMethodChannel?

  private init() {}

  func register(with messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    self.channel = methodChannel

    methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, rawResult: @escaping FlutterResult) in
      guard let self = self else {
        rawResult(FlutterError(code: "DEALLOCATED", message: "Bridge deallocated", details: nil))
        return
      }

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
        self.prepareVpn(completion: safeReply)
      case "startVpn":
        self.startVpn(completion: safeReply)
      case "stopVpn":
        self.stopVpn(completion: safeReply)
      default:
        safeReply(FlutterMethodNotImplemented)
      }
    }
  }

  private func prepareVpn(completion: @escaping (Any?) -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
      completion(true)
    }

    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if error != nil {
        completion(true)
        return
      }
      let manager = managers?.first ?? NETunnelProviderManager()
      self.configureManager(manager)
      manager.saveToPreferences { _ in
        completion(true)
      }
    }
  }

  private func startVpn(completion: @escaping (Any?) -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
      completion(-1)
    }

    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if error != nil {
        // Fallback: استفاده از System Proxy در صورت توزیع مستقیم (Unsandboxed/Non-AppStore)
        self.configureMacSystemProxyAsync(enable: true)
        completion(-1)
        return
      }

      let manager = managers?.first ?? NETunnelProviderManager()
      self.configureManager(manager)

      manager.saveToPreferences { saveError in
        if saveError != nil {
          self.configureMacSystemProxyAsync(enable: true)
          completion(-1)
          return
        }
        manager.loadFromPreferences { loadError in
          if loadError == nil {
            do {
              try manager.connection.startVPNTunnel()
            } catch {
              self.configureMacSystemProxyAsync(enable: true)
            }
          } else {
            self.configureMacSystemProxyAsync(enable: true)
          }
          completion(-1)
        }
      }
    }
  }

  private func stopVpn(completion: @escaping (Any?) -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
      completion(true)
    }

    configureMacSystemProxyAsync(enable: false)

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

  /// تشخیص هوشمند شبکه‌های فعال (Wi-Fi، Ethernet، دانگل‌ها)
  private func detectActiveNetworkServices() -> [String] {
    let fallbackServices = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN", "Thunderbolt Bridge"]
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    process.arguments = ["-listallnetworkservices"]
    let outPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
      let data = outPipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        let parsed = output
          .components(separatedBy: .newlines)
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty && !$0.contains("*") && !$0.lowercased().contains("asterisk") }
        if !parsed.isEmpty {
          return parsed
        }
      }
    } catch {}
    return fallbackServices
  }

  /// تنظیم همزمان پروکسی HTTP، HTTPS و SOCKS برای پوشش ۱۰۰ درصدی ترافیک مک
  func configureMacSystemProxyAsync(enable: Bool, host: String = "127.0.0.1", port: String = "10808") {
    DispatchQueue.global(qos: .utility).async {
      let services = self.detectActiveNetworkServices()
      for service in services {
        if enable {
          self.runNetworkSetup([
            "-setproxybypassdomains", service,
            "127.0.0.1", "localhost", "*.local", "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12"
          ])
          self.runNetworkSetup(["-setwebproxy", service, host, port])
          self.runNetworkSetup(["-setwebproxystate", service, "on"])
          self.runNetworkSetup(["-setsecurewebproxy", service, host, port])
          self.runNetworkSetup(["-setsecurewebproxystate", service, "on"])
          self.runNetworkSetup(["-setsocksfirewallproxy", service, host, port])
          self.runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
        } else {
          self.runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
          self.runNetworkSetup(["-setsecurewebproxystate", service, "off"])
          self.runNetworkSetup(["-setwebproxystate", service, "off"])
        }
      }
    }
  }

  func disableSystemProxiesSynchronously() {
    let services = detectActiveNetworkServices()
    for service in services {
      runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
      runNetworkSetup(["-setsecurewebproxystate", service, "off"])
      runNetworkSetup(["-setwebproxystate", service, "off"])
    }
  }

  private func runNetworkSetup(_ args: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    process.arguments = args
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch {}
  }
}