import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Outcome of a matchmaking attempt — either we were paired with a waiting
/// stranger ([matched] true, [roomName] set), or we were enqueued and now
/// wait for someone else to pick us up.
class LiveMatch {
  const LiveMatch({required this.matched, this.roomName, this.peerId});

  final bool matched;
  final String? roomName;
  final String? peerId;

  /// True only when we have a usable room to jump into.
  bool get isMatched =>
      matched && roomName != null && roomName!.isNotEmpty;
}

/// Omegle-style live-call matchmaking over Supabase. See
/// `supabase/migrations/0015_live_lobby.sql` for the table + RPCs.
///
/// Flow:
///   1. [enqueue] — atomically pair with a waiting stranger, or join the
///      queue as 'waiting'.
///   2. While waiting: [subscribeMyRow] for the instant pairing happens,
///      plus [fetchMyRow] polling as a backstop, plus [heartbeat] so a
///      long wait doesn't age the row out of the match window.
///   3. [cancel] — leave the queue (back button / tab change / dispose).
abstract final class LiveLobbyApi {
  static SupabaseClient get _c => Supabase.instance.client;

  /// Tap "go live". Returns a [LiveMatch]: `matched` when a stranger was
  /// already waiting (jump straight into [LiveMatch.roomName]), otherwise
  /// the caller is now enqueued and should wait.
  static Future<LiveMatch> enqueue() async {
    if (!isSupabaseReady) {
      throw StateError('Supabase non configuré');
    }
    final res = await _c.rpc('enqueue_live_call');
    Map<String, dynamic>? row;
    if (res is List && res.isNotEmpty) {
      row = Map<String, dynamic>.from(res.first as Map);
    } else if (res is Map) {
      row = Map<String, dynamic>.from(res);
    }
    if (row == null) return const LiveMatch(matched: false);
    return LiveMatch(
      matched: row['matched'] == true,
      roomName: row['room_name']?.toString(),
      peerId: row['peer_id']?.toString(),
    );
  }

  /// Keep the caller's 'waiting' row fresh. Best-effort — call every ~30s
  /// while sitting on the search screen.
  static Future<void> heartbeat() async {
    if (!isSupabaseReady) return;
    try {
      await _c.rpc('live_lobby_heartbeat');
    } catch (e) {
      debugPrint('LiveLobbyApi.heartbeat failed: $e');
    }
  }

  /// How many other strangers are waiting right now. Drives the live
  /// counter on the idle screen. Returns 0 on any failure.
  static Future<int> waitingCount() async {
    if (!isSupabaseReady) return 0;
    try {
      final res = await _c.rpc('live_lobby_waiting_count');
      if (res is int) return res;
      if (res is num) return res.toInt();
      return int.tryParse(res?.toString() ?? '') ?? 0;
    } catch (e) {
      debugPrint('LiveLobbyApi.waitingCount failed: $e');
      return 0;
    }
  }

  /// Leave the queue. Idempotent — safe to call when not enqueued.
  static Future<void> cancel(String myId) async {
    if (!isSupabaseReady || myId.isEmpty) return;
    try {
      await _c.from('live_lobby').delete().eq('user_id', myId);
    } catch (e) {
      debugPrint('LiveLobbyApi.cancel failed: $e');
    }
  }

  /// One-shot read of the caller's own lobby row — polling backstop in
  /// case the realtime UPDATE is missed (websocket drop, tab throttling).
  static Future<LiveMatch?> fetchMyRow(String myId) async {
    if (!isSupabaseReady || myId.isEmpty) return null;
    try {
      final row = await _c
          .from('live_lobby')
          .select()
          .eq('user_id', myId)
          .maybeSingle();
      if (row == null) return null;
      final m = Map<String, dynamic>.from(row);
      return LiveMatch(
        matched: m['status']?.toString() == 'matched',
        roomName: m['room_name']?.toString(),
        peerId: m['peer_id']?.toString(),
      );
    } catch (e) {
      debugPrint('LiveLobbyApi.fetchMyRow failed: $e');
      return null;
    }
  }

  /// Subscribe to UPDATEs on the caller's own lobby row. [onUpdate] fires
  /// the instant the matchmaker flips the row to 'matched'. The returned
  /// channel must be removed when the listener tears down.
  static RealtimeChannel subscribeMyRow({
    required String myId,
    required void Function(LiveMatch) onUpdate,
  }) {
    final channel = _c.channel('live_lobby:$myId').onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'live_lobby',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: myId,
          ),
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            onUpdate(LiveMatch(
              matched: row['status']?.toString() == 'matched',
              roomName: row['room_name']?.toString(),
              peerId: row['peer_id']?.toString(),
            ));
          },
        );
    channel.subscribe();
    return channel;
  }
}
