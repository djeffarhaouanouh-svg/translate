import 'package:flutter/material.dart';

import '../theme/whatsapp_call_theme.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const _profiles = <_DemoProfile>[
    _DemoProfile(name: 'Alex', age: 24, flag: '🇫🇷', bio: "Sport, voyages, café le matin."),
    _DemoProfile(name: 'Mateo', age: 26, flag: '🇪🇸', bio: "Surf, photo argentique, vinyles."),
    _DemoProfile(name: 'Jordan', age: 22, flag: '🇺🇸', bio: "Gym tous les jours · DM ouverts."),
    _DemoProfile(name: 'Luca', age: 28, flag: '🇮🇹', bio: "Architecte. Tatouages. Espresso."),
    _DemoProfile(name: 'Noah', age: 25, flag: '🇧🇪', bio: "Foot, séries, dimanche brunch."),
  ];

  int _topIndex = 0;
  final Set<String> _liked = <String>{};

  void _advance() {
    if (_topIndex >= _profiles.length) return;
    setState(() => _topIndex += 1);
  }

  void _toggleLike(String name) {
    setState(() {
      if (!_liked.add(name)) _liked.remove(name);
    });
  }

  void _addFriend(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Demande envoyée à $name'),
        duration: const Duration(seconds: 2),
        backgroundColor: WhatsAppCallTheme.bar,
      ),
    );
  }

  void _reset() {
    setState(() => _topIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _DiscoverHeader(),
            Expanded(
              child: _topIndex >= _profiles.length
                  ? _Empty(onReset: _reset)
                  : _buildStack(),
            ),
            // Spacer for the floating bottom nav.
            SizedBox(height: 12 + MediaQuery.paddingOf(context).bottom + 64),
          ],
        ),
      ),
    );
  }

  Widget _buildStack() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Up to 2 background cards, drawn first (bottom of z-order).
          for (int depth = 2; depth >= 1; depth--)
            if (_topIndex + depth < _profiles.length)
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(0, depth * 14.0),
                  child: Transform.scale(
                    scale: 1 - depth * 0.05,
                    child: IgnorePointer(
                      child: _ProfileCard(
                        profile: _profiles[_topIndex + depth],
                        liked: false,
                        onAdd: () {},
                        onToggleLike: () {},
                      ),
                    ),
                  ),
                ),
              ),
          // Top card — no swipe. Use the Ajouter / heart buttons to advance.
          Positioned.fill(
            child: _ProfileCard(
              profile: _profiles[_topIndex],
              liked: _liked.contains(_profiles[_topIndex].name),
              onAdd: () {
                _addFriend(_profiles[_topIndex].name);
                _advance();
              },
              onToggleLike: () => _toggleLike(_profiles[_topIndex].name),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoProfile {
  const _DemoProfile({
    required this.name,
    required this.age,
    required this.flag,
    required this.bio,
  });

  final String name;
  final int age;
  final String flag;
  final String bio;
}

class _DiscoverHeader extends StatelessWidget {
  const _DiscoverHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          const Text(
            'Discover',
            style: TextStyle(
              color: WhatsAppCallTheme.strongText,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: WhatsAppCallTheme.bar,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune, size: 16, color: WhatsAppCallTheme.subtleText),
                SizedBox(width: 6),
                Text(
                  'Filtres',
                  style: TextStyle(
                    color: WhatsAppCallTheme.subtleText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.liked,
    required this.onAdd,
    required this.onToggleLike,
  });

  final _DemoProfile profile;
  final bool liked;
  final VoidCallback onAdd;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: WhatsAppCallTheme.bar),
          Image.asset(
            'assets/demo_profile.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.85),
                  ],
                  stops: const [0.45, 0.65, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${profile.age}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(profile.flag, style: const TextStyle(fontSize: 22)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  profile.bio,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _AddButton(onTap: onAdd),
                    const Spacer(),
                    _LikeHeart(liked: liked, onTap: onToggleLike),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WhatsAppCallTheme.accent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_add_alt_1, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Ajouter',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LikeHeart extends StatelessWidget {
  const _LikeHeart({required this.liked, required this.onTap});
  final bool liked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF3B5C);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: liked ? red.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
          border: Border.all(
            color: liked ? red : Colors.white.withValues(alpha: 0.20),
            width: liked ? 2 : 1,
          ),
        ),
        child: Icon(
          liked ? Icons.favorite : Icons.favorite_border,
          size: liked ? 28 : 24,
          color: liked ? red : Colors.white,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onReset});
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
              child: const Icon(Icons.favorite_border,
                  color: WhatsAppCallTheme.subtleText, size: 34),
            ),
            const SizedBox(height: 18),
            const Text(
              "C'est tout pour aujourd'hui",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh, color: WhatsAppCallTheme.accent),
              label: const Text(
                'Recommencer',
                style: TextStyle(color: WhatsAppCallTheme.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
