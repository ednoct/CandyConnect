import NetworkExtension

/// Implementation of NEPacketTunnelProvider for Apple ecosystem (iOS and macOS).
/// 
/// REQUIRES ENTITLEMENT: `com.apple.developer.networking.networkextension`
/// 
/// This provider configures the virtual `utun` interface and routes all traffic
/// to it. The underlying Xray core (xraylib) will bind its TUN inbound to this interface.
class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        // IPv4 Configuration
        let ipv4Settings = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        networkSettings.ipv4Settings = ipv4Settings
        
        // IPv6 Configuration
        let ipv6Settings = NEIPv6Settings(addresses: ["fd00::1"], networkPrefixLengths: [120])
        ipv6Settings.includedRoutes = [NEIPv6Route.default()]
        networkSettings.ipv6Settings = ipv6Settings
        
        // DNS Configuration (Anti-Leak)
        let dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "2606:4700:4700::1111"])
        dnsSettings.matchDomains = [""]
        networkSettings.dnsSettings = dnsSettings

        setTunnelNetworkSettings(networkSettings) { error in
            if let error = error {
                NSLog("CandyConnect: Error configuring TUN settings: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            
            // At this point, the `utun` interface is up. 
            // Xray core binds natively, intercepting the routed traffic.
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // Handle teardown of the Xray core or clean up resources if needed
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Can be used to exchange dynamic configuration between the Flutter UI and the VPN Extension
        if let handler = completionHandler {
            handler(messageData)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {
    }
}
