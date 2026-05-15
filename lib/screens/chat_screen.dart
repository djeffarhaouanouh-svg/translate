import 'package:flutter/material.dart';

import '../services/block_api.dart';
import '../services/call_launcher.dart';
import '../services/chat_api.dart';
import '../services/device_id.dart';
import '../services/friendship_api.dart';
import '../services/languages.dart';
import '../services/profile_api.dart';
import '../services/supabase_service.dart';
import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import '../widgets/profile_avatar.dart';
import 'chat_thread_screen.dart';

/// WhatsApp-style chat home: lists every accepted friend (union of followers
/// + following). Tapping a row opens the direct-message thread; the trailing
/// video icon launches a call directly with that friend.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.translation = const NoOpRealtimeTranslation(),
  });

  final RealtimeTranslationPort translation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  String _myId = '';
  List<RemoteProfile> _friends = const [];
  Map<String, ChatMessage> _latestByConv = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
    // NOTE: we deliberately do NOT call ChatUnread.markAllSeen() here.
    // ChatScreen lives inside IndexedStack, so initState fires at app
    // launch even when the user is on another tab — calling markAllSeen
    // here would silently wipe the unread badge before the user ever
    // sees it. The badge is cleared in RootShell when the user actually
    // taps the Chat tab destination.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload();
    }
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = await DeviceId.getOrCreate();
      if (!isSupabaseReady) {
        if (!mounted) return;
        setState(() {
          _myId = id;
          _friends = const [];
          _loading = false;
        });
        return;
      }
      final followers = await FriendshipApi.fetchAcceptedPeers(
        meId: id,
        direction: FriendDirection.followers,
      );
      final following = await FriendshipApi.fetchAcceptedPeers(
        meId: id,
        direction: FriendDirection.following,
      );
      final byId = <String, RemoteProfile>{};
      for (final p in followers) {
        byId[p.id] = p;
      }
      for (final p in following) {
        byId[p.id] = p;
      }

      // Fetch the latest message for each conversation involving me — used
      // to render the last-message preview and to sort rows by most-recent
      // activity (WhatsApp style).
      final latest = await ChatApi.fetchLatestPerConversation(id);

      String convIdFor(String otherId) {
        final ids = [id, otherId]..sort();
        return 'dm-${ids[0]}-${ids[1]}';
      }

      final friends = byId.values.toList()
        ..sort((a, b) {
          final la = latest[convIdFor(a.id)]?.createdAt;
          final lb = latest[convIdFor(b.id)]?.createdAt;
          if (la == null && lb == null) {
            return a.displayName
                .toLowerCase()
                .compareTo(b.displayName.toLowerCase());
          }
          if (la == null) return 1; // peers without messages sink to the bottom
          if (lb == null) return -1;
          return lb.compareTo(la); // most recent first
        });
      if (!mounted) return;
      setState(() {
        _myId = id;
        _friends = friends;
        _latestByConv = latest;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur de chargement : $e';
        _loading = false;
      });
    }
  }

  String _conversationIdFor(String otherId) {
    final ids = [_myId, otherId]..sort();
    return 'dm-${ids[0]}-${ids[1]}';
  }

  Future<void> _openThread(RemoteProfile peer) async {
    final convId = _conversationIdFor(peer.id);
    final title = peer.displayName.isNotEmpty
        ? peer.displayName
        : (peer.handle.isNotEmpty ? '@${peer.handle}' : 'Ami');
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatThreadScreen(
          conversationId: convId,
          title: title,
          peerDeviceId: peer.id,
          translation: widget.translation,
        ),
      ),
    );
    _reload();
  }

  void _callPeer(RemoteProfile peer) {
    CallLauncher.startCall(
      context,
      peerDeviceId: peer.id,
      translation: widget.translation,
    );
  }

  void _viewProfile(RemoteProfile peer) {
    // No standalone "other user profile" screen yet — placeholder until that
    // view ships. Keeps the menu real so users see the option exists.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Profil de ${peer.displayName} — bientôt disponible'),
        backgroundColor: WhatsAppCallTheme.bar,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _blockPeer(RemoteProfile peer) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WhatsAppCallTheme.bar,
        title: Text(
          'Bloquer ${peer.displayName} ?',
          style: const TextStyle(color: WhatsAppCallTheme.strongText),
        ),
        content: const Text(
          'Cette personne ne pourra plus te trouver, te contacter ni t\'appeler. Tu peux annuler depuis Paramètres → Bloqués.',
          style: TextStyle(color: WhatsAppCallTheme.subtleText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Bloquer'),
          ),
        ],
      ),
    );
    if (ok != true || _myId.isEmpty) return;
    try {
      await BlockApi.block(blockerId: _myId, blockedId: peer.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${peer.displayName} bloqué.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Messages',
                  style: TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: WhatsAppCallTheme.accent),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _error!,
          style: const TextStyle(color: Color(0xFFFFAB91), height: 1.35, fontSize: 13),
        ),
      );
    }
    if (_friends.isEmpty) {
      return const _NoFriendsEmpty();
    }
    return RefreshIndicator(
      color: WhatsAppCallTheme.accent,
      backgroundColor: WhatsAppCallTheme.bar,
      onRefresh: _reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _friends.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          color: Color(0xFF1F2C34),
          indent: 76,
        ),
        itemBuilder: (ctx, i) {
          final p = _friends[i];
          final last = _latestByConv[_conversationIdFor(p.id)];
          return _FriendChatRow(
            profile: p,
            lastMessage: last,
            isMine: last?.senderId == _myId,
            onTap: () => _openThread(p),
            onCall: () => _callPeer(p),
            onViewProfile: () => _viewProfile(p),
            onBlock: () => _blockPeer(p),
          );
        },
      ),
    );
  }
}

