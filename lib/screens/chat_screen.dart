import 'package:flutter/material.dart';

import '../services/device_id.dart';
import '../services/friendship_api.dart';
import '../services/languages.dart';
import '../services/profile_api.dart';
import '../services/supabase_service.dart';
import '../theme/whatsapp_call_theme.dart';
import 'chat_thread_screen.dart';

/// WhatsApp-style chat home: lists every accepted friend (union of followers
/// + following). Tapping a row opens the direct-message thread, with a
/// deterministic conversation id derived from both device ids so the two
/// sides converge on the same room.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  String _myId = '';
  List<RemoteProfile> _friends = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
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
      final friends = byId.values.toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
        );
      if (!mounted) return;
      setState(() {
        _myId = id;
        _friends = friends;
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
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
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
          return _FriendChatRow(profile: p, onTap: () => _openThread(p));
        },
      ),
    );
  }
}

class _FriendChatRow extends StatelessWidget {
  const _FriendChatRow({required this.profile, required this.onTap});
  final RemoteProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lang = findLanguageByCode(profile.language);
    final name = profile.displayName.isNotEmpty
        ? profile.displayName
        : (profile.handle.isNotEmpty ? '@${profile.handle}' : 'Sans nom');
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: WhatsAppCallTheme.accentMuted,
              ),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      color: WhatsAppCallTheme.strongText,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lang != null
                        ? '${lang.flag}  ${lang.label}'
                        : 'Toucher pour discuter',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      color: WhatsAppCallTheme.subtleText,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: WhatsAppCallTheme.subtleText,
              size: 22,
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
