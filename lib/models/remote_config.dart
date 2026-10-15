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

  const RemoteConfig({
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
    final rawNotifs = json['notifications'];
    final parsedNotifs = <AppNotification>[];
    if (rawNotifs is List) {
      for (final item in rawNotifs) {
        if (item is Map) {
          parsedNotifs.add(
            AppNotification.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return RemoteConfig(
      apiEndpoints: ApiEndpoints.fromJson(_asMap(json['api_endpoints'])),
      networkProbes: NetworkProbes.fromJson(_asMap(json['network_probes'])),
      dnsRouting: DnsRouting.fromJson(_asMap(json['dns_routing'])),
      splitTunneling: SplitTunneling.fromJson(_asMap(json['split_tunneling'])),
      antiDpiOverrides:
          AntiDpiOverrides.fromJson(_asMap(json['anti_dpi_overrides'])),
      emergencyAccess:
          EmergencyAccess.fromJson(_asMap(json['emergency_access'])),
      clientPreferences:
          ClientPreferences.fromJson(_asMap(json['client_preferences'])),
      appControl: AppControl.fromJson(_asMap(json['app_control'])),
      promotions: PromotionConfig.fromJson(_asMap(json['promotions'])),
      notifications: parsedNotifs,
    );
  }
}

class ApiEndpoints {
  final String baseJsonSubUrl;
  final List<String> baseSubsStatsUrl;
  final List<String> failoverApiUrls;

  const ApiEndpoints({
    required this.baseJsonSubUrl,
    required this.baseSubsStatsUrl,
    required this.failoverApiUrls,
  });

  factory ApiEndpoints.fromJson(Map<String, dynamic> json) {
    return ApiEndpoints(
      baseJsonSubUrl: _asString(json['base_json_sub_url']),
      baseSubsStatsUrl: _asStringList(json['base_subs_stats_url']),
      failoverApiUrls: _asStringList(json['failover_api_urls']),
    );
  }
}

class NetworkProbes {
  final String latencyTargetUrl;
  final int autoReconnectPingThresholdMs;
  final int maxConnectionRetries;

  const NetworkProbes({
    required this.latencyTargetUrl,
    required this.autoReconnectPingThresholdMs,
    required this.maxConnectionRetries,
  });

  factory NetworkProbes.fromJson(Map<String, dynamic> json) {
    return NetworkProbes(
      latencyTargetUrl: _asString(json['latency_target_url']),
      autoReconnectPingThresholdMs:
          _asInt(json['auto_reconnect_ping_threshold_ms'], defaultValue: 0),
      maxConnectionRetries:
          _asInt(json['max_connection_retries'], defaultValue: 0),
    );
  }
}

class DnsRouting {
  final List<String> bootstrapDnsPool;
  final List<String> remoteDnsPool;

  const DnsRouting({
    required this.bootstrapDnsPool,
    required this.remoteDnsPool,
  });

  factory DnsRouting.fromJson(Map<String, dynamic> json) {
    return DnsRouting(
      bootstrapDnsPool: _asStringList(json['bootstrap_dns_pool']),
      remoteDnsPool: _asStringList(json['remote_dns_pool']),
    );
  }
}

class SplitTunneling {
  final bool bypassDomesticTraffic;
  final List<String> directDomains;
  final bool blockAdsAndTrackers;
  final List<String> blockedDomains;

  const SplitTunneling({
    required this.bypassDomesticTraffic,
    required this.directDomains,
    required this.blockAdsAndTrackers,
    required this.blockedDomains,
  });

  factory SplitTunneling.fromJson(Map<String, dynamic> json) {
    return SplitTunneling(
      bypassDomesticTraffic:
          _asBool(json['bypass_domestic_traffic'], defaultValue: false),
      directDomains: _asStringList(json['direct_domains']),
      blockAdsAndTrackers:
          _asBool(json['block_ads_and_trackers'], defaultValue: false),
      blockedDomains: _asStringList(json['blocked_domains']),
    );
  }
}

class AntiDpiOverrides {
  final bool enableDynamicTweaks;
  final List<String> xhttpFallbackSni;
  final String fragmentLength;
  final String fragmentInterval;

  const AntiDpiOverrides({
    required this.enableDynamicTweaks,
    required this.xhttpFallbackSni,
    required this.fragmentLength,
    required this.fragmentInterval,
  });

  factory AntiDpiOverrides.fromJson(Map<String, dynamic> json) {
    return AntiDpiOverrides(
      enableDynamicTweaks:
          _asBool(json['enable_dynamic_tweaks'], defaultValue: false),
      xhttpFallbackSni: _asStringList(json['xhttp_fallback_sni']),
      fragmentLength: _asString(json['fragment_length']),
      fragmentInterval: _asString(json['fragment_interval']),
    );
  }
}

class EmergencyAccess {
  final bool enableHardcodedFallback;
  final List<String> fallbackNodes;

  const EmergencyAccess({
    required this.enableHardcodedFallback,
    required this.fallbackNodes,
  });

  factory EmergencyAccess.fromJson(Map<String, dynamic> json) {
    return EmergencyAccess(
      enableHardcodedFallback:
          _asBool(json['enable_hardcoded_fallback'], defaultValue: false),
      fallbackNodes: _asStringList(json['fallback_nodes']),
    );
  }
}

class ClientPreferences {
  final int jsonAutoUpdateHours;
  final int subStatsAutoUpdateHours;
  final int githubJsonUpdateHours;
  final String telegramBotHandle;
  final SmuxConfig smux;

  const ClientPreferences({
    required this.jsonAutoUpdateHours,
    required this.subStatsAutoUpdateHours,
    required this.githubJsonUpdateHours,
    required this.telegramBotHandle,
    required this.smux,
  });

  factory ClientPreferences.fromJson(Map<String, dynamic> json) {
    return ClientPreferences(
      jsonAutoUpdateHours:
          _asInt(json['json_auto_update_hours'], defaultValue: 12),
      subStatsAutoUpdateHours:
          _asInt(json['sub_stats_auto_update_hours'], defaultValue: 1),
      githubJsonUpdateHours:
          _asInt(json['github_json_update_hours'], defaultValue: 1),
      telegramBotHandle: _asString(json['telegram_bot_handle']),
      smux: SmuxConfig.fromJson(_asMap(json['smux'])),
    );
  }
}

class SmuxConfig {
  final bool enabled;
  final int maxConnections;

  const SmuxConfig({
    required this.enabled,
    required this.maxConnections,
  });

  factory SmuxConfig.fromJson(Map<String, dynamic> json) {
    return SmuxConfig(
      enabled: _asBool(json['enabled'], defaultValue: false),
      maxConnections: _asInt(json['max_connections'], defaultValue: 8),
    );
  }
}

class AppControl {
  final String latestVersion;
  final bool forceUpdate;
  final String updateUrl;
  final MaintenanceMode maintenanceMode;

  const AppControl({
    required this.latestVersion,
    required this.forceUpdate,
    required this.updateUrl,
    required this.maintenanceMode,
  });

  factory AppControl.fromJson(Map<String, dynamic> json) {
    return AppControl(
      latestVersion: _asString(json['latest_version']),
      forceUpdate: _asBool(json['force_update'], defaultValue: false),
      updateUrl: _asString(json['update_url']),
      maintenanceMode:
          MaintenanceMode.fromJson(_asMap(json['maintenance_mode'])),
    );
  }
}

class MaintenanceMode {
  final bool active;
  final String message;

  const MaintenanceMode({
    required this.active,
    required this.message,
  });

  factory MaintenanceMode.fromJson(Map<String, dynamic> json) {
    return MaintenanceMode(
      active: _asBool(json['active'], defaultValue: false),
      message: _asString(json['message']),
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

  const PromotionConfig({
    required this.active,
    required this.campaignId,
    required this.bannerImageUrl,
    required this.title,
    required this.discountCode,
    required this.targetAction,
  });

  factory PromotionConfig.fromJson(Map<String, dynamic> json) {
    return PromotionConfig(
      active: _asBool(json['active'], defaultValue: false),
      campaignId: _asString(json['campaign_id']),
      bannerImageUrl: _asString(json['banner_image_url']),
      title: _asString(json['title']),
      discountCode: _asString(json['discount_code']),
      targetAction: _asString(json['target_action']),
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

  const AppNotification({
    required this.id,
    required this.isActive,
    required this.title,
    required this.message,
    required this.type,
    required this.dismissible,
    this.actionUrl,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawAction = _asString(json['action_url']);
    return AppNotification(
      id: _asString(json['id']),
      isActive: _asBool(json['is_active'], defaultValue: false),
      title: _asString(json['title']),
      message: _asString(json['message']),
      type: _asString(json['type'], defaultValue: 'info'),
      dismissible: _asBool(json['dismissible'], defaultValue: true),
      actionUrl: rawAction.isEmpty ? null : rawAction,
    );
  }
}

// ── توابع کمکی پارس ایمن (جلوگیری از کرش در صورت خطای تایپی در JSON) ─────────

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

String _asString(dynamic value, {String defaultValue = ''}) {
  if (value == null) return defaultValue;
  return value.toString().trim();
}

int _asInt(dynamic value, {int defaultValue = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value.trim()) ??
        double.tryParse(value.trim())?.toInt() ??
        defaultValue;
  }
  return defaultValue;
}

bool _asBool(dynamic value, {bool defaultValue = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return defaultValue;
}

List<String> _asStringList(dynamic value) {
  if (value is List) {
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    return [value.trim()];
  }
  return <String>[];
}