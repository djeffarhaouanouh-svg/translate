import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// User identifier used as the chat `sender_id`, friendship key, etc.
///
/// Now that Supabase Auth is the source of identity, this resolves to
/// `auth.currentUser.id` whenever the user is signed in — which is the case
/// everywhere inside [RootShell] (the app gates login at boot). The legacy
/// per-install UUID is kept only as a fallback for dev builds without
/// Supabase configured, so the call-sites scattered across the codebase
/// don't need to know the difference.
abstract final class DeviceId {
  static const _key = 'device_id';
  static String? _cached;

  static Future<String> getOrCreate() async {
    // Prefer the authenticated user id — that's the real identity now.
    if (AuthService.isAuthenticated) {
      return AuthService.currentUserId;
    }
    final cached = _cached;
    if (cached != null) return cached;
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_key);
    if (id == null || id.isEmpty) {
      id = _uuidV4();
      await p.setString(_key, id);
    }
    _cached = id;
    return id;
  }

  static String _uuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
    String hex(int v) => v.toRadixString(16).padLeft(2, '0');
    final h = b.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
  }
}
