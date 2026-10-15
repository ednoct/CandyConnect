import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_config.dart';
import '../models/subscription_stats.dart';
import '../services/remote_config_service.dart';
import '../utils/url_launcher_utils.dart';

class IsConnectedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final isConnectedProvider =
    NotifierProvider<IsConnectedNotifier, bool>(IsConnectedNotifier.new);

/// وضعیت حالت تونل (VPN) در برابر پروکسی — پایدارسازی شده و هماهنگ با DesktopManager
class IsVpnModeNotifier extends Notifier<bool> {
  static const _key = 'desktop_vpn_mode';
  bool _disposed = false;

  @override
  bool build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    SharedPreferences.getInstance().then((prefs) {
      if (_disposed) return;
      final saved = prefs.getBool(_key);
      if (saved != null && saved != state) {
        state = saved;
      }
    });
    return true;
  }

  void set(bool value) {
    state = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_key, value));
  }
}

final isVpnModeProvider =
    NotifierProvider<IsVpnModeNotifier, bool>(IsVpnModeNotifier.new);

/// وضعیت پروکسی سیستم‌عامل در دسکتاپ — هماهنگ با ریست و منوی Tray
class IsSystemProxyNotifier extends Notifier<bool> {
  static const _key = 'desktop_system_proxy';
  bool _disposed = false;

  @override
  bool build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    SharedPreferences.getInstance().then((prefs) {
      if (_disposed) return;
      final saved = prefs.getBool(_key);
      if (saved != null && saved != state) {
        state = saved;
      }
    });
    return false;
  }

  void set(bool value) {
    state = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_key, value));
  }
}

final isSystemProxyProvider =
    NotifierProvider<IsSystemProxyNotifier, bool>(IsSystemProxyNotifier.new);

class CurrentLicenseNotifier extends Notifier<String?> {
  static const _key = 'license_key';
  bool _disposed = false;

  @override
  String? build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    SharedPreferences.getInstance().then((prefs) {
      if (_disposed) return;
      final saved = prefs.getString(_key);
      if (saved != null && saved.isNotEmpty && state == null) {
        state = saved;
      }
    });
    return null;
  }

  void set(String? value) {
    state = value;
    if (value != null && value.isNotEmpty) {
      SharedPreferences.getInstance().then((prefs) => prefs.setString(_key, value));
    } else {
      SharedPreferences.getInstance().then((prefs) => prefs.remove(_key));
    }
  }
}

final currentLicenseProvider =
    NotifierProvider<CurrentLicenseNotifier, String?>(
        CurrentLicenseNotifier.new);

class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;
}

final navIndexProvider =
    NotifierProvider<NavIndexNotifier, int>(NavIndexNotifier.new);

// Self-polling Remote Config Notifier
class RemoteConfigNotifier extends Notifier<RemoteConfig?> {
  Timer? _pollTimer;
  bool _isFetching = false;
  bool _disposed = false;
  final _service = RemoteConfigService();

  @override
  RemoteConfig? build() {
    _disposed = false;
    Future.microtask(_fetchAndSchedule);
    ref.onDispose(() {
      _disposed = true;
      _pollTimer?.cancel();
    });
    return null;
  }

  Future<void> _fetchAndSchedule() async {
    if (_isFetching || _disposed) return;
    _isFetching = true;

    try {
      final newConfig = await _service.fetchConfig();
      if (_disposed) return;
      if (newConfig != null) {
        // بروزرسانی خودکار هندل ربات تلگرام در سراسر برنامه
        UrlLauncherUtils.setConfiguredBotHandle(
          newConfig.clientPreferences.telegramBotHandle,
        );

        final oldHours = state?.clientPreferences.githubJsonUpdateHours;
        // تضمین حداقل ۱ ساعت برای جلوگیری از حلقه بی‌نهایت در صورت صفر بودن مقدار در JSON
        final newHours =
            newConfig.clientPreferences.githubJsonUpdateHours.clamp(1, 168);
        state = newConfig;

        if (!_disposed && (_pollTimer == null || oldHours != newHours)) {
          _pollTimer?.cancel();
          _pollTimer = Timer.periodic(
            Duration(hours: newHours),
            (_) => _fetchAndSchedule(),
          );
        }
      } else if (_pollTimer == null && !_disposed) {
        _pollTimer = Timer.periodic(
          const Duration(hours: 1),
          (_) => _fetchAndSchedule(),
        );
      }
    } finally {
      _isFetching = false;
    }
  }

