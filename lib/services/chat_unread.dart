import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Tracks the count of unread messages addressed to the local user, so the
/// Chat tab can show a badge. The "seen" point is one timestamp stored in
/// SharedPreferences — opening the Chat list marks everything older as seen.
abstract final class ChatUnread {
  static final ValueNotifier<int> count = ValueNotifier<int>(0);

  static const _seenKey = 'chat_last_seen_iso';
  static StreamSubscription<List<Map<String, dynamic>>>? _sub;
  static String _meId = '';
  static String _lastSeenIso = '';

  /// Start watching the messages table for [meId]. Safe to call repeatedly;
  /// re-subscribes if the id changed.
  static Future<void> start(String meId) async {
    if (meId.isEmpty || !isSupabaseReady) return;
    if (meId == _meId && _sub != null) return;
    _meId = meId;

    final prefs = await SharedPreferences.getInstance();
    _lastSeenIso = prefs.getString(_seenKey) ??
        DateTime.now().toUtc().toIso8601String();

    await _sub?.cancel();
    _sub = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('recipient', meId)
        .listen(
          _onRows,
          onError: (e) =>
              debugPrint('ChatUnread stream error: $e'),
        );
  }

  static void _onRows(List<Map<String, dynamic>> rows) {
    var n = 0;
    for (final r in rows) {
      final ts = r['created_at']?.toString() ?? '';
      if (ts.isNotEmpty && ts.compareTo(_lastSeenIso) > 0) {
        n++;
      }
    }
    if (count.value != n) count.value = n;
  }

  /// Call when the user opens the Chat tab — moves the seen pointer to now
  /// and resets the badge.
  static Future<void> markAllSeen() async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    _lastSeenIso = nowIso;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seenKey, nowIso);
    count.value = 0;
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _meId = '';
    count.value = 0;
  }
}
