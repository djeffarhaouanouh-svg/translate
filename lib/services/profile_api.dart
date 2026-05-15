import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Default weekly allotment for the free tier (seconds of translated call).
const int freeWeeklyCreditsSeconds = 15 * 60; // 15 min
/// Default weekly allotment for the Premium tier.
const int proWeeklyCreditsSeconds = 4 * 60 * 60; // 4 h (~3-5h target band)

class RemoteProfile {
  const RemoteProfile({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.language,
    required this.avatarColor,
    required this.avatarUrl,
    this.isPro = false,
    this.creditsSeconds = freeWeeklyCreditsSeconds,
    this.creditsResetAt,
    this.lifetimeCallSeconds = 0,
    this.proExpiresAt,
  });

  final String id;
  final String handle;
  final String displayName;
  final String language;
  final String avatarColor;
  final String avatarUrl;

  /// Subscription state. `true` while the user has an active Premium
  /// entitlement (validated against the store IAP receipt server-side, later).
  final bool isPro;

  /// Translation credit remaining in seconds. Decremented during calls; the
  /// translation pipeline disables itself when this hits 0 but the underlying
  /// call keeps going.
  final int creditsSeconds;

  /// Next refill — when `now()` passes this, credits are reset to the tier's
  /// weekly allotment ([proWeeklyCreditsSeconds] / [freeWeeklyCreditsSeconds]).
  final DateTime? creditsResetAt;

  /// Lifetime stat (never reset). Used for "X minutes used" on the profile.
  final int lifetimeCallSeconds;

  /// When the current Premium period ends. Null on free tier.
  final DateTime? proExpiresAt;

