import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/chat_unread.dart';
import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import 'chat_screen.dart';
import 'join_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

/// Floating glass-morphism bottom-nav with a sliding pill that animates
/// between selected tabs.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      extendBody: true,
      body: ValueListenableBuilder<int>(
        valueListenable: ChatUnread.count,
        builder: (context, unread, _) {
          return Stack(
            children: [
              IndexedStack(index: _index, children: _pages),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12 + MediaQuery.paddingOf(context).bottom,
                child: Center(
                  child: _GlassNavBar(
                    selected: _index,
                    unreadChat: unread,
                    onSelect: (i) {
                      setState(() => _index = i);
                      if (i == 2) ChatUnread.markAllSeen();
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({
    required this.selected,
    required this.unreadChat,
    required this.onSelect,
  });

  final int selected;
  final int unreadChat;
  final ValueChanged<int> onSelect;

  static const double _height = 54;
  static const double _itemWidth = 72;
  static const double _hPad = 10;

  @override
  Widget build(BuildContext context) {
    final items = <_NavItemData>[
      _NavItemData(
        icon: Icons.search,
        selectedIcon: Icons.manage_search,
        label: AppStrings.t('nav_search'),
      ),
      _NavItemData(
        icon: Icons.call_outlined,
        selectedIcon: Icons.call,
        label: AppStrings.t('nav_call'),
      ),
      _NavItemData(
        icon: Icons.chat_bubble_outline,
        selectedIcon: Icons.chat_bubble,
        label: AppStrings.t('nav_chat'),
        badge: unreadChat,
      ),
      _NavItemData(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: AppStrings.t('nav_tab3'),
      ),
    ];

    final totalWidth = _hPad * 2 + _itemWidth * items.length;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: totalWidth,
          height: _height,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: 6),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Sliding highlight pill — animates between item slots.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: _itemWidth * selected,
                top: 0,
                bottom: 0,
                width: _itemWidth,
                child: Center(
                  child: Container(
                    width: _itemWidth - 4,
                    height: _height - 16,
                    decoration: BoxDecoration(
                      color: WhatsAppCallTheme.accent.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: WhatsAppCallTheme.accent.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
              // Items.
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    SizedBox(
                      width: _itemWidth,
                      height: _height,
                      child: _NavItem(
                        data: items[i],
                        selected: selected == i,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _NavItemData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Center(
          child: _badged(
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                selected ? data.selectedIcon : data.icon,
                key: ValueKey(selected),
                size: 22,
                color: selected
                    ? WhatsAppCallTheme.accent
                    : Colors.white.withValues(alpha: 0.78),
              ),
            ),
            data.badge,
          ),
        ),
      ),
    );
  }

  Widget _badged(Widget child, int count) {
    if (count <= 0) return child;
    return Badge.count(
      count: count,
      backgroundColor: WhatsAppCallTheme.danger,
      textColor: Colors.white,
      child: child,
    );
  }
}
