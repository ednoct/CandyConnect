import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

import '../core/xray_bridge.dart';
import 'dns_manager.dart';

class OptimizedResult {
  final Map<String, dynamic> node;
  final String bootstrapDns;
  final String remoteDns;
  final int realDelayMs;

  const OptimizedResult({
    required this.node,
    required this.bootstrapDns,
    required this.remoteDns,
    required this.realDelayMs,
  });

  @override
  String toString() =>
      'OptimizedResult('
      'bootstrapDns: $bootstrapDns, '
      'remoteDns: $remoteDns, '
      'realDelayMs: ${realDelayMs}ms'
      ')';
}

class _BoundVariant {
  final NodeVariant variant;
  final int port;
  const _BoundVariant({required this.variant, required this.port});
}

void _benchmarkIsolateEntry(List<dynamic> args) {
  final sendPort = args[0] as SendPort;
  final configPath = args[1] as String;

  try {
    final result = XrayBridge.invoke(jsonEncode({
      'apiVersion': 1,
      'method': 'runXray',
      'payload': {'configPath': configPath},
    }));
    sendPort.send(result.isEmpty ? 'done' : result);
  } catch (e) {
    sendPort.send('error: $e');
  }
}

class ConnectionOptimizer {
  static const int _benchBasePort = 12100;
  static const Duration _xrayWarmup = Duration(milliseconds: 1200);
  static const int _probeTimeoutMs = 5500;

  Isolate? _benchmarkIsolate;
  ReceivePort? _benchmarkPort;
  File? _configFile;
  bool _cancelled = false;

  void reset() => _cancelled = false;