  void set(RemoteConfig? value) {
    if (value != null) {
      UrlLauncherUtils.setConfiguredBotHandle(
        value.clientPreferences.telegramBotHandle,
      );
    }
    state = value;
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

  void set(SubscriptionStats? value) => state = value;
}

final subscriptionStatsProvider =
    NotifierProvider<SubscriptionStatsNotifier, SubscriptionStats?>(
        SubscriptionStatsNotifier.new);

class SubscriptionJsonNotifier extends Notifier<List<dynamic>?> {
  @override
  List<dynamic>? build() => null;

  void set(List<dynamic>? value) => state = value;
}

final subscriptionJsonProvider =
    NotifierProvider<SubscriptionJsonNotifier, List<dynamic>?>(
        SubscriptionJsonNotifier.new);

/// وضعیت اشتراک‌گذاری VPN در شبکه محلی (Allow LAN) — پایدارسازی شده در دیسک
class IsLanSharingNotifier extends Notifier<bool> {
  static const _key = 'allow_lan_sharing';
  bool _disposed = false;

  @override
  bool build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    SharedPreferences.getInstance().then((prefs) {
      if (_disposed) return;
      final saved = prefs.getBool(_key);
      if (saved != null && saved != state) {
        state = saved;
      }
    });
    return false;
  }

  void set(bool value) {
    state = value;
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
  bool _disposed = false;

  @override
  int build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    SharedPreferences.getInstance().then((prefs) {
      if (_disposed) return;
      final saved = prefs.getInt(_key);
      if (saved != null && saved != state) {
        state = saved;
      }
    });
    return 0;
  }

  void set(int value) {
    state = value;
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

  void set(bool value) => state = value;
}

final showSystemAppsProvider =
    NotifierProvider<ShowSystemAppsNotifier, bool>(ShowSystemAppsNotifier.new);

class SelectedAppsNotifier extends Notifier<Set<String>> {
  static const _key = 'selected_apps';
  bool _disposed = false;

  @override
  Set<String> build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    SharedPreferences.getInstance().then((prefs) {
      if (_disposed) return;
      final saved = prefs.getStringList(_key);
      if (saved != null) {
        state = saved.toSet();
      }
    });
    return {};
  }

  void set(Set<String> value) {
    state = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setStringList(_key, value.toList()));
  }

  void toggle(String packageName) {
    final next = Set<String>.from(state);
    if (next.contains(packageName)) {
      next.remove(packageName);
    } else {
      next.add(packageName);
    }
    state = next;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setStringList(_key, next.toList()));
  }
}

final selectedAppsProvider =
    NotifierProvider<SelectedAppsNotifier, Set<String>>(
        SelectedAppsNotifier.new);

// ── UI Dismiss-state providers ────────────────────────────────────────────────

/// نگهداری پایدار آیدی نوتیفیکیشن‌های بسته‌شده توسط کاربر
class DismissedNotificationsNotifier extends Notifier<Set<String>> {
  static const _key = 'dismissed_notification_ids';
  bool _disposed = false;

  @override
  Set<String> build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    SharedPreferences.getInstance().then((prefs) {
      if (_disposed) return;
      final saved = prefs.getStringList(_key);
      if (saved != null && saved.isNotEmpty) {
        state = {...state, ...saved};
      }
    });
    return {};
  }

  void set(Set<String> value) {
    state = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setStringList(_key, value.toList()));
  }

  void dismiss(String id) {
    final next = {...state, id};
    state = next;
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

  void set(bool value) => state = value;
}

final isPromoDismissedProvider =
    NotifierProvider<IsPromoDismissedNotifier, bool>(
        IsPromoDismissedNotifier.new);