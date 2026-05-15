import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_api.dart';
import 'supabase_service.dart';

/// Read/write helpers for the `blocked_users` table:
///
/// ```sql
/// create table blocked_users (
///   blocker uuid not null references auth.users(id) on delete cascade,
///   blocked uuid not null references auth.users(id) on delete cascade,
///   created_at timestamptz not null default now(),
///   primary key (blocker, blocked)
/// );
/// alter table blocked_users enable row level security;
/// create policy "blocker can manage their own blocks"
///   on blocked_users for all using (auth.uid() = blocker)
///   with check (auth.uid() = blocker);
/// ```
///
/// Read-side queries elsewhere (search results, chat threads, friend requests)
/// should join against this table so the blocking is enforced server-side.
abstract final class BlockApi {
  static SupabaseClient get _c => Supabase.instance.client;

  /// Insert a block row. Idempotent — uses upsert on the composite PK.
  static Future<void> block({
    required String blockerId,
    required String blockedId,
  }) async {
    if (!isSupabaseReady) return;
    if (blockerId.isEmpty || blockedId.isEmpty || blockerId == blockedId) {
      return;
    }
    try {
      await _c.from('blocked_users').upsert(
        {
          'blocker': blockerId,
          'blocked': blockedId,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'blocker,blocked',
      );
    } catch (e) {
      debugPrint('BlockApi.block failed: $e');
      rethrow;
    }
  }

  /// Remove a block row. Safe to call when no row exists.
  static Future<void> unblock({
    required String blockerId,
    required String blockedId,
  }) async {
    if (!isSupabaseReady) return;
    if (blockerId.isEmpty || blockedId.isEmpty) return;
    try {
      await _c
          .from('blocked_users')
          .delete()
          .eq('blocker', blockerId)
          .eq('blocked', blockedId);
    } catch (e) {
      debugPrint('BlockApi.unblock failed: $e');
      rethrow;
    }
  }

  /// True when [blockerId] currently has a block row pointing at [otherId].
  /// Useful for the "Bloquer / Débloquer" toggle in profile / chat headers.
  static Future<bool> isBlocked({
    required String blockerId,
    required String otherId,
  }) async {
    if (!isSupabaseReady || blockerId.isEmpty || otherId.isEmpty) return false;
    try {
      final row = await _c
          .from('blocked_users')
          .select('blocker')
          .eq('blocker', blockerId)
          .eq('blocked', otherId)
          .maybeSingle();
      return row != null;
    } catch (e) {
      debugPrint('BlockApi.isBlocked failed: $e');
      return false;
    }
  }

  /// Hydrated list of profiles I've blocked, newest first. Used by the
  /// Settings → "Liste des bloqués" screen so each row can show the
  /// avatar + name and offer an Unblock action.
  static Future<List<RemoteProfile>> fetchMyBlockedProfiles(
    String blockerId,
  ) async {
    if (!isSupabaseReady || blockerId.isEmpty) return const [];
    try {
      final rows = await _c
          .from('blocked_users')
          .select('blocked, created_at')
          .eq('blocker', blockerId)
          .order('created_at', ascending: false);
      final ids = (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map)['blocked']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (ids.isEmpty) return const [];
      return ProfileApi.fetchByIds(ids);
    } catch (e) {
      debugPrint('BlockApi.fetchMyBlockedProfiles failed: $e');
      return const [];
    }
  }
}
