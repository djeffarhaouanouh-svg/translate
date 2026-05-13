import 'package:flutter/material.dart';

import 'screens/onboarding_screen.dart';
import 'screens/root_shell.dart';
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
  late final OpenAiRealtimeTranslation _translation;

  @override
  void initState() {
    super.initState();
    _translation = OpenAiRealtimeTranslation();
    _bootstrap();
  }

  @override
  void dispose() {
    _translation.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final done = await UserPrefs.isOnboardingDone();
    if (!mounted) return;
    setState(() {
      _needsOnboarding = !done;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calls',
      debugShowCheckedModeBanner: false,
      theme: WhatsAppCallTheme.material(),
      home: _loading
          ? const Scaffold(
              backgroundColor: WhatsAppCallTheme.scaffold,
              body: Center(
                child: CircularProgressIndicator(color: WhatsAppCallTheme.accent),
              ),
            )
          : _needsOnboarding
              ? OnboardingScreen(
                  onCompleted: () => setState(() => _needsOnboarding = false),
                )
              : RootShell(translation: _translation),
    );
  }
}
