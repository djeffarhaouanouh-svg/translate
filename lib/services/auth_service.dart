import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Thin wrapper around `Supabase.instance.client.auth` so the rest of the app
/// imports a stable surface instead of reaching into the SDK directly. Every
/// method short-circuits with a clear error when Supabase wasn't configured
/// at build time.
abstract final class AuthService {
  static GoTrueClient get _auth => Supabase.instance.client.auth;

  static User? get currentUser =>
      isSupabaseReady ? _auth.currentUser : null;

  /// Empty string when not authenticated. Use [isAuthenticated] to gate flows.
  static String get currentUserId => currentUser?.id ?? '';

  /// Email tied to the auth account. Lives only on `auth.users` (never copied
  /// to `profiles`), so other users cannot read it.
  static String get currentEmail => currentUser?.email ?? '';

  static bool get isAuthenticated => currentUser != null;

  /// Broadcast stream — useful for routing the app between Login / Onboarding
  /// / Home in reaction to sign-in or sign-out.
  static Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    if (!isSupabaseReady) {
      throw StateError('Supabase non configuré');
    }
    return _auth.signUp(email: email.trim().toLowerCase(), password: password);
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    if (!isSupabaseReady) {
      throw StateError('Supabase non configuré');
    }
    return _auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  static Future<void> signOut() {
    if (!isSupabaseReady) return Future.value();
    return _auth.signOut();
  }

  static Future<void> resetPassword(String email) {
    if (!isSupabaseReady) {
      throw StateError('Supabase non configuré');
    }
    return _auth.resetPasswordForEmail(email.trim().toLowerCase());
  }

  /// Re-trigger the signup confirmation email for users who never clicked
  /// the original link. Idempotent server-side: Supabase rate-limits how
  /// often this can fire per address.
  static Future<void> resendSignupConfirmation(String email) {
    if (!isSupabaseReady) {
      throw StateError('Supabase non configuré');
    }
    return _auth.resend(
      type: OtpType.signup,
      email: email.trim().toLowerCase(),
    );
  }
}
