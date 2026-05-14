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
    // Restore the UI language from the saved profile so the app boots in the
    // user's language instead of the default fallback. Independent of auth
    // state — we still want the login screen in the right language.
    final profile = await UserPrefs.loadProfile();
    if (profile != null && profile.sourceLang.isNotEmpty) {
      AppStrings.setFromCode(profile.sourceLang);
    }
    final authed = AuthService.isAuthenticated;
    if (authed) {
      await _hydrateAuthedSession();
    }
    final onboardingDone =
        authed ? await UserPrefs.isOnboardingDone() : true;
    if (!mounted) return;
    setState(() {
      _authed = authed;
      _needsOnboarding = authed && !onboardingDone;
      _loading = false;
    });
  }

  /// Called whenever a fresh sign-in happens (login or signup confirmation).
  Future<void> _onSignedIn() async {
    setState(() => _loading = true);
    await _hydrateAuthedSession();
    final done = await UserPrefs.isOnboardingDone();
    final profile = await UserPrefs.loadProfile();
    final hasProfile = profile != null && profile.firstName.trim().isNotEmpty;
    if (!mounted) return;
    setState(() {
      _authed = true;
      _needsOnboarding = !done || !hasProfile;
      _loading = false;
    });
  }

  void _onSignedOut() {
    setState(() {
      _authed = false;
      _needsOnboarding = false;
    });
  }

  /// Side-effects that depend on having a current auth user: mirror profile
  /// row, start unread-count listener. Best-effort.
  Future<void> _hydrateAuthedSession() async {
    final uid = AuthService.currentUserId;
    if (uid.isEmpty) return;
    final profile = await UserPrefs.loadProfile();
    if (profile != null && profile.firstName.isNotEmpty) {
      unawaited(ProfileApi.upsertMyProfile(
        deviceId: uid,
        displayName: profile.firstName,
        language: profile.sourceLang,
      ));
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
    if (!_authed) {
      return const LoginScreen();
    }
    if (_needsOnboarding) {
      return OnboardingScreen(
        onCompleted: () => setState(() => _needsOnboarding = false),
      );
    }
    return RootShell(translation: _translation);
  }
}
