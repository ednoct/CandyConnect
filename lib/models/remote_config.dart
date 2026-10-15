class RemoteConfig {
  final ApiEndpoints apiEndpoints;
  final NetworkProbes networkProbes;
  final DnsRouting dnsRouting;
  final SplitTunneling splitTunneling;
  final AntiDpiOverrides antiDpiOverrides;
  final EmergencyAccess emergencyAccess;
  final ClientPreferences clientPreferences;
  final AppControl appControl;
  final PromotionConfig promotions;
  final List<AppNotification> notifications;

  RemoteConfig({
    required this.apiEndpoints,
    required this.networkProbes,
    required this.dnsRouting,
    required this.splitTunneling,
    required this.antiDpiOverrides,
    required this.emergencyAccess,
    required this.clientPreferences,
    required this.appControl,
    required this.promotions,
    required this.notifications,
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    return RemoteConfig(
      apiEndpoints: ApiEndpoints.fromJson(json['api_endpoints'] ?? {}),
      networkProbes: NetworkProbes.fromJson(json['network_probes'] ?? {}),
      dnsRouting: DnsRouting.fromJson(json['dns_routing'] ?? {}),
      splitTunneling: SplitTunneling.fromJson(json['split_tunneling'] ?? {}),
      antiDpiOverrides: AntiDpiOverrides.fromJson(json['anti_dpi_overrides'] ?? {}),
      emergencyAccess: EmergencyAccess.fromJson(json['emergency_access'] ?? {}),
      clientPreferences: ClientPreferences.fromJson(json['client_preferences'] ?? {}),
      appControl: AppControl.fromJson(json['app_control'] ?? {}),
      promotions: PromotionConfig.fromJson(json['promotions'] ?? {}),
      notifications: (json['notifications'] as List<dynamic>?)
              ?.map((e) => AppNotification.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class ApiEndpoints {
  final String baseJsonSubUrl;
  final List<String> baseSubsStatsUrl;
  final List<String> failoverApiUrls;

  ApiEndpoints({
    required this.baseJsonSubUrl,
    required this.baseSubsStatsUrl,
    required this.failoverApiUrls,
  });

  factory ApiEndpoints.fromJson(Map<String, dynamic> json) {
    return ApiEndpoints(
      baseJsonSubUrl: json['base_json_sub_url'] ?? '',
      baseSubsStatsUrl: List<String>.from(json['base_subs_stats_url'] ?? []),
      failoverApiUrls: List<String>.from(json['failover_api_urls'] ?? []),
    );
  }
}

class NetworkProbes {
  final String latencyTargetUrl;
  final int autoReconnectPingThresholdMs;
  final int maxConnectionRetries;

  NetworkProbes({
    required this.latencyTargetUrl,
    required this.autoReconnectPingThresholdMs,
    required this.maxConnectionRetries,
  });

  factory NetworkProbes.fromJson(Map<String, dynamic> json) {
    return NetworkProbes(
      latencyTargetUrl: json['latency_target_url'] ?? '',
      autoReconnectPingThresholdMs: json['auto_reconnect_ping_threshold_ms'] ?? 0,
      maxConnectionRetries: json['max_connection_retries'] ?? 0,
    );
  }
}

class DnsRouting {
  final List<String> bootstrapDnsPool;
  final List<String> remoteDnsPool;

  DnsRouting({
    required this.bootstrapDnsPool,
    required this.remoteDnsPool,
  });

  factory DnsRouting.fromJson(Map<String, dynamic> json) {
    return DnsRouting(
      bootstrapDnsPool: List<String>.from(json['bootstrap_dns_pool'] ?? []),
      remoteDnsPool: List<String>.from(json['remote_dns_pool'] ?? []),
    );
  }
}

class SplitTunneling {
  final bool bypassDomesticTraffic;
  final List<String> directDomains;
  final bool blockAdsAndTrackers;
  final List<String> blockedDomains;

  SplitTunneling({
    required this.bypassDomesticTraffic,
    required this.directDomains,
    required this.blockAdsAndTrackers,
    required this.blockedDomains,
  });

  factory SplitTunneling.fromJson(Map<String, dynamic> json) {
    return SplitTunneling(
      bypassDomesticTraffic: json['bypass_domestic_traffic'] ?? false,
      directDomains: List<String>.from(json['direct_domains'] ?? []),
      blockAdsAndTrackers: json['block_ads_and_trackers'] ?? false,
      blockedDomains: List<String>.from(json['blocked_domains'] ?? []),
    );
  }
}

class AntiDpiOverrides {
  final bool enableDynamicTweaks;
  final List<String> xhttpFallbackSni;
  final String fragmentLength;
  final String fragmentInterval;

  AntiDpiOverrides({
    required this.enableDynamicTweaks,
    required this.xhttpFallbackSni,
    required this.fragmentLength,
    required this.fragmentInterval,
  });

  factory AntiDpiOverrides.fromJson(Map<String, dynamic> json) {
    return AntiDpiOverrides(
      enableDynamicTweaks: json['enable_dynamic_tweaks'] ?? false,
      xhttpFallbackSni: List<String>.from(json['xhttp_fallback_sni'] ?? []),
      fragmentLength: json['fragment_length'] ?? '',
      fragmentInterval: json['fragment_interval'] ?? '',
    );
  }
}

class EmergencyAccess {
  final bool enableHardcodedFallback;
  final List<String> fallbackNodes;

  EmergencyAccess({
    required this.enableHardcodedFallback,
    required this.fallbackNodes,
  });

  factory EmergencyAccess.fromJson(Map<String, dynamic> json) {
    return EmergencyAccess(
      enableHardcodedFallback: json['enable_hardcoded_fallback'] ?? false,
      fallbackNodes: List<String>.from(json['fallback_nodes'] ?? []),
    );
  }
}

class ClientPreferences {
  final int jsonAutoUpdateHours;
  final int subStatsAutoUpdateHours;
  final int githubJsonUpdateHours;
  final String telegramBotHandle;
  final SmuxConfig smux;

  ClientPreferences({
    required this.jsonAutoUpdateHours,
    required this.subStatsAutoUpdateHours,
    required this.githubJsonUpdateHours,
    required this.telegramBotHandle,
    required this.smux,
  });

  factory ClientPreferences.fromJson(Map<String, dynamic> json) {
    return ClientPreferences(
      jsonAutoUpdateHours: json['json_auto_update_hours'] ?? 12,
      subStatsAutoUpdateHours: json['sub_stats_auto_update_hours'] ?? 1,
      githubJsonUpdateHours: json['github_json_update_hours'] ?? 1,
      telegramBotHandle: json['telegram_bot_handle'] ?? '',
      smux: SmuxConfig.fromJson(json['smux'] ?? {}),
    );
  }
}

class SmuxConfig {
  final bool enabled;
  final int maxConnections;

  SmuxConfig({
    required this.enabled,
    required this.maxConnections,
  });

  factory SmuxConfig.fromJson(Map<String, dynamic> json) {
    return SmuxConfig(
      enabled: json['enabled'] ?? false,
      maxConnections: json['max_connections'] ?? 8,
    );
  }
}

class AppControl {
  final String latestVersion;
  final bool forceUpdate;
  final String updateUrl;
  final MaintenanceMode maintenanceMode;

  AppControl({
    required this.latestVersion,
    required this.forceUpdate,
    required this.updateUrl,
    required this.maintenanceMode,
  });

  factory AppControl.fromJson(Map<String, dynamic> json) {
    return AppControl(
      latestVersion: json['latest_version'] ?? '',
      forceUpdate: json['force_update'] ?? false,
      updateUrl: json['update_url'] ?? '',
      maintenanceMode: MaintenanceMode.fromJson(json['maintenance_mode'] ?? {}),
    );
  }
}

class MaintenanceMode {
  final bool active;
  final String message;

  MaintenanceMode({
    required this.active,
    required this.message,
  });

  factory MaintenanceMode.fromJson(Map<String, dynamic> json) {
    return MaintenanceMode(
      active: json['active'] ?? false,
      message: json['message'] ?? '',
    );
  }
}

class PromotionConfig {
  final bool active;
  final String campaignId;
  final String bannerImageUrl;
  final String title;
  final String discountCode;
  final String targetAction;

  PromotionConfig({
    required this.active,
    required this.campaignId,
    required this.bannerImageUrl,
    required this.title,
    required this.discountCode,
    required this.targetAction,
  });

  factory PromotionConfig.fromJson(Map<String, dynamic> json) {
    return PromotionConfig(
      active: json['active'] ?? false,
      campaignId: json['campaign_id'] ?? '',
      bannerImageUrl: json['banner_image_url'] ?? '',
      title: json['title'] ?? '',
      discountCode: json['discount_code'] ?? '',
      targetAction: json['target_action'] ?? '',
    );
  }
}

class AppNotification {
  final String id;
  final bool isActive;
  final String title;
  final String message;
  final String type;
  final bool dismissible;
  final String? actionUrl;

  AppNotification({
    required this.id,
    required this.isActive,
    required this.title,
    required this.message,
    required this.type,
    required this.dismissible,
    this.actionUrl,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] ?? '',
      isActive: json['is_active'] ?? false,
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      type: json['type'] ?? 'info',
      dismissible: json['dismissible'] ?? true,
      actionUrl: json['action_url'],
    );
  }
}