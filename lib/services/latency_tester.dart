import 'dart:async';
import 'dart:io';
import 'dart:isolate';

class NodeLatencyResult {
  final dynamic node;
  final int latencyMs;

  const NodeLatencyResult({required this.node, required this.latencyMs});

  bool get isReachable => latencyMs >= 0;
}

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
  final int index;
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
  final int latencyMs;

  const _ProbeResult({required this.index, required this.latencyMs});
}

// ignore: library_private_types_in_public_api
void _probeIsolateEntry(_ProbeRequest req) async {
  final futures = req.endpoints.map((ep) => _probeOne(ep, req.timeoutMs));
  final results = await Future.wait(futures, eagerError: false);
  req.replyPort.send(results);
}

Future<_ProbeResult> _probeOne(_NodeEndpoint ep, int timeoutMs) async {
  final sw = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await Socket.connect(
      ep.host,
      ep.port,
      timeout: Duration(milliseconds: timeoutMs),
    );
    sw.stop();
    return _ProbeResult(index: ep.index, latencyMs: sw.elapsedMilliseconds);
  } catch (_) {
    sw.stop();
    return _ProbeResult(index: ep.index, latencyMs: -1);
  } finally {
    try {
      socket?.destroy();
    } catch (_) {}
  }
}

/// تبدیل ایمن پورت از هر نوع داده (int, double, String) بدون پرتاب TypeError
int? _parsePort(dynamic rawPort) {
  if (rawPort is int) return (rawPort > 0 && rawPort <= 65535) ? rawPort : null;
  if (rawPort is num) {
    final p = rawPort.toInt();
    return (p > 0 && p <= 65535) ? p : null;
  }
  if (rawPort is String) {
    final p = int.tryParse(rawPort.trim());
    if (p != null && p > 0 && p <= 65535) return p;
  }
  return null;
}

_NodeEndpoint? _extractEndpoint(int index, dynamic node) {
  if (node is! Map) return null;

  // ── 1 & 2: standard Xray outbounds ────────────────────────────────────────
  final outbounds = node['outbounds'];
  if (outbounds is List && outbounds.isNotEmpty) {
    for (final ob in outbounds) {
      if (ob is! Map) continue;
      final tag = (ob['tag']?.toString() ?? '').toLowerCase();
      if (tag == 'direct' || tag == 'block' || tag == 'dns-out') continue;

      final settings = ob['settings'];
      if (settings is Map) {
        // Flat VLESS / Reality schema
        final hostFlat = settings['address']?.toString().trim();
        final portFlat = _parsePort(settings['port']);
        if (hostFlat != null && hostFlat.isNotEmpty && portFlat != null) {
          return _NodeEndpoint(index: index, host: hostFlat, port: portFlat);
        }

        // vnext (VMess / VLESS)
        final vnext = settings['vnext'];
        if (vnext is List && vnext.isNotEmpty) {
          final server = vnext.first;
          if (server is Map) {
            final host = server['address']?.toString().trim();
            final port = _parsePort(server['port']);
            if (host != null && host.isNotEmpty && port != null) {
              return _NodeEndpoint(index: index, host: host, port: port);
            }
          }
        }

        // servers (Shadowsocks / Trojan / Socks / HTTP)
        final servers = settings['servers'];
        if (servers is List && servers.isNotEmpty) {
          final server = servers.first;
          if (server is Map) {
            final host = server['address']?.toString().trim();
            final port = _parsePort(server['port']);
            if (host != null && host.isNotEmpty && port != null) {
              return _NodeEndpoint(index: index, host: host, port: port);
            }
          }
        }

        // peers (WireGuard outbound)
        final peers = settings['peers'];
        if (peers is List && peers.isNotEmpty) {
          final peer = peers.first;
          if (peer is Map) {
            final endpointStr = peer['endpoint']?.toString().trim() ?? '';
            final lastColon = endpointStr.lastIndexOf(':');
            if (lastColon > 0) {
              final host = endpointStr
                  .substring(0, lastColon)
                  .replaceAll('[', '')
                  .replaceAll(']', '');
              final port = _parsePort(endpointStr.substring(lastColon + 1));
              if (host.isNotEmpty && port != null) {
                return _NodeEndpoint(index: index, host: host, port: port);
              }
            }
          }
        }
      }
    }
  }

  // ── 3: top-level "address" / "port" ───────────────────────────────────────
  final host3 = node['address']?.toString().trim();
  final port3 = _parsePort(node['port']);
  if (host3 != null && host3.isNotEmpty && port3 != null) {
    return _NodeEndpoint(index: index, host: host3, port: port3);
  }

  // ── 4: flat Shadowsocks-style keys ("server" / "server_port") ─────────────
  final host4 = node['server']?.toString().trim();
  final port4 = _parsePort(node['server_port']);
  if (host4 != null && host4.isNotEmpty && port4 != null) {
    return _NodeEndpoint(index: index, host: host4, port: port4);
  }

  // ── 5: V2RayN flat export schema ("add" / "port") ─────────────────────────
  final host5 = node['add']?.toString().trim();
  final port5 = _parsePort(node['port']);
  if (host5 != null && host5.isNotEmpty && port5 != null) {
    return _NodeEndpoint(index: index, host: host5, port: port5);
  }

  // ── 6: "host" / "port" flat keys ──────────────────────────────────────────
  final host6 = node['host']?.toString().trim();
  final port6 = _parsePort(node['port']);
  if (host6 != null && host6.isNotEmpty && port6 != null) {
    return _NodeEndpoint(index: index, host: host6, port: port6);
  }

  return null;
}

