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
            Expanded(child: _topIndex >= _profiles.length ? _Empty(onReset: _reset) : _buildStack()),
            // Bottom controls — guaranteed to advance the card on every platform.
            Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 8, 24, 24 + MediaQuery.paddingOf(context).bottom + 64),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundButton(
                    icon: Icons.close,
                    color: Colors.white,
                    bg: WhatsAppCallTheme.bar,
                    onTap: _topIndex < _profiles.length ? _advance : null,
                  ),
                  _RoundButton(
                    icon: Icons.favorite,
                    color: Colors.white,
                    bg: const Color(0xFFFF3B5C),
                    onTap: _topIndex < _profiles.length
                        ? () {
                            _toggleLike(_profiles[_topIndex].name);
                            _advance();
                          }
                        : null,
                  ),
                ],
              ),
            ),
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
                      child: _ProfileCard(profile: _profiles[_topIndex + depth]),
                    ),
                  ),
                ),
              ),
          // Top card — Dismissible handles the swipe (works on web & mobile).
          Dismissible(
            key: ValueKey(_topIndex),
            direction: DismissDirection.horizontal,
            // Trigger at 25% of the card width — Tinder-ish.
            dismissThresholds: const {
              DismissDirection.horizontal: 0.25,
              DismissDirection.startToEnd: 0.25,
              DismissDirection.endToStart: 0.25,
            },
            onDismissed: (dir) {
              if (dir == DismissDirection.startToEnd) {
                _liked.add(_profiles[_topIndex].name);
              }
              _advance();
            },
            child: _ProfileCard(profile: _profiles[_topIndex]),
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Text(
            'Discover',
            style: TextStyle(
              color: WhatsAppCallTheme.strongText,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final _DemoProfile profile;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Solid base color so the card is opaque even when the asset image
          // is missing (web build doesn't bundle assets/ yet).
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color bg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Icon(icon, color: color, size: 30),
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
