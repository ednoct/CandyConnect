import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_config.dart';
import '../models/subscription_stats.dart';
import '../services/remote_config_service.dart';

class IsConnectedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

final isConnectedProvider =
    NotifierProvider<IsConnectedNotifier, bool>(IsConnectedNotifier.new);

/// وضعیت حالت تونل (VPN) در برابر پروکسی — پایدارسازی شده و هماهنگ با DesktopManager
class IsVpnModeNotifier extends Notifier<bool> {
  static const _key = 'desktop_vpn_mode';

  @override
  bool build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_key);
      if (saved != null && saved != state) {
        super.state = saved;
      }
    });
    return true;
  }

  @override
  set state(bool value) {
    super.state = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_key, value));
  }
}

final isVpnModeProvider =
    NotifierProvider<IsVpnModeNotifier, bool>(IsVpnModeNotifier.new);

/// وضعیت پروکسی کل سیستم در دسکتاپ — منبع حقیقت واحد بین SettingsTab و System Tray
class DesktopSystemProxyNotifier extends Notifier<bool> {
  static const _key = 'desktop_system_proxy';

  @override
  bool build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_key);
      if (saved != null && saved != state) {
        super.state = saved;
      }
    });
    return false;
  }

  @override
  set state(bool value) {
    super.state = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_key, value));
  }
}

final desktopSystemProxyProvider =
    NotifierProvider<DesktopSystemProxyNotifier, bool>(
        DesktopSystemProxyNotifier.new);

class CurrentLicenseNotifier extends Notifier<String?> {
  static const _key = 'license_key';

  @override
  String? build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_key);
      if (saved != null && saved.isNotEmpty && state == null) {
        super.state = saved;
      }
    });
    return null;
  }

  @override
  set state(String? value) => super.state = value;
}

final currentLicenseProvider =
    NotifierProvider<CurrentLicenseNotifier, String?>(
        CurrentLicenseNotifier.new);

class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  @override
  set state(int value) => super.state = value;
}

final navIndexProvider =
    NotifierProvider<NavIndexNotifier, int>(NavIndexNotifier.new);

// Self-polling Remote Config Notifier
class RemoteConfigNotifier extends Notifier<RemoteConfig?> {
  Timer? _pollTimer;
  bool _isFetching = false;
  final _service = RemoteConfigService();

  @override
  RemoteConfig? build() {
    Future.microtask(_fetchAndSchedule);
    ref.onDispose(() => _pollTimer?.cancel());
    return null;
  }

  Future<void> _fetchAndSchedule() async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      final newConfig = await _service.fetchConfig();
      if (newConfig != null) {
        final oldHours = state?.clientPreferences.githubJsonUpdateHours;
        final newHours =
            newConfig.clientPreferences.githubJsonUpdateHours.clamp(1, 168);
        state = newConfig;

        if (_pollTimer == null || oldHours != newHours) {
          _pollTimer?.cancel();
          _pollTimer = Timer.periodic(
            Duration(hours: newHours),
            (_) => _fetchAndSchedule(),
          );
        }
      } else if (_pollTimer == null) {
        _pollTimer = Timer.periodic(
          const Duration(hours: 1),
          (_) => _fetchAndSchedule(),
        );
      }
    } finally {
      _isFetching = false;
    }
  }

  /// بروزرسانی دستی تنظیمات سرور
  Future<void> refresh() => _fetchAndSchedule();
}

final remoteConfigProvider =
    NotifierProvider<RemoteConfigNotifier, RemoteConfig?>(
        RemoteConfigNotifier.new);

class SubscriptionStatsNotifier extends Notifier<SubscriptionStats?> {
  @override
  SubscriptionStats? build() => null;

  @override
  set state(SubscriptionStats? value) => super.state = value;
}

final subscriptionStatsProvider =
    NotifierProvider<SubscriptionStatsNotifier, SubscriptionStats?>(
        SubscriptionStatsNotifier.new);

class SubscriptionJsonNotifier extends Notifier<List<dynamic>?> {
  @override
  List<dynamic>? build() => null;

  @override
  set state(List<dynamic>? value) => super.state = value;
}

final subscriptionJsonProvider =
    NotifierProvider<SubscriptionJsonNotifier, List<dynamic>?>(
        SubscriptionJsonNotifier.new);

/// وضعیت اشتراک‌گذاری VPN در شبکه محلی (Allow LAN) — پایدارسازی شده در دیسک
class IsLanSharingNotifier extends Notifier<bool> {
  static const _key = 'allow_lan_sharing';

  @override
  bool build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_key);
      if (saved != null && saved != state) {
        super.state = saved;
      }
    });
    return false;
  }

  @override
  set state(bool value) {
    super.state = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_key, value));
  }
}

final isLanSharingProvider =
    NotifierProvider<IsLanSharingNotifier, bool>(IsLanSharingNotifier.new);

// ── Per-App Proxy providers ──────────────────────────────────────────────────

/// 0 = Proxy All, 1 = Proxy Selected Only, 2 = Bypass Selected
class PerAppProxyModeNotifier extends Notifier<int> {
  static const _key = 'per_app_proxy_mode';

  @override
  int build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getInt(_key);
      if (saved != null && saved != state) {
        super.state = saved;
      }
    });
    return 0;
  }

  @override
  set state(int value) {
    super.state = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt(_key, value));
  }
}

final perAppProxyModeProvider =
    NotifierProvider<PerAppProxyModeNotifier, int>(
        PerAppProxyModeNotifier.new);

class ShowSystemAppsNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

final showSystemAppsProvider =
    NotifierProvider<ShowSystemAppsNotifier, bool>(ShowSystemAppsNotifier.new);

class SelectedAppsNotifier extends Notifier<Set<String>> {
  static const _key = 'selected_apps';

  @override
  Set<String> build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getStringList(_key);
      if (saved != null) {
        super.state = saved.toSet();
      }
    });
    return {};
  }

  void toggle(String packageName) {
    final next = Set<String>.from(state);
    if (next.contains(packageName)) {
      next.remove(packageName);
    } else {
      next.add(packageName);
    }
    state = next;
  }

  @override
  set state(Set<String> value) {
    super.state = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setStringList(_key, value.toList()));
  }
}

final selectedAppsProvider =
    NotifierProvider<SelectedAppsNotifier, Set<String>>(
        SelectedAppsNotifier.new);

// ── UI Dismiss-state providers ────────────────────────────────────────────────

/// نگهداری پایدار آیدی نوتیفیکیشن‌های بسته‌شده توسط کاربر
class DismissedNotificationsNotifier extends Notifier<Set<String>> {
  static const _key = 'dismissed_notification_ids';

  @override
  Set<String> build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getStringList(_key);
      if (saved != null && saved.isNotEmpty) {
        super.state = {...state, ...saved};
      }
    });
    return {};
  }

  void dismiss(String id) {
    final next = {...state, id};
    super.state = next;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setStringList(_key, next.toList()));
  }
}

final dismissedNotificationsProvider =
    NotifierProvider<DismissedNotificationsNotifier, Set<String>>(
        DismissedNotificationsNotifier.new);

class IsPromoDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

final isPromoDismissedProvider =
    NotifierProvider<IsPromoDismissedNotifier, bool>(
        IsPromoDismissedNotifier.new);