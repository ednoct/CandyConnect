import NetworkExtension
import Darwin

/// Implementation of NEPacketTunnelProvider for macOS.
/// Configures the virtual `utun` interface, DNS anti-leak rules, and local proxy
/// bridge (`127.0.0.1:10808`) with loop-prevention exclusions.
class PacketTunnelProvider: NEPacketTunnelProvider {

    override init() {
        super.init()
        setenv("GOGC", "50", 1)
    }

    override func startTunnel(
        options: [String : NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        networkSettings.mtu = 1500

        // ۱. تنظیمات IPv4 به همراه استثنا کردن Loopback و LAN جهت جلوگیری از حلقه مسیریابی
        let ipv4Settings = NEIPv4Settings(
            addresses: ["172.19.0.1"],
            subnetMasks: ["255.255.255.252"]
        )
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = [
            NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
        ]
        networkSettings.ipv4Settings = ipv4Settings

        // ۲. هدایت ترافیک به هسته Xray فعال روی پورت لوکال 10808
        let proxySettings = NEProxySettings()
        let localProxyServer = NEProxyServer(address: "127.0.0.1", port: 10808)
        proxySettings.httpEnabled = true
        proxySettings.httpServer = localProxyServer
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = localProxyServer
        proxySettings.excludeSimpleHostnames = true
        proxySettings.exceptionList = [
            "127.0.0.1",
            "localhost",
            "*.local",
            "192.168.0.0/16",
            "10.0.0.0/8",
            "172.16.0.0/12",
        ]
        networkSettings.proxySettings = proxySettings

        // ۳. تنظیمات ضدنشت DNS (Anti-Leak)
        let dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dnsSettings.matchDomains = [""]
        networkSettings.dnsSettings = dnsSettings

        setTunnelNetworkSettings(networkSettings) { error in
            if let error = error {
                NSLog("[CandyConnect macOS PacketTunnel] Error configuring TUN settings: \(error.localizedDescription)")
                completionHandler(error)
                return
            }

            NSLog("[CandyConnect macOS PacketTunnel] Virtual utun interface established successfully.")
            completionHandler(nil)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        NSLog("[CandyConnect macOS PacketTunnel] Stopping tunnel (reason: \(reason.rawValue))")
        completionHandler()
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        completionHandler?(messageData)
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {
    }
}