class LatencyTester {
  static const Duration _interval = Duration(minutes: 5);
  static const int _timeoutMs = 3000;
  static const int improvementThresholdMs = 150;

  Timer? _timer;
  bool _running = false;
  bool _roundInProgress = false;

  void start({
    required List<dynamic> nodes,
    String probeUrl = '',
    required void Function(NodeLatencyResult best) onBestNodeFound,
    dynamic Function()? currentNodeGetter,
  }) {
    stop();
    _running = true;

    Future<void> runRound() async {
      if (!_running || _roundInProgress) return;
      _roundInProgress = true;

      try {
        final result = await _measureAll(nodes);
        if (!_running || result == null || result.isEmpty) return;

        final current = currentNodeGetter?.call();
        if (current != null) {
          final currentResult = result
              .where((r) => r.node == current && r.isReachable)
              .firstOrNull;
          if (currentResult != null &&
              result.first.isReachable &&
              (currentResult.latencyMs - result.first.latencyMs) <
                  improvementThresholdMs) {
            return;
          }
        }

        if (result.first.isReachable) {
          onBestNodeFound(result.first);
        }
      } finally {
        _roundInProgress = false;
      }
    }

    runRound();
    _timer = Timer.periodic(_interval, (_) => runRound());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<List<NodeLatencyResult>?> measureAll(List<dynamic> nodes) =>
      _measureAll(nodes);

  Future<List<NodeLatencyResult>?> _measureAll(List<dynamic> nodes) async {
    if (nodes.isEmpty) return null;

    final endpoints = <_NodeEndpoint>[];
    for (int i = 0; i < nodes.length; i++) {
      final ep = _extractEndpoint(i, nodes[i]);
      if (ep != null) endpoints.add(ep);
    }

    if (endpoints.isEmpty) {
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
        errorsAreFatal: false,
      );

      final rawResults = await receivePort.first
          .timeout(const Duration(milliseconds: _timeoutMs + 1500))
          as List<_ProbeResult>;

      final results = rawResults.map((r) {
        return NodeLatencyResult(node: nodes[r.index], latencyMs: r.latencyMs);
      }).toList();

      // اضافه کردن نودهایی که احیاناً قابل پارس نبودند به انتهای لیست با پینگ -1
      if (results.length < nodes.length) {
        final probedIndices = rawResults.map((r) => r.index).toSet();
        for (int i = 0; i < nodes.length; i++) {
          if (!probedIndices.contains(i)) {
            results.add(NodeLatencyResult(node: nodes[i], latencyMs: -1));
          }
        }
      }

      results.sort((a, b) {
        if (a.isReachable && b.isReachable) {
          return a.latencyMs.compareTo(b.latencyMs);
        }
        if (a.isReachable) return -1;
        if (b.isReachable) return 1;
        return 0;
      });

      return results;
    } catch (_) {
      return [NodeLatencyResult(node: nodes.first, latencyMs: -1)];
    } finally {
      receivePort.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }
}