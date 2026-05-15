import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// One pending incoming call as seen by the callee. The room name is what
/// the callee should connect to via LiveKit if they accept.
class IncomingCall {
  const IncomingCall({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.roomName,
    required this.createdAt,
  });

  final String id;
  final String callerId;
  final String calleeId;
  final String roomName;
  final DateTime createdAt;

  factory IncomingCall.fromMap(Map<String, dynamic> m) => IncomingCall(
        id: m['id']?.toString() ?? '',
        callerId: m['caller']?.toString() ?? '',
        calleeId: m['callee']?.toString() ?? '',
        roomName: m['room_name']?.toString() ?? '',
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '')
                ?.toLocal() ??
            DateTime.now(),
      );
}

/// Realtime ring/answer over Supabase. Schema:
///
/// ```sql
/// create table incoming_calls (
///   id uuid primary key default gen_random_uuid(),
///   caller uuid not null references auth.users(id) on delete cascade,
///   callee uuid not null references auth.users(id) on delete cascade,
///   room_name text not null,
///   created_at timestamptz not null default now()
/// );
/// alter table incoming_calls enable row level security;
/// alter publication supabase_realtime add table incoming_calls;
///
/// create policy "callee can see their own incoming calls"
///   on incoming_calls for select using (auth.uid() = callee);
/// create policy "caller can insert their own outgoing calls"
///   on incoming_calls for insert with check (auth.uid() = caller);
/// create policy "caller or callee can delete"
///   on incoming_calls for delete using (
///     auth.uid() = caller or auth.uid() = callee
///   );
/// ```
abstract final class IncomingCallApi {
  static SupabaseClient get _c => Supabase.instance.client;

  /// Inserts a fresh "ringing" row addressed to [calleeId]. The callee's
  /// realtime subscription will pick it up and show the incoming-call
  /// modal. Returns the inserted row id (caller keeps it so they can
  /// delete the row when they hang up before the callee accepts).
  static Future<String?> ring({
    required String callerId,
    required String calleeId,
    required String roomName,
  }) async {
    if (!isSupabaseReady) return null;
    if (callerId.isEmpty || calleeId.isEmpty || callerId == calleeId) {
      return null;
    }
    try {
      final inserted = await _c
          .from('incoming_calls')
          .insert({
            'caller': callerId,
            'callee': calleeId,
            'room_name': roomName,
          })
          .select('id')
          .single();
      final id = Map<String, dynamic>.from(inserted)['id']?.toString();
      debugPrint('[ring] inserted incoming_call id=$id callee=$calleeId');
      return id;
    } catch (e) {
      debugPrint('[ring] FAILED: $e');
      return null;
    }
  }

  /// Removes a ringing row. Both caller (cancel before pickup) and callee
  /// (decline / accept) are allowed by the RLS policy.
  static Future<void> cancel({required String callId}) async {
    if (!isSupabaseReady || callId.isEmpty) return;
    try {
      await _c.from('incoming_calls').delete().eq('id', callId);
    } catch (e) {
      debugPrint('IncomingCallApi.cancel failed: $e');
    }
  }

  /// Subscribe to incoming-call rows for [calleeId]. The returned channel
  /// must be `unsubscribe()`d when the listener tears down (e.g. on sign
  /// out). [onCall] fires for every fresh INSERT.
  static RealtimeChannel subscribe({
    required String calleeId,
    required void Function(IncomingCall) onCall,
  }) {
    debugPrint('[ring] subscribing as callee=$calleeId');
    final channel = _c.channel('incoming_calls:$calleeId').onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'incoming_calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'callee',
            value: calleeId,
          ),
          callback: (payload) {
            debugPrint('[ring] received realtime insert: ${payload.newRecord}');
            final row = payload.newRecord;
            onCall(IncomingCall.fromMap(Map<String, dynamic>.from(row)));
          },
        );
    channel.subscribe((status, error) {
      debugPrint('[ring] channel status=$status err=$error');
    });
    return channel;
  }
}
