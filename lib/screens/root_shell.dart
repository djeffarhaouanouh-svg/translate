import 'package:flutter/material.dart';

import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import 'join_screen.dart';

/// Bottom-nav host for the app. The existing join flow lives at the centered
/// "Appel" tab; the three placeholder tabs are scaffolded for later screens.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.translation});

  final RealtimeTranslationPort translation;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  static const _mainIndex = 1;
  int _index = _mainIndex;

  late final List<Widget> _pages = <Widget>[
    const _PlaceholderTab(title: 'Onglet 1'),
    JoinScreen(translation: widget.translation),
    const _PlaceholderTab(title: 'Onglet 2'),
    const _PlaceholderTab(title: 'Onglet 3'),
  ];

  static const List<NavigationDestination> _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.circle_outlined),
      selectedIcon: Icon(Icons.circle),
      label: 'Onglet 1',
    ),
    NavigationDestination(
      icon: Icon(Icons.call_outlined),
      selectedIcon: Icon(Icons.call),
      label: 'Appel',
    ),
    NavigationDestination(
      icon: Icon(Icons.circle_outlined),
      selectedIcon: Icon(Icons.circle),
      label: 'Onglet 2',
    ),
    NavigationDestination(
      icon: Icon(Icons.circle_outlined),
      selectedIcon: Icon(Icons.circle),
      label: 'Onglet 3',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        backgroundColor: WhatsAppCallTheme.bar,
        indicatorColor: WhatsAppCallTheme.accentMuted,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      appBar: AppBar(title: Text(title)),
      body: const Center(
        child: Text(
          'Bientôt',
          style: TextStyle(
            color: WhatsAppCallTheme.subtleText,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}
