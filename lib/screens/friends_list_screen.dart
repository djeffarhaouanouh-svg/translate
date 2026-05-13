import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/device_id.dart';
import '../services/friendship_api.dart';
import '../services/languages.dart';
import '../services/profile_api.dart';
import '../theme/whatsapp_call_theme.dart';

/// List of accounts behind the Followers / Following counts on ProfileScreen.
/// Each row shows the peer's avatar + name + language. When viewing
/// followers, a "S'abonner" button appears for anyone the user does not
/// already follow back, so the relation can be made mutual in one tap.
class FriendsListScreen extends StatefulWidget {
  const FriendsListScreen({super.key, required this.direction});

  final FriendDirection direction;

  @override
  State<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  String _myId = '';
  List<RemoteProfile> _peers = const [];
  Set<String> _myFollowingIds = const {};
  Set<String> _myFollowingPendingIds = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = await DeviceId.getOrCreate();
      final peers = await FriendshipApi.fetchAcceptedPeers(
        meId: id,
        direction: widget.direction,
      );
      final mine = await FriendshipApi.fetchMine(id);
      final followingAccepted = <String>{};
      final followingPending = <String>{};
      for (final f in mine) {
        if (f.requester == id) {
          if (f.status == 'accepted') {
            followingAccepted.add(f.addressee);
          } else if (f.status == 'pending') {
            followingPending.add(f.addressee);
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _myId = id;
        _peers = peers;
        _myFollowingIds = followingAccepted;
        _myFollowingPendingIds = followingPending;
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

  Future<void> _followBack(RemoteProfile peer) async {
    try {
      final f = await FriendshipApi.sendRequest(meId: _myId, peerId: peer.id);
      if (!mounted) return;
      if (f == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Supabase non configuré.")),
        );
        return;
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.direction == FriendDirection.followers
        ? AppStrings.t('profile_followers')
        : AppStrings.t('profile_following');
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _load,
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
    if (_peers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            widget.direction == FriendDirection.followers
                ? 'Personne ne te suit encore.'
                : 'Tu ne suis personne encore.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: WhatsAppCallTheme.subtleText, fontSize: 14),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _peers.length,
      itemBuilder: (ctx, i) {
        final p = _peers[i];
        final showFollowBack =
            widget.direction == FriendDirection.followers &&
                !_myFollowingIds.contains(p.id) &&
                !_myFollowingPendingIds.contains(p.id);
        final showPendingPill =
            widget.direction == FriendDirection.followers &&
                _myFollowingPendingIds.contains(p.id);
        return _FriendRow(
          profile: p,
          trailing: showFollowBack
              ? _FollowBackButton(onTap: () => _followBack(p))
              : showPendingPill
                  ? const _MutedPill(label: 'En attente', icon: Icons.hourglass_top)
                  : const _MutedPill(label: 'Ami', icon: Icons.check_circle),
        );
      },
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.profile, required this.trailing});

  final RemoteProfile profile;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final lang = findLanguageByCode(profile.language);
    final name = profile.displayName.isNotEmpty
        ? profile.displayName
        : (profile.handle.isNotEmpty ? '@${profile.handle}' : 'Sans nom');
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: WhatsAppCallTheme.bar,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
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
                  fontSize: 18,
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
                  if (lang != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${lang.flag}  ${lang.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: const TextStyle(
                        color: WhatsAppCallTheme.subtleText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _FollowBackButton extends StatelessWidget {
  const _FollowBackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WhatsAppCallTheme.accent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_alt_1, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'S\'abonner',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MutedPill extends StatelessWidget {
  const _MutedPill({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bubbleIncoming,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: WhatsAppCallTheme.subtleText),
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
