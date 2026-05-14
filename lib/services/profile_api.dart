import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class RemoteProfile {
  const RemoteProfile({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.language,
    required this.avatarColor,
    required this.avatarUrl,
  });

  final String id;
  final String handle;
  final String displayName;
  final String language;
  final String avatarColor;
  final String avatarUrl;

  /// Backwards-compat shim — the rest of the UI still reads `firstName` /
  /// `sourceLang`. Same data, different schema names.
  String get firstName => displayName;
  String get sourceLang => language;

  factory RemoteProfile.fromMap(Map<String, dynamic> m) => RemoteProfile(
        id: m['id']?.toString() ?? '',
        handle: m['handle']?.toString() ?? '',
        displayName: m['display_name']?.toString() ?? '',
        language: m['language']?.toString() ?? '',
        avatarColor: m['avatar_color']?.toString() ?? '',
        avatarUrl: m['avatar_url']?.toString() ?? '',
      );
}

/// Supabase `profiles` table. Mirror of the local UserPrefs profile so that
/// other users can discover each other by display name.
/// Result of the most recent [ProfileApi.upsertMyProfile] call. Surfaced in
/// the Profile screen so users can see whether their row actually reached
/// Supabase, and what the failure was if it did not.
class ProfileSyncStatus {
  ProfileSyncStatus({
    required this.attemptedAt,
    required this.ok,
    this.error,
  });
  final DateTime attemptedAt;
  final bool ok;
  final String? error;
}

abstract final class ProfileApi {
  static SupabaseClient get _c => Supabase.instance.client;

  /// Most recent upsert outcome — null before the first attempt.
  static ProfileSyncStatus? lastSync;

  /// Build a deterministic handle from the user's display name + device id
  /// so it stays stable across edits but is unique per install.
  static String _deriveHandle(String displayName, String deviceId) {
    final sanitized = displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '')
        .substring(0, displayName.length.clamp(0, 24));
    final suffix = deviceId.replaceAll('-', '').substring(0, 6);
    final base = sanitized.isEmpty ? 'user' : sanitized;
    return '$base-$suffix';
  }

  /// Deterministic accent color for the avatar circle when there is no
  /// uploaded photo. Returns a 7-char `#RRGGBB`.
  static String _deriveAvatarColor(String seed) {
    const palette = <String>[
      '#00A884', '#128C7E', '#075E54', '#34B7F1', '#1F6FEB',
      '#7B61FF', '#A855F7', '#EC4899', '#F97316', '#EAB308',
      '#22C55E', '#14B8A6',
    ];
    if (seed.isEmpty) return palette[0];
    var hash = 0;
    for (final c in seed.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  /// Write-through: insert or update my profile row keyed by [deviceId].
  /// Safe to call repeatedly — uses upsert on the primary key. Records the
  /// outcome in [lastSync] so the Profile screen can surface failures.
  static Future<void> upsertMyProfile({
    required String deviceId,
    required String displayName,
    required String language,
  }) async {
    final now = DateTime.now();
    if (!isSupabaseReady) {
      lastSync = ProfileSyncStatus(
        attemptedAt: now,
        ok: false,
        error: 'Supabase client not initialized (missing SUPABASE_URL / '
            'SUPABASE_PUBLISHABLE_KEY at build time).',
      );
      debugPrint('ProfileApi.upsertMyProfile: Supabase not ready, skipping');
      return;
    }
    if (deviceId.isEmpty || displayName.isEmpty) {
      lastSync = ProfileSyncStatus(
        attemptedAt: now,
        ok: false,
        error: 'Empty deviceId or displayName.',
      );
      return;
    }
    try {
      await _c.from('profiles').upsert({
        'id': deviceId,
        'handle': _deriveHandle(displayName, deviceId),
        'display_name': displayName,
        'language': language,
        'avatar_color': _deriveAvatarColor(displayName + deviceId),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id');
      lastSync = ProfileSyncStatus(attemptedAt: now, ok: true);
    } catch (e) {
      lastSync = ProfileSyncStatus(
        attemptedAt: now,
        ok: false,
        error: e.toString(),
      );
      debugPrint('ProfileApi.upsertMyProfile failed: $e');
    }
  }

  /// Upload [bytes] as the user's avatar to Supabase Storage and write the
  /// resulting public URL back into `profiles.avatar_url`. Returns the URL
  /// (with a cache-busting query param) on success, null on failure.
  static Future<String?> uploadAvatar({
    required String deviceId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    if (!isSupabaseReady) return null;
    if (deviceId.isEmpty || bytes.isEmpty) return null;
    try {
      final ext = contentType.endsWith('png') ? 'png' : 'jpg';
      final path = '$deviceId.$ext';
      await _c.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType,
              cacheControl: '3600',
            ),
          );
      final baseUrl = _c.storage.from('avatars').getPublicUrl(path);
      // Cache-bust so the new image is fetched after re-upload.
      final urlWithBuster =
          '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      await _c.from('profiles').update({
        'avatar_url': urlWithBuster,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', deviceId);
      return urlWithBuster;
    } catch (e) {
      debugPrint('ProfileApi.uploadAvatar failed: $e');
      return null;
    }
  }

  /// Case-insensitive substring search by display name. Excludes my own profile.
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
        .ilike('display_name', '%$q%')
        .neq('id', myDeviceId)
        .order('display_name', ascending: true)
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

  /// Fetch a single profile by id, or null if no row exists.
  static Future<RemoteProfile?> fetchById(String id) async {
    if (!isSupabaseReady || id.isEmpty) return null;
    final row = await _c.from('profiles').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return RemoteProfile.fromMap(Map<String, dynamic>.from(row));
  }
}
