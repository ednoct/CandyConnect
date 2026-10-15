import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

import '../core/xray_bridge.dart';
import 'dns_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result type returned by the optimizer
// ─────────────────────────────────────────────────────────────────────────────

/// The winning combination of node + DNS architecture selected by the
/// [ConnectionOptimizer]'s real-delay HTTP benchmark.
class OptimizedResult {
  /// The subscription node that won the benchmark.
  final Map<String, dynamic> node;

  /// The Bootstrap DNS IP (to be routed *direct* / outside the proxy),
  /// chosen by [DnsManager.raceBestBootstrap].
  final String bootstrapDns;

  /// The Remote DNS IP (to be routed *through* the proxy), chosen as
  /// part of the variant that produced the fastest HTTP response.
  final String remoteDns;

  /// Elapsed milliseconds for the winning HTTP GET through the proxy.
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

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark Isolate entry-point  (MUST be a top-level function)
// ─────────────────────────────────────────────────────────────────────────────

/// Entry-point for the short-lived benchmark Xray isolate.
///
/// The `runXray` CGo call is **blocking** — it runs the full Xray event loop
/// until `stopXray` is invoked from another context (main isolate) or the
/// isolate is killed.  Running it here keeps the main/UI thread completely
/// free during the benchmark.
///
/// Receives: `[SendPort replyPort, String configFilePath]`
void _benchmarkIsolateEntry(List<dynamic> args) {
  final sendPort = args[0] as SendPort;
  final configPath = args[1] as String;

  try {
    // XrayBridge re-initialises its static state within this isolate
    // (each isolate has its own heap). The underlying Go DLL and its state
    // are process-global, so this call drives the same singleton Xray engine.
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

// ─────────────────────────────────────────────────────────────────────────────
// ConnectionOptimizer
// ─────────────────────────────────────────────────────────────────────────────

/// Performs real-delay (HTTP Proxy Head Ping) benchmarking of [NodeVariant]s.
///
/// ### Mechanism
/// 1. Builds a **single** temporary Xray JSON config containing:
///    - One HTTP inbound per variant (on ports [_benchBasePort] + i)
///    - One proxy outbound per variant (cloned from the node's outbound block)
///    - Routing: `bench-in-i → bench-out-i`
/// 2. Spins this config up inside a **dedicated Dart Isolate**.
///    The `runXray` call blocks that isolate's thread — the main isolate
///    is never stalled.
/// 3. Fires concurrent `HttpClient` GET requests to [probeUrl] through each
///    variant's HTTP proxy port using `HttpClient.findProxy`.
/// 4. The first variant returning an HTTP 2xx wins.
/// 5. Sends `stopXray` to the Go DLL, then kills the isolate cleanly.
///
/// ### Cancellation
/// Call [cancel] at any time (e.g. user taps Disconnect). The `_cancelled`
/// flag is set synchronously, so probes that have not yet fired are skipped
/// immediately. The benchmark Xray is stopped async in the background.
class ConnectionOptimizer {
  // ── Configuration constants ───────────────────────────────────────────────

  /// Base local port for benchmark HTTP inbounds.  Variants occupy a contiguous
  /// range: [_benchBasePort, _benchBasePort + concurrency − 1].
  static const int _benchBasePort = 12100;

  /// Seconds to wait after spawning the Xray isolate before firing probes.
  /// Xray needs a moment to bind its listeners.
  static const Duration _xrayWarmup = Duration(milliseconds: 1500);

  /// Total HTTP probe timeout per variant, in milliseconds.
  static const int _probeTimeoutMs = 6000;

  // ── Internal state ────────────────────────────────────────────────────────

  Isolate? _benchmarkIsolate;
  ReceivePort? _benchmarkPort;
  File? _configFile;
  bool _cancelled = false;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Resets the cancellation flag so this instance can be reused after [cancel].
  void reset() => _cancelled = false;

  /// Finds the best [NodeVariant] via real HTTP delay through a temporary
  /// Xray proxy instance.
  ///
  /// Returns `null` if:
  ///   - [variants] is empty
  ///   - No variant responds successfully within the timeout
  ///   - [cancel] was called before the result arrived
  ///
  /// The [probeUrl] should be a lightweight endpoint that returns HTTP 2xx
  /// quickly (e.g. `https://cp.cloudflare.com/generate_204`).
  Future<OptimizedResult?> findBest({
    required List<NodeVariant> variants,
    required String bootstrapDns,
    required String probeUrl,
    int concurrency = 5,
  }) async {
    if (variants.isEmpty || _cancelled) return null;

    // Cap concurrency to avoid opening too many ephemeral ports
    final limited = variants.take(concurrency).toList();
    debugPrint(
      '[ConnectionOptimizer] Starting real-delay benchmark: '
      '${limited.length} variants, probe: $probeUrl',
    );

    // ── Step 1: Build the multi-outbound benchmark Xray config ───────────
    final config = _buildBenchmarkConfig(limited, _benchBasePort);
    if (config == null) {
      debugPrint('[ConnectionOptimizer] No parseable proxy outbounds found — '
          'skipping real-delay phase.');
      return null;
    }

    // ── Step 2: Persist config to a temp file ────────────────────────────
    _configFile = await _writeTempConfig(config);
    if (_configFile == null || _cancelled) {
      _cleanup();
      return null;
    }
    debugPrint(
        '[ConnectionOptimizer] Benchmark config written: ${_configFile!.path}');

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
      debugPrint('[ConnectionOptimizer] Cancelled during warmup.');
      await _stopBenchmarkCore();
      _cleanup();
      return null;
    }

    // ── Step 5: Race concurrent HTTP probes ──────────────────────────────
    OptimizedResult? winner;
    try {
      winner = await _raceProbeFutures(
        limited, bootstrapDns, probeUrl, _benchBasePort,
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

  /// Aborts any in-progress benchmark.
  ///
  /// Sets [_cancelled] synchronously (so in-flight probes skip immediately),
  /// then tears down the benchmark Xray + isolate in the background.
  /// This method itself is async but callers **do not need to await** it;
  /// they may call it fire-and-forget during a disconnect sequence.
  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    debugPrint('[ConnectionOptimizer] cancel() invoked.');
    await _stopBenchmarkCore();
    _cleanup();
  }

  // ── Private: Config Building ──────────────────────────────────────────────

  /// Builds a single temporary Xray config with N HTTP inbounds and N
  /// proxy outbounds — one for each variant.  Returns `null` if no valid
  /// proxy outbounds could be extracted from any node.
  Map<String, dynamic>? _buildBenchmarkConfig(
    List<NodeVariant> variants,
    int basePort,
  ) {
    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];

    for (int i = 0; i < variants.length; i++) {
      final variant = variants[i];
      final outboundTag = 'bench-out-$i';
      final inboundTag = 'bench-in-$i';
      final port = basePort + i;

      // Extract and retag the node's proxy outbound
      final proxyOutbound =
          _extractProxyOutbound(variant.node, outboundTag);
      if (proxyOutbound == null) {
        debugPrint(
            '[ConnectionOptimizer] Variant $i: could not extract proxy '
            'outbound — skipping.');
        continue;
      }

      outbounds.add(proxyOutbound);

      // HTTP inbound on a unique loopback port
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

      // Strict 1-to-1 routing: this inbound → this outbound only
      rules.add({
        'type': 'field',
        'inboundTag': [inboundTag],
        'outboundTag': outboundTag,
      });
    }

    if (outbounds.isEmpty) return null;

    // Mandatory fallback outbounds required by Xray's routing engine
    outbounds.addAll([
      {'tag': 'direct', 'protocol': 'freedom', 'settings': {}},
      {'tag': 'block', 'protocol': 'blackhole', 'settings': {}},
    ]);

    return {
      'log': {'loglevel': 'none'},
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': rules,
      },
    };
  }

  /// Clones the first non-direct / non-block outbound from [node], applying
  /// [newTag].  Returns `null` if no suitable outbound is found.
  Map<String, dynamic>? _extractProxyOutbound(
    Map<String, dynamic> node,
    String newTag,
  ) {
    final rawOutbounds = node['outbounds'];
    if (rawOutbounds is! List) return null;

    for (final ob in rawOutbounds) {
      if (ob is! Map) continue;
      final obMap = Map<String, dynamic>.from(ob);
      final tag = (obMap['tag'] as String? ?? '').toLowerCase();
      // Skip special system outbounds
      if (tag == 'direct' || tag == 'block' || tag == 'dns-out') continue;

      // Retag and return the cloned outbound
      obMap['tag'] = newTag;
      return obMap;
    }
    return null;
  }

  /// Writes [config] to a uniquely-named temp file.  Returns `null` on error.
  Future<File?> _writeTempConfig(Map<String, dynamic> config) async {
    try {
      final tempDir = Directory.systemTemp;
      final file = File(
        '${tempDir.path}/cc_bench_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonEncode(config));
      return file;
    } catch (e) {
      debugPrint('[ConnectionOptimizer] Failed to write temp config: $e');
      return null;
    }
  }

  // ── Private: Probing ──────────────────────────────────────────────────────

  /// Fires all variant probes concurrently and resolves with the first 2xx
  /// winner, or `null` if all fail or the overall timeout elapses.
  Future<OptimizedResult?> _raceProbeFutures(
    List<NodeVariant> variants,
    String bootstrapDns,
    String probeUrl,
    int basePort,
  ) {
    // A Completer lets the first success signal all others to stand down.
    final completer = Completer<OptimizedResult?>();
    int remaining = variants.length;

    void onProbeResult(OptimizedResult? result) {
      if (completer.isCompleted) return;
      remaining--;
      if (result != null) {
        // First winner
        completer.complete(result);
      } else if (remaining <= 0) {
        // All probes failed
        completer.complete(null);
      }
    }

    for (int i = 0; i < variants.length; i++) {
      if (_cancelled) {
        onProbeResult(null);
        continue;
      }
      final variant = variants[i];
      final port = basePort + i;
      _probeVariant(variant, bootstrapDns, port, probeUrl)
          .then(onProbeResult);
    }

    // Outer timeout slightly longer than per-probe to catch stragglers
    return completer.future.timeout(
      const Duration(milliseconds: _probeTimeoutMs + 1000),
      onTimeout: () => null,
    );
  }

  /// Issues an HTTP GET to [probeUrl] through the HTTP proxy on [proxyPort].
  ///
  /// Uses `HttpClient.findProxy` which sends an HTTP `CONNECT` tunnel for
  /// HTTPS targets — fully supported by Xray's `http` protocol inbound.
  /// Certificate verification is disabled since we only care about
  /// reachability timing, not content authenticity.
  ///
  /// Returns an [OptimizedResult] on HTTP 2xx, or `null` on failure.
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

      // Route through this variant's dedicated benchmark HTTP inbound
      client.findProxy = (uri) => 'PROXY 127.0.0.1:$proxyPort';

      // Bypass TLS certificate verification — we are measuring speed, not
      // validating server identity during the benchmark pass.
      client.badCertificateCallback = (cert, host, port) => true;

      final request = await client
          .getUrl(Uri.parse(probeUrl))
          .timeout(Duration(milliseconds: _probeTimeoutMs));
      request.headers
        ..set('User-Agent', 'CandyConnect/Optimizer 1.0')
        ..set('Connection', 'close');

      final response = await request
          .close()
          .timeout(Duration(milliseconds: _probeTimeoutMs));

      sw.stop();
      // Drain body to free the connection
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
      debugPrint(
          '[ConnectionOptimizer] Port $proxyPort probe failed: $e');
      return null;
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }

  // ── Private: Teardown ─────────────────────────────────────────────────────

  /// Signals the Go DLL to stop the benchmark Xray event loop.
  ///
  /// Because [_benchmarkIsolateEntry] blocks on `runXray`, invoking `stopXray`
  /// from *this* isolate (via the same DLL) unblocks it.  This is safe because
  /// the Go runtime manages its own synchronisation internally.
  Future<void> _stopBenchmarkCore() async {
    try {
      XrayBridge.invoke(jsonEncode({
        'apiVersion': 1,
        'method': 'stopXray',
        'payload': {},
      }));
      debugPrint('[ConnectionOptimizer] stopXray sent to benchmark core.');
    } catch (e) {
      debugPrint('[ConnectionOptimizer] stopXray error: $e');
    }
    // Allow Xray's goroutines to finish tearing down before we kill the isolate
    await Future.delayed(const Duration(milliseconds: 300));
  }

  /// Kills the benchmark isolate and frees all associated resources.
  void _cleanup() {
    _benchmarkIsolate?.kill(priority: Isolate.immediate);
    _benchmarkIsolate = null;
    _benchmarkPort?.close();
    _benchmarkPort = null;
    try {
      _configFile?.deleteSync();
    } catch (_) {}
    _configFile = null;
  }
}
