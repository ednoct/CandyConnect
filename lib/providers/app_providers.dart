import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/remote_config.dart';
import '../models/subscription_stats.dart';
import '../services/remote_config_service.dart';

class IsConnectedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  set state(bool value) => super.state = value;
}
final isConnectedProvider = NotifierProvider<IsConnectedNotifier, bool>(IsConnectedNotifier.new);

class IsVpnModeNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  set state(bool value) => super.state = value;
}
final isVpnModeProvider = NotifierProvider<IsVpnModeNotifier, bool>(IsVpnModeNotifier.new);

class CurrentLicenseNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  set state(String? value) => super.state = value;
}
final currentLicenseProvider = NotifierProvider<CurrentLicenseNotifier, String?>(CurrentLicenseNotifier.new);

class NavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;
  set state(int value) => super.state = value;
}
final navIndexProvider = NotifierProvider<NavIndexNotifier, int>(NavIndexNotifier.new);

// Self-polling Remote Config Notifier
// Fetches on startup then re-fetches every github_json_update_hours hours.
// If the interval changes in the new config, the timer is rescheduled.
class RemoteConfigNotifier extends Notifier<RemoteConfig?> {
  Timer? _pollTimer;
  final _service = RemoteConfigService();

  @override
  RemoteConfig? build() {
    // Kick off initial fetch immediately.
    Future.microtask(_fetchAndSchedule);
    // Cleanup timer when the provider is disposed.
    ref.onDispose(() => _pollTimer?.cancel());
    return null;
  }

  Future<void> _fetchAndSchedule() async {
    final newConfig = await _service.fetchConfig();
    if (newConfig != null) {
      final oldHours = state?.clientPreferences.githubJsonUpdateHours;
      final newHours = newConfig.clientPreferences.githubJsonUpdateHours;
      state = newConfig;
      // Only reschedule if interval changed or timer not yet running.
      if (_pollTimer == null || oldHours != newHours) {
        _pollTimer?.cancel();
        _pollTimer = Timer.periodic(
          Duration(hours: newHours),
          (_) => _fetchAndSchedule(),
        );
      }
    } else if (_pollTimer == null) {
      // Config fetch failed on first attempt — retry in 1 hour.
      _pollTimer = Timer.periodic(
        const Duration(hours: 1),
        (_) => _fetchAndSchedule(),
      );
    }
  }

  /// Force an immediate re-fetch (e.g., on pull-to-refresh).
  Future<void> refresh() => _fetchAndSchedule();
}
final remoteConfigProvider =
    NotifierProvider<RemoteConfigNotifier, RemoteConfig?>(RemoteConfigNotifier.new);

class SubscriptionStatsNotifier extends Notifier<SubscriptionStats?> {
  @override
  SubscriptionStats? build() => null;
  set state(SubscriptionStats? value) => super.state = value;
}
final subscriptionStatsProvider = NotifierProvider<SubscriptionStatsNotifier, SubscriptionStats?>(SubscriptionStatsNotifier.new);

class SubscriptionJsonNotifier extends Notifier<List<dynamic>?> {
  @override
  List<dynamic>? build() => null;
  set state(List<dynamic>? value) => super.state = value;
}
final subscriptionJsonProvider = NotifierProvider<SubscriptionJsonNotifier, List<dynamic>?>(SubscriptionJsonNotifier.new);

class IsLanSharingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  set state(bool value) => super.state = value;
}
final isLanSharingProvider = NotifierProvider<IsLanSharingNotifier, bool>(IsLanSharingNotifier.new);

// ── Per-App Proxy providers ──────────────────────────────────────────────────

/// 0 = Proxy All, 1 = Proxy Selected Only, 2 = Bypass Selected
class PerAppProxyModeNotifier extends Notifier<int> {
  static const _key = 'per_app_proxy_mode';

  @override
  int build() {
    // Load persisted value asynchronously without blocking
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getInt(_key);
      if (saved != null && saved != state) {
        state = saved;
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
    NotifierProvider<PerAppProxyModeNotifier, int>(PerAppProxyModeNotifier.new);

class ShowSystemAppsNotifier extends Notifier<bool> {
  @override
  bool build() => false;
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
        state = saved.toSet();
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
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setStringList(_key, next.toList()));
  }

  @override
  set state(Set<String> value) => super.state = value;
}
final selectedAppsProvider =
    NotifierProvider<SelectedAppsNotifier, Set<String>>(SelectedAppsNotifier.new);

// ── UI Dismiss-state providers ────────────────────────────────────────────────

/// Tracks which notification IDs have been dismissed this session.
class DismissedNotificationsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void dismiss(String id) {
    state = {...state, id};
  }
}
final dismissedNotificationsProvider =
    NotifierProvider<DismissedNotificationsNotifier, Set<String>>(
        DismissedNotificationsNotifier.new);

/// Whether the promo banner has been dismissed this session.
class IsPromoDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  set state(bool value) => super.state = value;
}
final isPromoDismissedProvider =
    NotifierProvider<IsPromoDismissedNotifier, bool>(IsPromoDismissedNotifier.new);
