import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/chat_unread.dart';
import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import 'chat_screen.dart';
import 'join_screen.dart';
import 'profile_screen.dart';
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
    const ProfileScreen(),
  ];

  List<NavigationDestination> _destinationsFor(int unread) =>
      <NavigationDestination>[
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
          icon: _badged(const Icon(Icons.chat_bubble_outline), unread),
          selectedIcon: _badged(const Icon(Icons.chat_bubble), unread),
          label: AppStrings.t('nav_chat'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline),
          selectedIcon: const Icon(Icons.person),
          label: AppStrings.t('nav_tab3'),
        ),
      ];

  Widget _badged(Widget icon, int count) {
    if (count <= 0) return icon;
    return Badge.count(
      count: count,
      backgroundColor: WhatsAppCallTheme.danger,
      textColor: Colors.white,
      child: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ChatUnread.count,
      builder: (context, unread, _) {
        return Scaffold(
          backgroundColor: WhatsAppCallTheme.scaffold,
          body: IndexedStack(index: _index, children: _pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            backgroundColor: WhatsAppCallTheme.bar,
            indicatorColor: WhatsAppCallTheme.accentMuted,
            onDestinationSelected: (i) {
              setState(() => _index = i);
              if (i == 2) {
                // Opening Chat tab clears the badge.
                ChatUnread.markAllSeen();
              }
            },
            destinations: _destinationsFor(unread),
          ),
        );
      },
    );
  }
}

