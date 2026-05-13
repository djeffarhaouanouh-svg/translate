import 'dart:async';

import 'package:flutter/material.dart';

import '../services/device_id.dart';
import '../services/friendship_api.dart';
import '../services/languages.dart';
import '../services/profile_api.dart';
import '../services/supabase_service.dart';
import '../theme/whatsapp_call_theme.dart';

/// Onglet 1 — find friends by their first name. Each result row shows their
/// language flag and a contextual action button based on the existing
/// friendship state (none / pending / accepted).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryCtrl = TextEditingController();
  Timer? _debounce;

  String _myId = '';
  List<RemoteProfile> _results = const [];
  List<Friendship> _myFriendships = const [];
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final id = await DeviceId.getOrCreate();
    if (!mounted) return;
    setState(() => _myId = id);
    await _refreshFriendships();
  }

  Future<void> _refreshFriendships() async {
    if (_myId.isEmpty) return;
    try {
      final list = await FriendshipApi.fetchMine(_myId);
      if (!mounted) return;
      setState(() => _myFriendships = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Impossible de charger les amitiés: $e');
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
    final f = await FriendshipApi.sendRequest(meId: _myId, peerId: peer.id);
    if (!mounted) return;
    if (f == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'envoyer la demande.')),
      );
      return;
    }
    await _refreshFriendships();
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
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      appBar: AppBar(title: const Text('Rechercher')),
      body: Column(
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
          Expanded(child: _buildBody()),
        ],
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
    final initial = profile.firstName.isNotEmpty
        ? profile.firstName.characters.first.toUpperCase()
        : '?';

    final name = profile.firstName.isNotEmpty
        ? profile.firstName
        : (profile.handle.isNotEmpty ? '@${profile.handle}' : 'Sans nom');
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: WhatsAppCallTheme.bar,
            child: Text(
              initial,
              style: const TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontWeight: FontWeight.w600,
              ),
            ),
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
                if (lang != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${lang.flag}  Parle ${lang.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      color: WhatsAppCallTheme.subtleText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _actionForStatus(),
        ],
      ),
    );
  }

  Widget _actionForStatus() {
    switch (status) {
      case FriendshipStatus.none:
      case FriendshipStatus.rejected:
        return FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Ajouter'),
          style: FilledButton.styleFrom(
            backgroundColor: WhatsAppCallTheme.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        );
      case FriendshipStatus.pendingOutgoing:
        return const _StatusPill(label: 'En attente', icon: Icons.hourglass_top);
      case FriendshipStatus.pendingIncoming:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Refuser',
              onPressed: onReject,
              icon: const Icon(Icons.close, color: WhatsAppCallTheme.danger),
            ),
            IconButton(
              tooltip: 'Accepter',
              onPressed: onAccept,
              icon: const Icon(Icons.check, color: WhatsAppCallTheme.accent),
            ),
          ],
        );
      case FriendshipStatus.accepted:
        return const _StatusPill(label: 'Ami', icon: Icons.check_circle);
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: WhatsAppCallTheme.subtleText),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: WhatsAppCallTheme.subtleText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
