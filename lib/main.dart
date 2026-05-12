import 'package:flutter/material.dart';

import 'screens/join_screen.dart';
import 'theme/whatsapp_call_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LiveKitTranslateApp());
}

class LiveKitTranslateApp extends StatelessWidget {
  const LiveKitTranslateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveKit Call',
      debugShowCheckedModeBanner: false,
      theme: WhatsAppCallTheme.material(),
      home: const JoinScreen(),
    );
  }
}
