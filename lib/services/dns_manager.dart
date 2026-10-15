import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NodeVariant — a subscription node paired with a specific Remote DNS server
// ─────────────────────────────────────────────────────────────────────────────

/// A pairing of a subscription node config with a specific remote DNS server.
///
/// The [ConnectionOptimizer] benchmarks these variants against each other to
/// find the combination that yields the lowest real HTTP latency.
class NodeVariant {
  final Map<String, dynamic> node;

  /// Remote DNS IP to be injected into the Xray config's proxy-side DNS
  /// (e.g. `"1.1.1.1"` or `"8.8.8.8"`).
  final String remoteDns;

  const NodeVariant({required this.node, required this.remoteDns});

  @override
  String toString() =>
      'NodeVariant(remoteDns: $remoteDns, '
      'nodeKeys: ${node.keys.toList()})';
}

// ─────────────────────────────────────────────────────────────────────────────
// DnsManager
// ─────────────────────────────────────────────────────────────────────────────

/// Handles the two DNS pre-processing steps in the connection pipeline:
///
/// ### Phase 1 — Bootstrap DNS Race
/// Races TCP connections to **port 53** for every IP in
/// `dnsRouting.bootstrapDnsPool`.  Returns the single lowest-latency IP.
/// This IP will be used as the *direct* (outside-proxy) DNS resolver, ensuring
/// the proxy server's hostname can be resolved without a circular dependency.
///
/// ### Phase 2 — Variant Generation
/// Cross-multiplies a list of nodes (typically the top-3 TCP-ranked nodes)
/// against `dnsRouting.remoteDnsPool` to produce [NodeVariant]s.
/// Example: 3 nodes × 2 remote DNS = 6 variants.
class DnsManager {
  // ── Constants ─────────────────────────────────────────────────────────────

  static const int _bootstrapPort = 53;
  static const int _bootstrapTimeoutMs = 2000;

  // Hard-coded fallback used only when both the pool is empty and the race
  // fails completely.
  static const String _fallbackBootstrap = '5.200.200.200';
  static const String _fallbackRemote = '8.8.8.8';

  // ── Phase 1: Bootstrap DNS Race ───────────────────────────────────────────

  /// Concurrently TCP-connects to port 53 for each IP in [pool] and returns
  /// the lowest-latency winner.
  ///
  /// Falls back to [_fallbackBootstrap] if [pool] is empty or all probes fail.
  /// Per the approved plan, this deliberately uses TCP (not UDP), which is
  /// universally supported on all platforms via `dart:io`'s `Socket.connect`.
  Future<String> raceBestBootstrap(List<String> pool) async {
    if (pool.isEmpty) {
      debugPrint('[DnsManager] bootstrapDnsPool is empty — '
          'using fallback $_fallbackBootstrap');
      return _fallbackBootstrap;
    }

    if (pool.length == 1) {
      debugPrint('[DnsManager] Single bootstrap candidate: ${pool.first}');
      return pool.first;
    }

    debugPrint('[DnsManager] Racing ${pool.length} bootstrap '
        'DNS candidates on port $_bootstrapPort…');

    // Race all probes concurrently; never throw — individual failures return -1
    final probeResults = await Future.wait(
      pool.map((ip) => _probeBootstrapDns(ip)),
      eagerError: false,
    );

    // Pair latency results with their corresponding IPs
    final ranked = <({int ms, String ip})>[];
    for (int i = 0; i < pool.length; i++) {
      if (probeResults[i] >= 0) {
        ranked.add((ms: probeResults[i], ip: pool[i]));
      }
    }
    ranked.sort((a, b) => a.ms.compareTo(b.ms));

    final winner = ranked.firstOrNull?.ip ?? pool.first;
    debugPrint(
      '[DnsManager] Bootstrap race complete. '
      'Winner: $winner (${ranked.firstOrNull?.ms ?? "—"}ms). '
      'All results: ${ranked.map((r) => "${r.ip}=${r.ms}ms").join(", ")}',
    );
    return winner;
  }

  /// Single TCP-handshake probe to [ip]:53.
  /// Returns elapsed milliseconds, or -1 if the connection fails / times out.
  Future<int> _probeBootstrapDns(String ip) async {
    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        ip,
        _bootstrapPort,
        timeout: const Duration(milliseconds: _bootstrapTimeoutMs),
      );
      sw.stop();
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      sw.stop();
      return -1;
    }
  }

  // ── Phase 2: Variant Generation ───────────────────────────────────────────

  /// Cross-multiplies [nodes] against [remoteDnsPool] to produce [NodeVariant]s.
  ///
  /// Example:
  /// ```
  /// nodes        = [NodeA, NodeB, NodeC]  (top-3 TCP-ranked)
  /// remoteDnsPool = ["1.1.1.1", "8.8.8.8"]
  ///
  /// → Variant 1:  NodeA + 1.1.1.1
  /// → Variant 2:  NodeA + 8.8.8.8
  /// → Variant 3:  NodeB + 1.1.1.1
  /// → Variant 4:  NodeB + 8.8.8.8
  /// → Variant 5:  NodeC + 1.1.1.1
  /// → Variant 6:  NodeC + 8.8.8.8
  /// ```
  ///
  /// If [remoteDnsPool] is empty, one variant per node is produced using the
  /// hard-coded fallback DNS.
  List<NodeVariant> generateVariants({
    required List<dynamic> nodes,
    required List<String> remoteDnsPool,
  }) {
    final effectivePool =
        remoteDnsPool.isNotEmpty ? remoteDnsPool : [_fallbackRemote];

    final variants = <NodeVariant>[];
    for (final raw in nodes) {
      if (raw is! Map) continue;
      // Deep-clone the node map so variants are independent of each other
      final node = Map<String, dynamic>.from(raw);
      for (final dns in effectivePool) {
        variants.add(NodeVariant(node: node, remoteDns: dns));
      }
    }

    debugPrint(
      '[DnsManager] Generated ${variants.length} variants '
      '(${nodes.length} nodes × ${effectivePool.length} DNS entries).',
    );
    return variants;
  }
}
