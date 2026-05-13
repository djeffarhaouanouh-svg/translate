import 'package:flutter/material.dart';

import 'screens/join_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/user_prefs.dart';
import 'theme/whatsapp_call_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
              : const JoinScreen(),
    );
  }
}