  /// Backwards-compat shim — the rest of the UI still reads `firstName` /
  /// `sourceLang`. Same data, different schema names.
  String get firstName => displayName;
  String get sourceLang => language;

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  static int _parseInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  factory RemoteProfile.fromMap(Map<String, dynamic> m) => RemoteProfile(
        id: m['id']?.toString() ?? '',
        handle: m['handle']?.toString() ?? '',
        displayName: m['display_name']?.toString() ?? '',
        language: m['language']?.toString() ?? '',
        avatarColor: m['avatar_color']?.toString() ?? '',
        avatarUrl: m['avatar_url']?.toString() ?? '',
        isPro: m['is_pro'] == true,
        creditsSeconds:
            _parseInt(m['credits_seconds'], freeWeeklyCreditsSeconds),
        creditsResetAt: _parseDate(m['credits_reset_at']),
        lifetimeCallSeconds: _parseInt(m['lifetime_call_seconds'], 0),
        proExpiresAt: _parseDate(m['pro_expires_at']),
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
  /// resulting public URL back into `profiles.avatar_url`. Throws on failure
  /// so the caller can surface the real error (bucket missing, RLS, etc.).
  static Future<String> uploadAvatar({
    required String deviceId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    if (!isSupabaseReady) {
      throw StateError('Supabase non configuré');
    }
    if (deviceId.isEmpty) throw ArgumentError('deviceId vide');
    if (bytes.isEmpty) throw ArgumentError('image vide');

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
    final urlWithBuster =
        '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    await _c.from('profiles').update({
      'avatar_url': urlWithBuster,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', deviceId);
    return urlWithBuster;
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

  /// Fetch a single profile by id, or null if no row exists. Also applies the
  /// weekly credit-refill check so the rest of the app doesn't have to.
  static Future<RemoteProfile?> fetchById(String id) async {
    if (!isSupabaseReady || id.isEmpty) return null;
    final row = await _c.from('profiles').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    final p = RemoteProfile.fromMap(Map<String, dynamic>.from(row));
    final refilled = await _maybeRefillCredits(p);
    return refilled ?? p;
  }

  /// If [p.creditsResetAt] is in the past, top credits back up to the tier's
  /// weekly allotment and push a new reset date 7 days out. Returns the
  /// updated profile, or null if no refill was needed.
  static Future<RemoteProfile?> _maybeRefillCredits(RemoteProfile p) async {
    final resetAt = p.creditsResetAt;
    if (resetAt == null) return null;
    if (DateTime.now().isBefore(resetAt)) return null;
    final allotment =
        p.isPro ? proWeeklyCreditsSeconds : freeWeeklyCreditsSeconds;
    final nextReset = DateTime.now().toUtc().add(const Duration(days: 7));
    try {
      await _c.from('profiles').update({
        'credits_seconds': allotment,
        'credits_reset_at': nextReset.toIso8601String(),
      }).eq('id', p.id);
    } catch (e) {
      debugPrint('ProfileApi._maybeRefillCredits failed: $e');
      return null;
    }
    return RemoteProfile(
      id: p.id,
      handle: p.handle,
      displayName: p.displayName,
      language: p.language,
      avatarColor: p.avatarColor,
      avatarUrl: p.avatarUrl,
      isPro: p.isPro,
      creditsSeconds: allotment,
      creditsResetAt: nextReset.toLocal(),
      lifetimeCallSeconds: p.lifetimeCallSeconds,
      proExpiresAt: p.proExpiresAt,
    );
  }

  /// Decrement `credits_seconds` by [seconds] and bump `lifetime_call_seconds`
  /// by the same amount. Both clamp at sensible bounds. Returns the new
  /// credits balance, or null on failure.
  ///
  /// Note: this is a client-side decrement. A determined user could spoof it
  /// by editing the request. That's fine for the v1 honor-system; if it
  /// becomes an issue we'll move it behind a Postgres function with
  /// `SECURITY DEFINER` so the decrement is atomic + tamper-proof.
  static Future<int?> consumeCredits({
    required String userId,
    required int seconds,
  }) async {
    if (!isSupabaseReady || userId.isEmpty || seconds <= 0) return null;
    try {
      // Read-modify-write. Two round-trips but keeps the logic readable.
      final row = await _c
          .from('profiles')
          .select('credits_seconds, lifetime_call_seconds')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      final current = RemoteProfile._parseInt(row['credits_seconds'], 0);
      final lifetime =
          RemoteProfile._parseInt(row['lifetime_call_seconds'], 0);
      final next = (current - seconds).clamp(0, 1 << 31);
      await _c.from('profiles').update({
        'credits_seconds': next,
        'lifetime_call_seconds': lifetime + seconds,
      }).eq('id', userId);
      return next;
    } catch (e) {
      debugPrint('ProfileApi.consumeCredits failed: $e');
      return null;
    }
  }

  /// Permanently remove the caller's profile row and any friendships they
  /// participate in. The Supabase auth.users record is **not** deleted —
  /// that requires a server-side admin call. Calling code should sign the
  /// user out right after; the next sign-in will route them through
  /// onboarding because their profile row is gone.
  static Future<void> deleteMyProfile(String userId) async {
    if (!isSupabaseReady || userId.isEmpty) return;
    try {
      await _c
          .from('friendships')
          .delete()
          .or('requester.eq.$userId,addressee.eq.$userId');
    } catch (e) {
      debugPrint('ProfileApi.deleteMyProfile: friendships cleanup failed: $e');
    }
    await _c.from('profiles').delete().eq('id', userId);
  }

  /// Activate (or extend) Premium for [userId]. Stamps `pro_expires_at` 7
  /// days out, flips `is_pro` true, refills credits to the Pro allotment.
  ///
  /// In production this should be called by the BACKEND after validating
  /// an App Store / Play Store receipt — never trust the client. For now
  /// it's wired so the UI can demo the upgrade flow.
  static Future<void> activatePremiumWeek(String userId) async {
    if (!isSupabaseReady || userId.isEmpty) return;
    final until = DateTime.now().toUtc().add(const Duration(days: 7));
    await _c.from('profiles').update({
      'is_pro': true,
      'pro_expires_at': until.toIso8601String(),
      'credits_seconds': proWeeklyCreditsSeconds,
      'credits_reset_at': until.toIso8601String(),
    }).eq('id', userId);
  }
}