class _FriendChatRow extends StatelessWidget {
  const _FriendChatRow({
    required this.profile,
    required this.lastMessage,
    required this.isMine,
    required this.onTap,
    required this.onCall,
    required this.onViewProfile,
    required this.onBlock,
  });
  final RemoteProfile profile;
  final ChatMessage? lastMessage;
  final bool isMine;
  final VoidCallback onTap;
  final VoidCallback onCall;
  final VoidCallback onViewProfile;
  final VoidCallback onBlock;

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isSameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isSameDay) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    final wasYesterday =
        dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;
    if (wasYesterday) return 'hier';
    final daysAgo = now.difference(dt).inDays;
    if (daysAgo < 7) {
      const weekdays = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
      return weekdays[(dt.weekday - 1).clamp(0, 6)];
    }
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$d/$mo';
  }

  @override
  Widget build(BuildContext context) {
    final lang = findLanguageByCode(profile.language);
    final name = profile.displayName.isNotEmpty
        ? profile.displayName
        : (profile.handle.isNotEmpty ? '@${profile.handle}' : 'Sans nom');

    final subtitleParts = <InlineSpan>[];
    if (lastMessage != null && lastMessage!.body.isNotEmpty) {
      if (isMine) {
        subtitleParts.add(const TextSpan(
          text: 'Vous : ',
          style: TextStyle(
            color: WhatsAppCallTheme.subtleText,
            fontWeight: FontWeight.w500,
          ),
        ));
      }
      subtitleParts.add(TextSpan(text: lastMessage!.body));
    } else if (lang != null) {
      subtitleParts.add(TextSpan(text: '${lang.flag}  ${lang.label}'));
    } else {
      subtitleParts.add(const TextSpan(text: 'Toucher pour discuter'));
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            ProfileAvatar(
              displayName: profile.displayName,
              avatarUrl: profile.avatarUrl,
              avatarColorHex: profile.avatarColor,
              size: 60,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: const TextStyle(
                            color: WhatsAppCallTheme.strongText,
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      if (lastMessage != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _formatTime(lastMessage!.createdAt),
                          style: const TextStyle(
                            color: WhatsAppCallTheme.subtleText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    text: TextSpan(
                      style: const TextStyle(
                        color: WhatsAppCallTheme.subtleText,
                        fontSize: 14,
                      ),
                      children: subtitleParts,
                    ),
                  ),
                ],
              ),
            ),
            // Trailing actions: quick call + 3-dot menu (Voir profil / Bloquer).
            IconButton(
              tooltip: 'Appeler',
              onPressed: onCall,
              icon: const Icon(Icons.phone, color: WhatsAppCallTheme.accent),
            ),
            PopupMenuButton<String>(
              tooltip: 'Plus',
              icon: const Icon(Icons.more_vert,
                  color: WhatsAppCallTheme.subtleText),
              color: WhatsAppCallTheme.bar,
              onSelected: (v) {
                if (v == 'profile') onViewProfile();
                if (v == 'block') onBlock();
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem<String>(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 18, color: WhatsAppCallTheme.strongText),
                      SizedBox(width: 10),
                      Text('Voir profil',
                          style: TextStyle(
                              color: WhatsAppCallTheme.strongText)),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block,
                          size: 18, color: Color(0xFFE53935)),
                      SizedBox(width: 10),
                      Text('Bloquer',
                          style: TextStyle(color: Color(0xFFE53935))),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoFriendsEmpty extends StatelessWidget {
  const _NoFriendsEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: WhatsAppCallTheme.bar,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline,
                color: WhatsAppCallTheme.subtleText,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Pas encore d\'amis',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Va dans l\'onglet Recherche pour trouver quelqu\'un par son prénom, '
              'puis envoie une demande d\'ami pour pouvoir discuter avec lui.',
              textAlign: TextAlign.center,
              style: TextStyle(color: WhatsAppCallTheme.subtleText, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
