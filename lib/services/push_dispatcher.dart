import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Tiny client for the backend's `POST /api/notify` route. Used by
/// every event site that should wake up the other party: incoming
/// call, new chat message, new friend request, new like.
///
/// Always fire-and-forget — the underlying user action (insert the
/// message / friendship / etc.) must never depend on the notification
/// going through. Failures are logged and swallowed.
abstract final class PushDispatcher {
  /// Build the `/api/notify` URI. On web with no explicit TOKEN_API_BASE
  /// we hit our own origin (Docker-deployed backend sits in front of the
  /// Flutter web bundle on the same host); otherwise fall back to the
  /// configured base. Mirrors the resolver in `token_api.dart`.
  static Uri _notifyUri() {
    const fromEnv = String.fromEnvironment('TOKEN_API_BASE');
    if (fromEnv.isNotEmpty) {
      final b = fromEnv.replaceAll(RegExp(r'/$'), '');
      return Uri.parse('$b/api/notify');
    }
    if (kIsWeb) {
      final o = Uri.base.removeFragment();
      return Uri(
        scheme: o.scheme,
        host: o.host,
        port: o.hasPort ? o.port : null,
        path: '/api/notify',
      );
    }
    final b = resolvedTokenApiBase().replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$b/api/notify');
  }

  static Future<void> notify({
    required String recipientUid,
    required String title,
    String? body,
    String? type,
    Map<String, dynamic>? data,
  }) async {
    if (recipientUid.isEmpty || title.isEmpty) return;
    try {
      final uri = _notifyUri();
      await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'recipientUid': recipientUid,
              'title': title,
              if (body != null) 'body': body,
              if (type != null) 'type': type,
              if (data != null) 'data': data,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('PushDispatcher.notify failed: $e');
    }
  }
}
