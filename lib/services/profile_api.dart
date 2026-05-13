import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class RemoteProfile {
  const RemoteProfile({
    required this.id,
    required this.firstName,
    required this.sourceLang,
  });

  final String id;
  final String firstName;
  final String sourceLang;

  factory RemoteProfile.fromMap(Map<String, dynamic> m) => RemoteProfile(
        id: m['id']?.toString() ?? '',
        firstName: m['first_name']?.toString() ?? '',
        sourceLang: m['source_lang']?.toString() ?? '',
      );
}

/// Supabase `profiles` table. Mirror of the local UserPrefs profile so that
/// other users can discover each other by first name.
abstract final class ProfileApi {
  static SupabaseClient get _c => Supabase.instance.client;

  /// Write-through: insert or update my profile row keyed by [deviceId].
  /// Safe to call repeatedly — uses upsert on the primary key.
  /// No-ops (and logs) if Supabase is not configured.
  static Future<void> upsertMyProfile({
    required String deviceId,
    required String firstName,
    required String sourceLang,
  }) async {
    if (!isSupabaseReady) {
      debugPrint('ProfileApi.upsertMyProfile: Supabase not ready, skipping');
      return;
    }
    if (deviceId.isEmpty || firstName.isEmpty) return;
    try {
      await _c.from('profiles').upsert({
        'id': deviceId,
        'first_name': firstName,
        'source_lang': sourceLang,
      }, onConflict: 'id');
    } catch (e) {
      debugPrint('ProfileApi.upsertMyProfile failed: $e');
    }
  }

  /// Case-insensitive substring search by first name. Excludes my own profile.
  static Future<List<RemoteProfile>> searchByFirstName({
    required String query,
    required String myDeviceId,
    int limit = 30,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final rows = await _c
        .from('profiles')
        .select()
        .ilike('first_name', '%$q%')
        .neq('id', myDeviceId)
        .order('first_name', ascending: true)
        .limit(limit);
    return (rows as List)
        .map((r) => RemoteProfile.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }

  /// Bulk fetch by ids (used to resolve friendship rows into people).
  static Future<List<RemoteProfile>> fetchByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _c.from('profiles').select().inFilter('id', ids);
    return (rows as List)
        .map((r) => RemoteProfile.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }
}
