import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class NodeVariant {
  final Map<String, dynamic> node;
  final String remoteDns;

  const NodeVariant({required this.node, required this.remoteDns});

  @override
  String toString() =>
      'NodeVariant(remoteDns: $remoteDns, '
      'nodeKeys: ${node.keys.toList()})';
}

class DnsManager {
  static const int _bootstrapPort = 53;
  static const int _bootstrapTimeoutMs = 1800;

  static const String _fallbackBootstrap = '5.200.200.200';
  static const String _fallbackRemote = '8.8.8.8';

  /// استخراج آدرس IP تمیز (حذف پورت یا اسکیما در صورت وجود در کانفیگ)
  static String _cleanDnsHost(String raw) {
    String s = raw.trim();
    if (s.contains('://')) {
      final uri = Uri.tryParse(s);
      if (uri != null && uri.host.isNotEmpty) return uri.host;
    }
    if (s.contains(':') && !s.contains('[')) {
      return s.split(':').first.trim();
    }
    return s;
  }

  // ── Phase 1: Bootstrap DNS Race ───────────────────────────────────────────

  Future<String> raceBestBootstrap(List<String> pool) async {
    final cleanedPool = pool
        .map(_cleanDnsHost)
        .where((ip) => ip.isNotEmpty)
        .toSet()
        .toList();

    if (cleanedPool.isEmpty) {
      debugPrint('[DnsManager] bootstrapDnsPool is empty — '
          'using fallback $_fallbackBootstrap');
      return _fallbackBootstrap;
    }

    if (cleanedPool.length == 1) {
      debugPrint(
          '[DnsManager] Single bootstrap candidate: ${cleanedPool.first}');
      return cleanedPool.first;
    }

    debugPrint('[DnsManager] Racing ${cleanedPool.length} bootstrap '
        'DNS candidates on port $_bootstrapPort…');

    final probeResults = await Future.wait(
      cleanedPool.map((ip) => _probeBootstrapDns(ip)),
      eagerError: false,
    );

    final ranked = <({int ms, String ip})>[];
    for (int i = 0; i < cleanedPool.length; i++) {
      if (probeResults[i] >= 0) {
        ranked.add((ms: probeResults[i], ip: cleanedPool[i]));
      }
    }
    ranked.sort((a, b) => a.ms.compareTo(b.ms));

    final winner = ranked.firstOrNull?.ip ?? cleanedPool.first;
    debugPrint(
      '[DnsManager] Bootstrap race complete. '
      'Winner: $winner (${ranked.firstOrNull?.ms ?? "—"}ms). '
      'All results: ${ranked.map((r) => "${r.ip}=${r.ms}ms").join(", ")}',
    );
    return winner;
  }

  Future<int> _probeBootstrapDns(String ip) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(
        ip,
        _bootstrapPort,
        timeout: const Duration(milliseconds: _bootstrapTimeoutMs),
      );
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      sw.stop();
      return -1;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  // ── Phase 2: Variant Generation (با Deep Clone کامل) ──────────────────────

  List<NodeVariant> generateVariants({
    required List<dynamic> nodes,
    required List<String> remoteDnsPool,
  }) {
    final cleanedDnsPool = remoteDnsPool
        .map(_cleanDnsHost)
        .where((ip) => ip.isNotEmpty)
        .toSet()
        .toList();

    final effectivePool =
        cleanedDnsPool.isNotEmpty ? cleanedDnsPool : [_fallbackRemote];

    final variants = <NodeVariant>[];
    for (final raw in nodes) {
      if (raw is! Map) continue;

      for (final dns in effectivePool) {
        try {
          // کپی عمیق (Deep Clone) تا دستکاری تگ‌های یک واریانت روی واریانت دیگر اثر نگذارد
          final deepClonedNode = Map<String, dynamic>.from(
            jsonDecode(jsonEncode(raw)) as Map,
          );
          variants.add(NodeVariant(node: deepClonedNode, remoteDns: dns));
        } catch (_) {}
      }
    }

    debugPrint(
      '[DnsManager] Generated ${variants.length} variants '
      '(${nodes.length} nodes × ${effectivePool.length} DNS entries).',
    );
    return variants;
  }
}