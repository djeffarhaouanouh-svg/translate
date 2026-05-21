import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_strings.dart';
import '../services/call_alert.dart';
import '../services/chat_unread.dart';
import '../services/device_id.dart';
import '../services/incoming_call_api.dart';
import '../services/notification_router.dart';
import '../services/profile_api.dart';
import '../services/supabase_service.dart';
import '../services/token_api.dart';
import '../services/web_poll.dart';
import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import '../widgets/profile_avatar.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'discover_screen.dart';
import 'live_call_screen.dart';
import 'profile_screen.dart';

/// Floating glass-morphism bottom-nav with a sliding pill that animates
/// between selected tabs.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.translation});

  final RealtimeTranslationPort translation;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  /// Default tab — Discover (now at index 1, swapped with Chat).
  static const _mainIndex = 1;
  int _index = _mainIndex;

  // Tab order: Chat (0), Discover (1), Live (2), Profile (3). Discover is
  // the default landing tab. The pages list is rebuilt every frame in
  // build() so the Live tab can be told whether it is currently visible
  // (it holds the camera only while on screen).

  RealtimeChannel? _callsChannel;
  bool _ringingDialogOpen = false;
  Timer? _callPollTimer;
  String _myCalleeId = '';
  /// Call ids that have already triggered the modal — keeps the realtime
  /// channel and the polling backup from racing into two dialogs for the
  /// same ring. Cleared lazily; bounded by call rate so it won't blow up.
  final Set<String> _handledCallIds = {};

  @override
  void initState() {
    super.initState();
    _subscribeIncomingCalls();
    // Route taps on push notifications (live-call invite, message, …).
    NotificationRouter.pending.addListener(_onNotificationIntent);
    // A cold launch from a notification tap may have set an intent
    // before this shell mounted — handle it once after the first frame.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _onNotificationIntent(),
    );
  }

  /// Sends the shell to the screen a tapped notification points at.
  void _onNotificationIntent() {
    final intent = NotificationRouter.pending.value;
    if (intent == null || !mounted) return;
    switch (intent.type) {
      case 'live_call':
        if (_index != 2) setState(() => _index = 2);
      case 'message':
        if (_index != 0) setState(() => _index = 0);
        ChatUnread.markAllSeen();
      // 'incoming_call' needs no routing — the ring modal is shown by
      // the realtime subscription / poll whatever tab is open.
    }
    NotificationRouter.consume();
  }

  Future<void> _subscribeIncomingCalls() async {
    if (!isSupabaseReady) return;
    final myId = await DeviceId.getOrCreate();
    if (!mounted || myId.isEmpty) return;
    _myCalleeId = myId;
    _callsChannel = IncomingCallApi.subscribe(
      calleeId: myId,
      onCall: _handleIncomingCall,
    );
    // Web realtime occasionally misses INSERT events (websocket drop,
    // tab throttling). Poll every 3s as a safety net so a missed
    // notification is at most ~3s late.
    _callPollTimer = WebPoll.every(const Duration(seconds: 3), () async {
      if (!mounted || _ringingDialogOpen) return;
      final pending = await IncomingCallApi.fetchPending(_myCalleeId);
      if (!mounted) return;
      for (final call in pending) {
        if (_handledCallIds.contains(call.id)) continue;
        _handleIncomingCall(call);
        // The dialog can only handle one ring at a time. Bail out and
        // let the next poll pick up any remaining ones once it closes.
        break;
      }
    });
  }

  Future<void> _handleIncomingCall(IncomingCall call) async {
    if (!mounted || _ringingDialogOpen) return;
    if (_handledCallIds.contains(call.id)) return;
    _handledCallIds.add(call.id);
    final caller = isSupabaseReady
        ? await ProfileApi.fetchById(call.callerId)
        : null;
    if (!mounted) return;
    _ringingDialogOpen = true;
    final callerName = caller?.displayName.isNotEmpty == true
        ? caller!.displayName
        : AppStrings.t('incoming_someone');
    // Web only: vibrate + flash the tab title until the user answers /
    // dismisses. No-op on native (handled by the OS already).
    CallAlert.start(callerName: callerName);
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _IncomingCallDialog(
        callerName: callerName,
        callerAvatarUrl: caller?.avatarUrl,
        callerAvatarColor: caller?.avatarColor,
      ),
    );
    CallAlert.stop();
    _ringingDialogOpen = false;
    // Either side of the answer collapses the row so the caller knows.
    await IncomingCallApi.cancel(callId: call.id);
    if (!mounted) return;
    if (accepted == true) {
      await _joinCallRoom(call);
    }
  }

  Future<void> _joinCallRoom(IncomingCall call) async {
    try {
      final myId = await DeviceId.getOrCreate();
      final myProfile = isSupabaseReady
          ? await ProfileApi.fetchById(myId)
          : null;
      final token = await fetchLiveKitToken(
        roomName: call.roomName,
        identity: 'u${DateTime.now().millisecondsSinceEpoch}',
        displayName: myProfile?.displayName ?? '',
        sourceLang: myProfile?.language ?? '',
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            wsUrl: token.url,
            jwt: token.token,
            roomName: token.roomName,
            displayName: myProfile?.displayName ?? '',
            mySourceLang: myProfile?.language ?? '',
            translation: widget.translation,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('cant_join_call', args: {'msg': '$e'}))),
      );
    }
  }

  @override
  void dispose() {
    _callPollTimer?.cancel();
    NotificationRouter.pending.removeListener(_onNotificationIntent);
    final ch = _callsChannel;
    if (ch != null) {
      unawaited(Supabase.instance.client.removeChannel(ch));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      extendBody: true,
      body: ValueListenableBuilder<int>(
        valueListenable: ChatUnread.count,
        builder: (context, unread, _) {
          final pages = <Widget>[
            ChatScreen(translation: widget.translation),
            const DiscoverScreen(),
            LiveCallScreen(
              active: _index == 2,
              translation: widget.translation,
            ),
            const ProfileScreen(),
          ];
          return Stack(
            children: [
              IndexedStack(index: _index, children: pages),
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
                      // Chat is at index 0 now (swapped with Discover).
                      if (i == 0) ChatUnread.markAllSeen();
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
        icon: Icons.chat_bubble_outline,
        selectedIcon: Icons.chat_bubble,
        label: AppStrings.t('nav_chat'),
        badge: unreadChat,
      ),
      _NavItemData(
        icon: Icons.search,
        selectedIcon: Icons.manage_search,
        label: AppStrings.t('nav_search'),
      ),
      const _NavItemData(
        icon: Icons.public,
        selectedIcon: Icons.travel_explore,
        label: 'Live',
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
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
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
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
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

/// Modal shown to the callee when a peer rings them. Pops `true` on
/// "Accepter", `false` on "Refuser".
class _IncomingCallDialog extends StatefulWidget {
  const _IncomingCallDialog({
    required this.callerName,
    required this.callerAvatarUrl,
    required this.callerAvatarColor,
  });

  final String callerName;
  final String? callerAvatarUrl;
  final String? callerAvatarColor;

  @override
  State<_IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<_IncomingCallDialog> {
  static const _timeout = Duration(seconds: 30);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Auto-decline if the user doesn't answer in time so the call doesn't
    // ring forever after the caller has already given up.
    _timer = Timer(_timeout, () {
      if (mounted) Navigator.of(context).pop(false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: WhatsAppCallTheme.bar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tappable hero zone — clicking anywhere on the avatar / name /
          // label accepts the call directly, same effect as the green
          // button. Keeps the explicit Accept / Decline buttons below
          // for users who want to refuse.
          InkWell(
            onTap: () => Navigator.of(context).pop(true),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProfileAvatar(
                    displayName: widget.callerName,
                    avatarUrl: widget.callerAvatarUrl,
                    avatarColorHex: widget.callerAvatarColor,
                    size: 88,
                    fontSize: 36,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.callerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WhatsAppCallTheme.strongText,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.t('incoming_call_label'),
                    style: const TextStyle(
                      color: WhatsAppCallTheme.subtleText,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundActionButton(
                  icon: Icons.call_end,
                  label: AppStrings.t('decline'),
                  color: const Color(0xFFE53935),
                  onTap: () => Navigator.of(context).pop(false),
                ),
                _RoundActionButton(
                  icon: Icons.call,
                  label: AppStrings.t('accept'),
                  color: WhatsAppCallTheme.accent,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: WhatsAppCallTheme.strongText,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
