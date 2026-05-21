import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import 'supabase_service.dart' show isSupabaseReady;

/// Client side of the analytics pipeline feeding the off-site admin
/// dashboard. Events are buffered in memory and flushed in batches to
/// `POST /api/events`, which validates them and inserts into
/// `public.analytics_events` (see backend/analytics.js + migration 0017).
///
/// Design rules:
///  * **Never throws, never blocks a real flow.** A failed flush just
///    keeps the events buffered for the next attempt; a misconfigured
///    backend URL makes every call a silent no-op.
///  * Each event carries the device-side timestamp (`ts`) — events can
///    sit buffered across an app backgrounding, so insert time would be
///    misleading. The backend trusts `ts` within a sane skew window.
///  * One [_sessionId] per app launch groups a session for retention /
///    recurring-user math on the dashboard.
abstract final class Analytics {
  /// Groups every event of one app launch. A v4 UUID — `Random.secure`
  /// is plenty since this is an analytics correlation id, not a secret.
  static final String _sessionId = _uuidV4();

  static final List<Map<String, dynamic>> _buffer = [];
  static bool _sending = false;
  static bool _started = false;

  /// Flush as soon as the buffer reaches this many events…
  static const int _flushAt = 12;
  /// …and on a timer regardless, so a quiet session still reports.
  static const Duration _flushInterval = Duration(seconds: 20);
  /// Hard cap so a long offline stretch can't grow the buffer forever —
  /// the oldest events are dropped past this.
  static const int _maxBuffer = 200;
  /// Largest batch sent in one POST (backend also caps at 50).
  static const int _maxBatchSend = 50;

  /// Idempotent. Starts the periodic flush timer and a lifecycle
  /// observer that flushes when the app is backgrounded (so a
  /// `call_ended` right before the user switches away is not lost).
  static void start() {
    if (_started) return;
    _started = true;
    // App-lifetime timer — never cancelled, so its handle is not stored.
    Timer.periodic(_flushInterval, (_) => unawaited(flush()));
    try {
      WidgetsBinding.instance.addObserver(_LifecycleFlusher());
    } catch (_) {
      // No binding (e.g. a unit test) — the timer-based flush still works.
    }
  }

  /// Record one event. Cheap and synchronous — it only appends to the
  /// in-memory buffer; the network happens later in [flush].
  static void track(
    String event, {
    Map<String, dynamic>? props,
    String? roomName,
    String? langFrom,
    String? langTo,
    int? latencyMs,
  }) {
    try {
      final e = <String, dynamic>{
        'event': event,
        'session_id': _sessionId,
        'ts': DateTime.now().toUtc().toIso8601String(),
      };
      if (roomName != null && roomName.isNotEmpty) e['room_name'] = roomName;
      if (langFrom != null && langFrom.isNotEmpty) e['lang_from'] = langFrom;
      if (langTo != null && langTo.isNotEmpty) e['lang_to'] = langTo;
      if (latencyMs != null) e['latency_ms'] = latencyMs;
      final country = _localeCountry();
      if (country != null) e['country'] = country;
      if (props != null && props.isNotEmpty) e['props'] = props;

      _buffer.add(e);
      if (_buffer.length > _maxBuffer) {
        _buffer.removeRange(0, _buffer.length - _maxBuffer);
      }
      if (_buffer.length >= _flushAt) {
        unawaited(flush());
      }
    } catch (_) {
      // Analytics must never break a caller — swallow everything.
    }
  }

  /// Send as many buffered events as fit in one batch. Events stay in
  /// the buffer until the POST is confirmed, so a transient network
  /// failure simply retries them next tick. Safe to call concurrently —
  /// overlapping calls short-circuit on [_sending].
  static Future<void> flush() async {
    if (_sending || _buffer.isEmpty) return;
    final uri = _eventsUri();
    if (uri == null) return; // backend URL not resolvable → no-op

    _sending = true;
    try {
      final batch = _buffer.take(_maxBatchSend).toList(growable: false);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final token = _accessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http
          .post(uri, headers: headers, body: jsonEncode({'events': batch}))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Remove exactly the events that were sent (by identity — each
        // map is a unique object), so events appended mid-flight stay.
        for (final e in batch) {
          _buffer.remove(e);
        }
      }
      // Non-2xx → leave the batch buffered; the next tick retries it.
    } catch (_) {
      // Network error / timeout — keep everything buffered.
    } finally {
      _sending = false;
    }
  }

  /// Supabase access token of the signed-in user, or null for guests /
  /// when Supabase was not configured at build time. The backend
  /// attributes the batch to that user; null → events stay anonymous.
  static String? _accessToken() {
    if (!isSupabaseReady) return null;
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// ISO-3166 alpha-2 region of the device locale, upper-cased. A weak
  /// signal (it is the UI region, not the network country) — the
  /// backend overrides it with a CDN geo header when one is present.
  static String? _localeCountry() {
    try {
      final c = PlatformDispatcher.instance.locale.countryCode;
      if (c != null && RegExp(r'^[A-Za-z]{2}$').hasMatch(c)) {
        return c.toUpperCase();
      }
    } catch (_) {}
    return null;
  }

  /// Resolve `<backend>/api/events` the same way [fetchLiveKitToken]
  /// resolves its endpoint: build-time `TOKEN_API_BASE`, else same
  /// origin on web, else the platform default. Null when unresolvable.
  static Uri? _eventsUri() {
    const fromEnv = String.fromEnvironment('TOKEN_API_BASE');
    if (fromEnv.isNotEmpty) {
      final b = fromEnv.replaceAll(RegExp(r'/$'), '');
      return Uri.parse('$b/api/events');
    }
    if (kIsWeb) {
      final o = Uri.base.removeFragment();
      return Uri(
        scheme: o.scheme,
        host: o.host,
        port: o.hasPort ? o.port : null,
        path: '/api/events',
      );
    }
    final b = resolvedTokenApiBase().replaceAll(RegExp(r'/$'), '');
    if (b.isEmpty) return null;
    return Uri.parse('$b/api/events');
  }
}

/// Flushes the buffer when the app leaves the foreground.
class _LifecycleFlusher with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(Analytics.flush());
    }
  }
}

/// Minimal RFC-4122 v4 UUID. Not security-sensitive — only used to
/// correlate one app launch's events on the dashboard.
String _uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 1
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
      '-${h.substring(16, 20)}-${h.substring(20)}';
}
