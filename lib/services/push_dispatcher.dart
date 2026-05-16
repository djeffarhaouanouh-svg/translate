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
  static Future<void> notify({
    required String recipientUid,
    required String title,
    String? body,
    String? type,
    Map<String, dynamic>? data,
  }) async {
    if (recipientUid.isEmpty || title.isEmpty) return;
    final base = resolvedTokenApiBase();
    if (base.isEmpty) return;
    try {
      final uri = Uri.parse('$base/api/notify');
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
