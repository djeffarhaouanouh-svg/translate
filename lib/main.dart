import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/root_shell.dart';
import 'services/app_strings.dart';
import 'services/auth_service.dart';
import 'services/chat_unread.dart';
import 'services/profile_api.dart';
import 'services/supabase_service.dart';
import 'services/user_prefs.dart';
import 'theme/whatsapp_call_theme.dart';
import 'translation/openai_realtime_translation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const LiveKitTranslateApp());
}

class LiveKitTranslateApp extends StatefulWidget {
  const LiveKitTranslateApp({super.key});

  @override
  State<LiveKitTranslateApp> createState() => _LiveKitTranslateAppState();
}

class _LiveKitTranslateAppState extends State<LiveKitTranslateApp> {
  bool _loading = true;
  bool _needsOnboarding = false;
  bool _authed = false;
  late final OpenAiRealtimeTranslation _translation;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _translation = OpenAiRealtimeTranslation();
    _bootstrap();
    // React to sign-in / sign-out events anywhere in the app.
    if (isSupabaseReady) {
      _authSub = AuthService.onAuthStateChange.listen((state) {
        final wasAuthed = _authed;
        final nowAuthed = AuthService.isAuthenticated;
        if (wasAuthed != nowAuthed) {
          if (nowAuthed) {
            _onSignedIn();
          } else {
            _onSignedOut();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _translation.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Onboarding (name + language) is now stored locally and runs BEFORE
    // login, so the login screen itself is rendered in the user's chosen
    // language. Restore the UI language from local prefs as early as possible.
    final profile = await UserPrefs.loadProfile();
    if (profile != null && profile.sourceLang.isNotEmpty) {
      AppStrings.setFromCode(profile.sourceLang);
    }
    final hasLocalOnboarding =
        profile != null && profile.firstName.trim().isNotEmpty;
    final authed = AuthService.isAuthenticated;
    if (authed) {
      await _hydrateAuthedSession();
    }
    if (!mounted) return;
    setState(() {
      _authed = authed;
      _needsOnboarding = !hasLocalOnboarding;
      _loading = false;
    });
  }

  /// Called whenever a fresh sign-in happens (login or signup confirmation).
  Future<void> _onSignedIn() async {
    setState(() => _loading = true);
    await _hydrateAuthedSession();
    if (!mounted) return;
    // Onboarding already happened pre-login by design, so we never bounce
    // back to it here. The Supabase profile row was either created by the
    // hydrate step above, or by the upsert call there if missing.
    setState(() {
      _authed = true;
      _loading = false;
    });
  }

  void _onSignedOut() {
    setState(() {
      _authed = false;
      _needsOnboarding = false;
    });
  }

  /// Side-effects that depend on having a current auth user: mirror the
  /// locally-stored onboarding data (display name + spoken language) up to
  /// the Supabase `profiles` row, then start the unread-count listener.
  /// This is what materializes the profile right after signup — the user
  /// chose their name and language pre-login, we push them now that we
  /// have an auth.uid() to anchor on.
  Future<void> _hydrateAuthedSession() async {
    final uid = AuthService.currentUserId;
    if (uid.isEmpty) return;
    final profile = await UserPrefs.loadProfile();
    if (profile != null && profile.firstName.isNotEmpty) {
      // Await this one — the user may navigate straight to the profile tab
      // and we don't want a flash of "no row".
      await ProfileApi.upsertMyProfile(
        deviceId: uid,
        displayName: profile.firstName,
        language: profile.sourceLang,
      );
    }
    unawaited(ChatUnread.start(uid));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppStrings.currentBcp47,
      builder: (context, _, _) {
        return MaterialApp(
          title: 'Calls',
          debugShowCheckedModeBanner: false,
          theme: WhatsAppCallTheme.material(),
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    if (_loading) {
      return const Scaffold(
        backgroundColor: WhatsAppCallTheme.scaffold,
        body: Center(
          child: CircularProgressIndicator(color: WhatsAppCallTheme.accent),
        ),
      );
    }
    // Order matters: language must be picked before the login screen so the
    // copy on Login/Signup renders in the user's chosen language.
    if (_needsOnboarding) {
      return OnboardingScreen(
        onCompleted: () => setState(() => _needsOnboarding = false),
      );
    }
    if (!_authed) {
      return const LoginScreen();
    }
    return RootShell(translation: _translation);
  }
}
