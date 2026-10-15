import 'dart:async';
import 'dart:io';
import 'dart:isolate';

// ─────────────────────────────────────────────────────────────────────────────
// Public result type
// ─────────────────────────────────────────────────────────────────────────────

class NodeLatencyResult {
  final dynamic node; // original Map<String, dynamic> from subscription JSON
  final int latencyMs; // TCP handshake duration; -1 = unreachable

  const NodeLatencyResult({required this.node, required this.latencyMs});

  bool get isReachable => latencyMs >= 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Message types sent to/from the probe Isolate
// ─────────────────────────────────────────────────────────────────────────────

class _ProbeRequest {
  final SendPort replyPort;
  final List<_NodeEndpoint> endpoints;
  final int timeoutMs;

  const _ProbeRequest({
    required this.replyPort,
    required this.endpoints,
    required this.timeoutMs,
  });
}

class _NodeEndpoint {
  final int index; // maps back to the original node list
  final String host;
  final int port;

  const _NodeEndpoint({
    required this.index,
    required this.host,
    required this.port,
  });
}

class _ProbeResult {
  final int index;
  final int latencyMs; // -1 = unreachable / timeout

  const _ProbeResult({required this.index, required this.latencyMs});
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate entry-point  (MUST be top-level)
// ─────────────────────────────────────────────────────────────────────────────

// ignore: library_private_types_in_public_api
void _probeIsolateEntry(_ProbeRequest req) async {
  final futures = req.endpoints.map((ep) => _probeOne(ep, req.timeoutMs));
  final results = await Future.wait(futures);
  req.replyPort.send(results);
}

Future<_ProbeResult> _probeOne(_NodeEndpoint ep, int timeoutMs) async {
  final sw = Stopwatch()..start();
  try {
    final socket = await Socket.connect(
      ep.host,
      ep.port,
      timeout: Duration(milliseconds: timeoutMs),
    );
    sw.stop();
    socket.destroy();
    return _ProbeResult(index: ep.index, latencyMs: sw.elapsedMilliseconds);
  } catch (_) {
    sw.stop();
    return _ProbeResult(index: ep.index, latencyMs: -1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Host/port extractor
// Handles multiple Xray/V2Ray config schemas:
//   1. outbounds[].settings.vnext[].{address, port}   (VLESS/VMess)
//   2. outbounds[].settings.servers[].{address, port} (Shadowsocks/Trojan/HTTP)
//   3. Top-level "address"/"port"
//   4. Top-level "server"/"server_port" (Shadowsocks-style flat keys)
//   5. outbounds[].streamSettings host headers (ws/http)
// ─────────────────────────────────────────────────────────────────────────────

_NodeEndpoint? _extractEndpoint(int index, dynamic node) {
  if (node is! Map<String, dynamic>) return null;

  // ── 1 & 2: standard Xray outbounds ────────────────────────────────────────
  final outbounds = node['outbounds'];
  if (outbounds is List && outbounds.isNotEmpty) {
    for (final ob in outbounds) {
      if (ob is! Map<String, dynamic>) continue;
      final tag = (ob['tag'] as String? ?? '').toLowerCase();
      if (tag == 'direct' || tag == 'block') continue;

      final settings = ob['settings'];
      if (settings is Map<String, dynamic>) {
        // ── Flat VLESS/VLESS-reality: settings.address + settings.port ────
        // This is the primary schema used by this subscription server:
        //   outbounds[].settings = { "address": "1.2.3.4", "port": 443, ... }
        final hostFlat = settings['address'] as String?;
        final portFlat = settings['port'];
        if (hostFlat != null && hostFlat.isNotEmpty && portFlat != null) {
          return _NodeEndpoint(
              index: index,
              host: hostFlat,
              port: (portFlat as num).toInt());
        }

        // vnext (VMess / VLESS with vnext wrapper)
        final vnext = settings['vnext'];
        if (vnext is List && vnext.isNotEmpty) {
          final server = vnext.first;
          if (server is Map<String, dynamic>) {
            final host = server['address'] as String?;
            final port = server['port'];
            if (host != null && host.isNotEmpty && port != null) {
              return _NodeEndpoint(
                  index: index, host: host, port: (port as num).toInt());
            }
          }
        }
        // servers (Shadowsocks / Trojan / HTTP)
        final servers = settings['servers'];
        if (servers is List && servers.isNotEmpty) {
          final server = servers.first;
          if (server is Map<String, dynamic>) {
            final host = server['address'] as String?;
            final port = server['port'];
            if (host != null && host.isNotEmpty && port != null) {
              return _NodeEndpoint(
                  index: index, host: host, port: (port as num).toInt());
            }
          }
        }
      }
    }
  }

  // ── 3: top-level "address" / "port" (rare Xray shorthand) ─────────────────
  final host3 = node['address'] as String?;
  final port3 = node['port'];
  if (host3 != null && host3.isNotEmpty && port3 != null) {
    return _NodeEndpoint(
        index: index, host: host3, port: (port3 as num).toInt());
  }

  // ── 4: flat Shadowsocks-style keys ─────────────────────────────────────────
  // { "server": "...", "server_port": 443, ... }
  final host4 = node['server'] as String?;
  final port4 = node['server_port'];
  if (host4 != null && host4.isNotEmpty && port4 != null) {
    return _NodeEndpoint(
        index: index, host: host4, port: (port4 as num).toInt());
  }

  // ── 5: "add" / "port" (V2RayN flat export schema) ─────────────────────────
  // { "add": "host.example.com", "port": "443", ... }
  final host5 = node['add'] as String?;
  final port5raw = node['port']?.toString();
  final port5 = port5raw != null ? int.tryParse(port5raw) : null;
  if (host5 != null && host5.isNotEmpty && port5 != null) {
    return _NodeEndpoint(index: index, host: host5, port: port5);
  }

  // ── 6: "host" / "port" flat keys ───────────────────────────────────────────
  final host6 = node['host'] as String?;
  final port6raw = node['port']?.toString();
  final port6 = port6raw != null ? int.tryParse(port6raw) : null;
  if (host6 != null && host6.isNotEmpty && port6 != null) {
    return _NodeEndpoint(index: index, host: host6, port: port6);
  }

  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public LatencyTester class
// ─────────────────────────────────────────────────────────────────────────────

/// Concurrently measures TCP-handshake latency for every node in [nodes] using
/// a dedicated background [Isolate].  Calls [onBestNodeFound] immediately with
/// the lowest-latency node, then repeats every 5 minutes.
///
/// If the currently connected node is passed via [currentNodeGetter], a silent
/// switch is only triggered when a better node's latency is at least
/// [improvementThresholdMs] ms lower than the current node's latency.
class LatencyTester {
  static const Duration _interval = Duration(minutes: 5);
  static const int _timeoutMs = 3000;
  static const int improvementThresholdMs = 150;

  Timer? _timer;
  bool _running = false;

  /// Start background latency testing.
  ///
  /// [nodes]           – subscription node list (List of Map&lt;String,dynamic&gt;)
  /// [probeUrl]        – used only for DNS resolution check (unused in TCP path)
  /// [onBestNodeFound] – called with the best [NodeLatencyResult] each round
  /// [currentNodeGetter] – optional; returns the currently active node so we
  ///                       can apply the improvement threshold
  void start({
    required List<dynamic> nodes,
    String probeUrl = '',
    required void Function(NodeLatencyResult best) onBestNodeFound,
    dynamic Function()? currentNodeGetter,
  }) {
    stop();
    _running = true;

    Future<void> runRound() async {
      if (!_running) return;
      final result = await _measureAll(nodes);
      if (!_running || result == null) return;

      final current = currentNodeGetter?.call();
      if (current != null) {
        // Find current node's latency in this round
        final currentResult = result
            .where((r) => r.node == current && r.isReachable)
            .firstOrNull;
        if (currentResult != null &&
            result.first.isReachable &&
            (currentResult.latencyMs - result.first.latencyMs) <
                improvementThresholdMs) {
          // Current node is still good enough – don't switch
          return;
        }
      }

      if (result.first.isReachable) {
        onBestNodeFound(result.first);
      }
    }

    // Immediate first probe
    runRound();

    _timer = Timer.periodic(_interval, (_) => runRound());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// One-shot measurement without starting the periodic timer.
  Future<List<NodeLatencyResult>?> measureAll(List<dynamic> nodes) =>
      _measureAll(nodes);

  // ── Private ──────────────────────────────────────────────────────────────

  /// Spawns an isolate to probe all nodes concurrently.
  /// Returns nodes sorted by ascending latency (unreachable at the end).
  Future<List<NodeLatencyResult>?> _measureAll(List<dynamic> nodes) async {
    if (nodes.isEmpty) return null;

    // Build endpoint list, skipping nodes we can't parse.
    // Log the first node's schema to diagnose extraction failures.
    if (nodes.isNotEmpty) {
      try {
        final firstNode = nodes.first;
        if (firstNode is Map<String, dynamic>) {
          // Schema diagnosis logging removed for production
        }
      } catch (_) {}
    }

    final endpoints = <_NodeEndpoint>[];
    for (int i = 0; i < nodes.length; i++) {
      final ep = _extractEndpoint(i, nodes[i]);
      if (ep != null) endpoints.add(ep);
    }

    if (endpoints.isEmpty) {
      // Cannot parse any node — return -1 (unreachable) so the UI shows the
      // explicit failure state rather than interpreting 0 as "no measurement".
      return [NodeLatencyResult(node: nodes.first, latencyMs: -1)];
    }

    final receivePort = ReceivePort();
    Isolate? isolate;

    try {
      isolate = await Isolate.spawn(
        _probeIsolateEntry,
        _ProbeRequest(
          replyPort: receivePort.sendPort,
          endpoints: endpoints,
          timeoutMs: _timeoutMs,
        ),
      );

      final rawResults = await receivePort.first as List<_ProbeResult>;

      // Map back to nodes
      final results = rawResults.map((r) {
        return NodeLatencyResult(node: nodes[r.index], latencyMs: r.latencyMs);
      }).toList();

      // Sort: reachable nodes first by ascending ms, then unreachable
      results.sort((a, b) {
        if (a.isReachable && b.isReachable) {
          return a.latencyMs.compareTo(b.latencyMs);
        }
        if (a.isReachable) return -1;
        if (b.isReachable) return 1;
        return 0;
      });

      return results;
    } catch (e) {
      // Isolate spawn failure – fall back to first node as unreachable
      return [NodeLatencyResult(node: nodes.first, latencyMs: -1)];
    } finally {
      receivePort.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }
}
