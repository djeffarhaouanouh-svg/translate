import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import 'chat_screen.dart';
import 'join_screen.dart';
import 'search_screen.dart';

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
    const SearchScreen(),
    JoinScreen(translation: widget.translation),
    const ChatScreen(),
    _PlaceholderTab(title: AppStrings.t('nav_tab3')),
  ];

  List<NavigationDestination> get _destinations => <NavigationDestination>[
        NavigationDestination(
          icon: const Icon(Icons.search),
          selectedIcon: const Icon(Icons.manage_search),
          label: AppStrings.t('nav_search'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.call_outlined),
          selectedIcon: const Icon(Icons.call),
          label: AppStrings.t('nav_call'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.chat_bubble_outline),
          selectedIcon: const Icon(Icons.chat_bubble),
          label: AppStrings.t('nav_chat'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.circle_outlined),
          selectedIcon: const Icon(Icons.circle),
          label: AppStrings.t('nav_tab3'),
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
      body: Center(
        child: Text(
          AppStrings.t('tab_placeholder_soon'),
          style: const TextStyle(
            color: WhatsAppCallTheme.subtleText,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}
