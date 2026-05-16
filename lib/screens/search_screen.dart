import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/device_id.dart';
import '../services/friendship_api.dart';
import '../services/greetings.dart';
import '../services/languages.dart';
import '../services/profile_api.dart';
import '../services/supabase_service.dart';
import '../services/web_poll.dart';
import '../theme/whatsapp_call_theme.dart';
import '../widgets/profile_avatar.dart';

/// Onglet 1 — find friends by their first name. Each result row shows their
/// language flag and a contextual action button based on the existing
/// friendship state (none / pending / accepted).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with WidgetsBindingObserver {
  final _queryCtrl = TextEditingController();
  Timer? _debounce;

  String _myId = '';
  List<RemoteProfile> _results = const [];
  List<Friendship> _myFriendships = const [];
  List<IncomingFriendRequest> _incoming = const [];
  bool _searching = false;
  String? _error;
  RealtimeChannel? _friendshipsChannel;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFriendships();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _queryCtrl.dispose();
    _pollTimer?.cancel();
    final ch = _friendshipsChannel;
    if (ch != null) {
      unawaited(Supabase.instance.client.removeChannel(ch));
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final id = await DeviceId.getOrCreate();
    if (!mounted) return;
    setState(() => _myId = id);
    await _refreshFriendships();
    // Live-refresh the inbox + friends list whenever any friendships row
    // changes anywhere — RLS filters what we can see, so this picks up
    // new incoming requests addressed to me without waiting on a tab
    // open or app resume.
    if (isSupabaseReady && id.isNotEmpty) {
      _friendshipsChannel = FriendshipApi.subscribeMine(
        userId: id,
        onChange: () {
          if (mounted) _refreshFriendships();
        },
      );
    }
    // Web realtime occasionally drops — polling backup so a freshly
    // received friend request still surfaces within ~8s.
    _pollTimer = WebPoll.every(
      const Duration(seconds: 8),
      () => _refreshFriendships(),
    );
  }

  Future<void> _refreshFriendships() async {
    if (_myId.isEmpty) return;
    try {
      final list = await FriendshipApi.fetchMine(_myId);
      final incoming =
          await FriendshipApi.fetchIncomingPendingWithProfiles(_myId);
      if (!mounted) return;
      setState(() {
        _myFriendships = list;
        _incoming = incoming;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Impossible de charger les amitiés: $e');
      return;
    }
  }


  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _runSearch(value));
  }

  Future<void> _runSearch(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    if (!isSupabaseReady) {
      setState(() => _error = 'Supabase non configuré — recherche désactivée.');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await ProfileApi.searchByFirstName(
        query: q,
        myDeviceId: _myId,
      );
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Recherche échouée: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(RemoteProfile peer) async {
    try {
      final f = await FriendshipApi.sendRequest(meId: _myId, peerId: peer.id);
      if (!mounted) return;
      if (f == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supabase non configuré.')),
        );
        return;
      }
      // Seed a 👋 so the conversation appears in both chat lists right
      // away — best-effort, ignored on failure.
      unawaited(Greetings.sendIntroMessage(myId: _myId, peerId: peer.id));
      await _refreshFriendships();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  Future<void> _accept(Friendship f) async {
    await FriendshipApi.accept(f.id);
    await _refreshFriendships();
  }

  Future<void> _reject(Friendship f) async {
    await FriendshipApi.reject(f.id);
    await _refreshFriendships();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
        children: [
          _SearchField(controller: _queryCtrl, onChanged: _onQueryChanged),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFFAB91), fontSize: 12, height: 1.3),
              ),
            ),
          if (_incoming.isNotEmpty)
            _IncomingRequestsSection(
              requests: _incoming,
              onAccept: _accept,
              onReject: _reject,
            ),
          Expanded(child: _buildBody()),
        ],
      ),
      ),
    );
  }

  Widget _buildBody() {
    if (_searching) {
      return const Center(
        child: CircularProgressIndicator(color: WhatsAppCallTheme.accent),
      );
    }
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) {
      return const _SearchIntro();
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Aucun profil trouvé pour « $q ».',
            textAlign: TextAlign.center,
            style: const TextStyle(color: WhatsAppCallTheme.subtleText, fontSize: 14),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF1F2C34)),
      itemBuilder: (ctx, i) {
        final p = _results[i];
        final (status, f) = FriendshipApi.statusWith(_myId, p.id, _myFriendships);
        return _ProfileRow(
          profile: p,
          status: status,
          friendship: f,
          onAdd: () => _sendRequest(p),
          onAccept: f == null ? null : () => _accept(f),
          onReject: f == null ? null : () => _reject(f),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        style: const TextStyle(color: WhatsAppCallTheme.strongText),
        decoration: InputDecoration(
          hintText: 'Chercher un ami par prénom',
          hintStyle: const TextStyle(color: WhatsAppCallTheme.subtleText),
          filled: true,
          fillColor: WhatsAppCallTheme.bar,
          prefixIcon: const Icon(Icons.search, color: WhatsAppCallTheme.subtleText),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: WhatsAppCallTheme.subtleText),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _SearchIntro extends StatelessWidget {
  const _SearchIntro();

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
              child: const Icon(Icons.search, color: WhatsAppCallTheme.subtleText, size: 34),
            ),
            const SizedBox(height: 18),
            const Text(
              'Trouve un ami par son prénom',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tape les premières lettres de son prénom — la recherche est insensible à la casse.',
              textAlign: TextAlign.center,
              style: TextStyle(color: WhatsAppCallTheme.subtleText, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingRequestsSection extends StatelessWidget {
  const _IncomingRequestsSection({
    required this.requests,
    required this.onAccept,
    required this.onReject,
  });

  final List<IncomingFriendRequest> requests;
  final ValueChanged<Friendship> onAccept;
  final ValueChanged<Friendship> onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WhatsAppCallTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active,
                  size: 18,
                  color: WhatsAppCallTheme.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  'Invitations reçues (${requests.length})',
                  style: const TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          for (final req in requests)
            _IncomingRequestTile(
              request: req,
              onAccept: () => onAccept(req.friendship),
              onReject: () => onReject(req.friendship),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _IncomingRequestTile extends StatelessWidget {
  const _IncomingRequestTile({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  final IncomingFriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final p = request.requester;
    final name = p?.displayName.isNotEmpty == true
        ? p!.displayName
        : (p?.handle.isNotEmpty == true ? '@${p!.handle}' : 'Inconnu');
    final lang = p != null ? findLanguageByCode(p.language) : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      child: Row(
        children: [
          ProfileAvatar(
            displayName: name,
            avatarUrl: p?.avatarUrl,
            avatarColorHex: p?.avatarColor,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lang != null
                      ? '${lang.flag}  ${lang.label} · veut être ami'
                      : 'veut être ami',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(
                    color: WhatsAppCallTheme.subtleText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CircleAction(
            icon: Icons.close,
            tooltip: 'Refuser',
            color: WhatsAppCallTheme.danger,
            onTap: onReject,
          ),
          const SizedBox(width: 6),
          _CircleAction(
            icon: Icons.check,
            tooltip: 'Accepter',
            color: WhatsAppCallTheme.accent,
            onTap: onAccept,
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.status,
    required this.friendship,
    required this.onAdd,
    required this.onAccept,
    required this.onReject,
  });

  final RemoteProfile profile;
  final FriendshipStatus status;
  final Friendship? friendship;
  final VoidCallback onAdd;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final lang = findLanguageByCode(profile.sourceLang);
    final name = profile.firstName.isNotEmpty
        ? profile.firstName
        : (profile.handle.isNotEmpty ? '@${profile.handle}' : 'Sans nom');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: WhatsAppCallTheme.bar,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // 1. Avatar — fixed 44x44
            ProfileAvatar(
              displayName: profile.displayName,
              avatarUrl: profile.avatarUrl,
              avatarColorHex: profile.avatarColor,
              size: 44,
            ),
            const SizedBox(width: 12),
            // 2. Name + language — takes remaining space
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
                        : (profile.handle.isNotEmpty ? '@${profile.handle}' : ''),
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
            const SizedBox(width: 8),
            // 3. Action — always icon-only so the width is deterministic.
            _actionForStatus(),
          ],
        ),
      ),
    );
  }

  Widget _actionForStatus() {
    switch (status) {
      case FriendshipStatus.none:
      case FriendshipStatus.rejected:
        return _CircleAction(
          icon: Icons.person_add,
          tooltip: 'Ajouter',
          color: WhatsAppCallTheme.accent,
          onTap: onAdd,
        );
      case FriendshipStatus.pendingOutgoing:
        return _CircleAction(
          icon: Icons.hourglass_top,
          tooltip: 'En attente',
          color: WhatsAppCallTheme.subtleText,
          onTap: null,
        );
      case FriendshipStatus.pendingIncoming:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CircleAction(
              icon: Icons.close,
              tooltip: 'Refuser',
              color: WhatsAppCallTheme.danger,
              onTap: onReject,
            ),
            const SizedBox(width: 6),
            _CircleAction(
              icon: Icons.check,
              tooltip: 'Accepter',
              color: WhatsAppCallTheme.accent,
              onTap: onAccept,
            ),
          ],
        );
      case FriendshipStatus.accepted:
        return _CircleAction(
          icon: Icons.check_circle,
          tooltip: 'Ami',
          color: WhatsAppCallTheme.accent,
          onTap: null,
        );
    }
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: disabled
            ? WhatsAppCallTheme.bubbleIncoming
            : color.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: disabled ? WhatsAppCallTheme.subtleText : color),
          ),
        ),
      ),
    );
  }
}

