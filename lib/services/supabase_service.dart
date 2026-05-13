import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Initializes the global Supabase client from build-time env. Safe to call
/// before `runApp`. No-ops (and logs a debug message) when keys are missing so
/// local dev without Supabase keys still boots normally.
Future<void> initSupabase() async {
  final url = resolvedSupabaseUrl();
  final key = resolvedSupabasePublishableKey();
  if (url.isEmpty || key.isEmpty) {
    debugPrint(
      'Supabase: SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY not set — '
      'client not initialized. Pass via --dart-define at build time.',
    );
    return;
  }
  await Supabase.initialize(url: url, anonKey: key);
}

/// Whether [Supabase.instance] is usable. False when the keys were missing at
/// build time. Callers that touch the client must guard on this.
bool get isSupabaseReady {
  try {
    Supabase.instance;
    return true;
  } catch (_) {
    return false;
  }
}
