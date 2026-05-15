import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/whatsapp_call_theme.dart';
import 'search_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  static const _profiles = <_DemoProfile>[
    _DemoProfile(name: 'Alex', age: 24, flag: '🇫🇷', bio: "Sport, voyages, café le matin."),
    _DemoProfile(name: 'Mateo', age: 26, flag: '🇪🇸', bio: "Surf, photo argentique, vinyles."),
    _DemoProfile(name: 'Jordan', age: 22, flag: '🇺🇸', bio: "Gym tous les jours · DM ouverts."),
    _DemoProfile(name: 'Luca', age: 28, flag: '🇮🇹', bio: "Architecte. Tatouages. Espresso."),
    _DemoProfile(name: 'Noah', age: 25, flag: '🇧🇪', bio: "Foot, séries, dimanche brunch."),
  ];

  int _topIndex = 0;

  // Drag state for the top card.
  Offset _drag = Offset.zero;
  Size _cardSize = Size.zero;
  late final AnimationController _ctrl;
  Offset _animFrom = Offset.zero;
  Offset _animTo = Offset.zero;
  bool _isFlying = false; // true => on completion, advance the index

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )
      ..addListener(() {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        setState(() => _drag = Offset.lerp(_animFrom, _animTo, t)!);
      })
      ..addStatusListener((s) {
        if (s != AnimationStatus.completed) return;
        if (_isFlying) {
          setState(() {
            _topIndex += 1;
            _drag = Offset.zero;
            _isFlying = false;
          });
        }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails _) {
    if (_ctrl.isAnimating) {
      _ctrl.stop();
      if (_isFlying) {
        _topIndex += 1;
        _isFlying = false;
        _drag = Offset.zero;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    final w = _cardSize.width;
    final vx = d.velocity.pixelsPerSecond.dx;
    // Trigger if dragged ~25% of the card OR flicked fast enough.
    final triggered = (w > 0 && _drag.dx.abs() > w * 0.25) || vx.abs() > 500;
    if (triggered) {
      _flyOff(vx.abs() > 500 ? (vx >= 0 ? 1 : -1) : (_drag.dx >= 0 ? 1 : -1));
    } else {
      _springBack();
    }
  }

  void _flyOff(int direction) {
    _animFrom = _drag;
    _animTo = Offset(direction * (_cardSize.width + 200), _drag.dy + 80);
    _isFlying = true;
    _ctrl
      ..duration = const Duration(milliseconds: 240)
      ..forward(from: 0);
  }

  void _springBack() {
    _animFrom = _drag;
    _animTo = Offset.zero;
    _isFlying = false;
    _ctrl
      ..duration = const Duration(milliseconds: 220)
      ..forward(from: 0);
  }

  void _advance() {
    if (_topIndex >= _profiles.length) return;
    setState(() => _topIndex += 1);
  }

  void _sendHello(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('👋 envoyé à $name'),
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
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          _cardSize = Size(constraints.maxWidth, constraints.maxHeight);
          final w = _cardSize.width;
          final rotation = w == 0 ? 0.0 : (_drag.dx / w) * 0.25;
          return Stack(
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
                            onAdd: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
              // Top card — draggable horizontally. GestureDetector wraps the
              // Transform-displaced card so the hit area follows the visual.
              Positioned.fill(
                child: Transform.translate(
                  offset: _drag,
                  child: Transform.rotate(
                    angle: rotation,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      child: _ProfileCard(
                        profile: _profiles[_topIndex],
                        onAdd: () {
                          _sendHello(_profiles[_topIndex].name);
                          _advance();
                        },
                      ),
                    ),
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

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
    );
  }

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
          // Compact search pill — opens the real SearchScreen on tap.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openSearch(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: WhatsAppCallTheme.bar,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search, size: 16, color: WhatsAppCallTheme.subtleText),
                  SizedBox(width: 6),
                  Text(
                    'Chercher',
                    style: TextStyle(
                      color: WhatsAppCallTheme.subtleText,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
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
    required this.onAdd,
  });

  final _DemoProfile profile;
  final VoidCallback onAdd;

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
                Align(
                  alignment: Alignment.centerLeft,
                  child: _AddButton(onTap: onAdd),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Envoyer 👋" — the emoji scales up briefly and the device gives a short
/// haptic tap on press. Parent then advances to the next card.
class _AddButton extends StatefulWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // Scale: 1 → 1.7 → 1, with overshoot.
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.7)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 1.7, end: 1.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 60),
    ]).animate(_ctrl);
    // Wave: -15° → +15° → -10° → 0 over the burst.
    _rotate = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.26), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -0.26, end: 0.26), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.26, end: -0.17), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -0.17, end: 0.0), weight: 25),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onPress() {
    HapticFeedback.mediumImpact();
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WhatsAppCallTheme.accent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _onPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Envoyer ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              AnimatedBuilder(
                animation: _ctrl,
                builder: (_, _) => Transform.rotate(
                  angle: _rotate.value,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: const Text('👋', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
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