  Future<OptimizedResult?> findBest({
    required List<NodeVariant> variants,
    required String bootstrapDns,
    required String probeUrl,
    int concurrency = 5,
  }) async {
    if (variants.isEmpty || _cancelled) return null;

    final limited = variants.take(concurrency).toList();
    debugPrint(
      '[ConnectionOptimizer] Starting real-delay benchmark: '
      '${limited.length} variants, probe: $probeUrl',
    );

    // ── Step 1: Build the multi-outbound benchmark Xray config ───────────
    final buildResult =
        _buildBenchmarkConfig(limited, bootstrapDns, _benchBasePort);
    if (buildResult == null || buildResult.boundVariants.isEmpty) {
      debugPrint('[ConnectionOptimizer] No parseable proxy outbounds found — '
          'skipping real-delay phase.');
      return null;
    }

    // ── Step 2: Persist config to a temp file ────────────────────────────
    _configFile = await _writeTempConfig(buildResult.config);
    if (_configFile == null || _cancelled) {
      _cleanup();
      return null;
    }

    // ── Step 3: Spawn the blocking Xray isolate ──────────────────────────
    _benchmarkPort = ReceivePort();
    try {
      _benchmarkIsolate = await Isolate.spawn(
        _benchmarkIsolateEntry,
        [_benchmarkPort!.sendPort, _configFile!.path],
        errorsAreFatal: false,
      );
    } catch (e) {
      debugPrint(
          '[ConnectionOptimizer] Failed to spawn benchmark isolate: $e');
      _cleanup();
      return null;
    }

    // ── Step 4: Wait for Xray to bind its HTTP listeners ─────────────────
    await Future.delayed(_xrayWarmup);
    if (_cancelled) {
      await _stopBenchmarkCore();
      _cleanup();
      return null;
    }

    // ── Step 5: Race concurrent HTTP probes ──────────────────────────────
    OptimizedResult? winner;
    try {
      winner = await _raceProbeFutures(
        buildResult.boundVariants,
        bootstrapDns,
        probeUrl,
      );
    } catch (e) {
      debugPrint('[ConnectionOptimizer] Probe race threw: $e');
    }

    // ── Step 6: Tear down benchmark Xray and clean up ─────────────────────
    await _stopBenchmarkCore();
    _cleanup();

    if (winner != null) {
      debugPrint('[ConnectionOptimizer] ✓ Winner selected: $winner');
    } else {
      debugPrint(
          '[ConnectionOptimizer] No real-delay winner — '
          'caller will use TCP-ranked fallback.');
    }
    return winner;
  }

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    debugPrint('[ConnectionOptimizer] cancel() invoked.');
    await _stopBenchmarkCore();
    _cleanup();
  }

  // ── Private: Config Building ──────────────────────────────────────────────

  ({Map<String, dynamic> config, List<_BoundVariant> boundVariants})?
      _buildBenchmarkConfig(
    List<NodeVariant> variants,
    String bootstrapDns,
    int basePort,
  ) {
    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];
    final boundVariants = <_BoundVariant>[];
    final dnsServers = <dynamic>[bootstrapDns];

    for (int i = 0; i < variants.length; i++) {
      final variant = variants[i];
      final slotIdx = boundVariants.length;
      final outboundTag = 'bench-out-$slotIdx';
      final inboundTag = 'bench-in-$slotIdx';
      final port = basePort + slotIdx;

      final proxyOutbound =
          _extractProxyOutbound(variant.node, outboundTag);
      if (proxyOutbound == null) {
        continue;
      }

      if (!dnsServers.contains(variant.remoteDns)) {
        dnsServers.add(variant.remoteDns);
      }

      outbounds.add(proxyOutbound);
      boundVariants.add(_BoundVariant(variant: variant, port: port));

      inbounds.add({
        'tag': inboundTag,
        'protocol': 'http',
        'port': port,
        'listen': '127.0.0.1',
        'settings': {
          'allowTransparent': false,
          'timeout': 5,
        },
        'sniffing': {'enabled': false},
      });

      rules.add({
        'type': 'field',
        'inboundTag': [inboundTag],
        'outboundTag': outboundTag,
      });
    }

    if (outbounds.isEmpty) return null;

    // هدایت مستقیم ترافیک Bootstrap DNS تا دامنه‌های سرور پروکسی بدون حلقه، Resolve شوند
    rules.insert(0, {
      'type': 'field',
      'ip': ['$bootstrapDns/32'],
      'outboundTag': 'direct',
    });

    outbounds.addAll([
      {'tag': 'direct', 'protocol': 'freedom', 'settings': {}},
      {'tag': 'block', 'protocol': 'blackhole', 'settings': {}},
    ]);

    final config = <String, dynamic>{
      'log': {'loglevel': 'none'},
      'dns': {
        'servers': dnsServers,
      },
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'rules': rules,
      },
    };

    return (config: config, boundVariants: boundVariants);
  }

  Map<String, dynamic>? _extractProxyOutbound(
    Map<String, dynamic> node,
    String newTag,
  ) {
    final rawOutbounds = node['outbounds'];
    if (rawOutbounds is! List) return null;

    for (final ob in rawOutbounds) {
      if (ob is! Map) continue;
      final obMap = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(ob)) as Map,
      );
      final tag = (obMap['tag'] as String? ?? '').toLowerCase();
      if (tag == 'direct' || tag == 'block' || tag == 'dns-out') continue;

      obMap['tag'] = newTag;
      return obMap;
    }
    return null;
  }

  Future<File?> _writeTempConfig(Map<String, dynamic> config) async {
    try {
      final tempDir = Directory.systemTemp;
      final file = File(
        '${tempDir.path}/cc_bench_${DateTime.now().microsecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonEncode(config), flush: true);
      return file;
    } catch (e) {
      debugPrint('[ConnectionOptimizer] Failed to write temp config: $e');
      return null;
    }
  }

  // ── Private: Probing ──────────────────────────────────────────────────────

  Future<OptimizedResult?> _raceProbeFutures(
    List<_BoundVariant> boundVariants,
    String bootstrapDns,
    String probeUrl,
  ) {
    final completer = Completer<OptimizedResult?>();
    int remaining = boundVariants.length;

    void onProbeResult(OptimizedResult? result) {
      if (completer.isCompleted) return;
      remaining--;
      if (result != null) {
        completer.complete(result);
      } else if (remaining <= 0) {
        completer.complete(null);
      }
    }

    for (final bound in boundVariants) {
      if (_cancelled) {
        onProbeResult(null);
        continue;
      }
      _probeVariant(bound.variant, bootstrapDns, bound.port, probeUrl)
          .then(onProbeResult);
    }

    return completer.future.timeout(
      const Duration(milliseconds: _probeTimeoutMs + 1000),
      onTimeout: () => null,
    );
  }

  Future<OptimizedResult?> _probeVariant(
    NodeVariant variant,
    String bootstrapDns,
    int proxyPort,
    String probeUrl,
  ) async {
    if (_cancelled) return null;
    final sw = Stopwatch()..start();
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout =
          const Duration(milliseconds: _probeTimeoutMs);
      client.idleTimeout = const Duration(seconds: 2);
      client.findProxy = (uri) => 'PROXY 127.0.0.1:$proxyPort';
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client
          .getUrl(Uri.parse(probeUrl))
          .timeout(const Duration(milliseconds: _probeTimeoutMs));
      request.headers
        ..set('User-Agent', 'CandyConnect/Optimizer 1.0')
        ..set('Connection', 'close');

      final response = await request
          .close()
          .timeout(const Duration(milliseconds: _probeTimeoutMs));

      sw.stop();
      await response.drain<void>();

      if (_cancelled) return null;

      final statusOk =
          response.statusCode >= 200 && response.statusCode < 300;
      debugPrint(
        '[ConnectionOptimizer] Port $proxyPort '
        '(remoteDns: ${variant.remoteDns}): '
        'HTTP ${response.statusCode} in ${sw.elapsedMilliseconds}ms '
        '${statusOk ? "✓" : "✗"}',
      );

      if (!statusOk) return null;

      return OptimizedResult(
        node: variant.node,
        bootstrapDns: bootstrapDns,
        remoteDns: variant.remoteDns,
        realDelayMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return null;
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }

  // ── Private: Teardown ─────────────────────────────────────────────────────

  Future<void> _stopBenchmarkCore() async {
    if (_benchmarkIsolate == null) return;
    try {
      XrayBridge.invoke(jsonEncode({
        'apiVersion': 1,
        'method': 'stopXray',
        'payload': {},
      }));
    } catch (e) {
      debugPrint('[ConnectionOptimizer] stopXray error: $e');
    }
    await Future.delayed(const Duration(milliseconds: 250));
  }

  void _cleanup() {
    _benchmarkIsolate?.kill(priority: Isolate.immediate);
    _benchmarkIsolate = null;
    _benchmarkPort?.close();
    _benchmarkPort = null;
    try {
      if (_configFile != null && _configFile!.existsSync()) {
        _configFile!.deleteSync();
      }
    } catch (_) {}
    _configFile = null;
  }
}