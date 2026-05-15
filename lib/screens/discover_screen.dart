import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/whatsapp_call_theme.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  static const _demoProfiles = <_DemoProfile>[
    _DemoProfile(name: 'Alex', age: 24, distanceKm: 3, flag: '🇫🇷', bio: "Sport, voyages, café le matin."),
    _DemoProfile(name: 'Mateo', age: 26, distanceKm: 8, flag: '🇪🇸', bio: "Surf, photo argentique, vinyles."),
    _DemoProfile(name: 'Jordan', age: 22, distanceKm: 2, flag: '🇺🇸', bio: "Gym tous les jours · DM ouverts."),
    _DemoProfile(name: 'Luca', age: 28, distanceKm: 12, flag: '🇮🇹', bio: "Architecte. Tatouages. Espresso."),
    _DemoProfile(name: 'Noah', age: 25, distanceKm: 5, flag: '🇧🇪', bio: "Foot, séries, dimanche brunch."),
  ];

  // Index of the top visible profile in _demoProfiles. Incrementing this
  // is what "consumes" a card — no list mutation, so there's nothing to
  // race with the animation lifecycle.
  int _topIndex = 0;
  final Set<String> _liked = <String>{};

  // Debug counters — surfaced in the on-screen banner.
  int _dbgPanStarts = 0;
  int _dbgPanEnds = 0;
  int _dbgFlyOffs = 0;
  int _dbgStatusCompleted = 0;
  String _dbgLastEnd = '-';

  Offset _drag = Offset.zero;
  bool _dragging = false;
  Size _cardSize = Size.zero;

  // Single controller drives both fly-off and spring-back. _isFlying tells
  // the status listener which one just finished so it knows whether to pop
  // the top card.
  late final AnimationController _ctrl;
  Offset _animFrom = Offset.zero;
  Offset _animTo = Offset.zero;
  bool _isFlying = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
  }

  int get _remaining => _demoProfiles.length - _topIndex;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTick() {
    final t = Curves.easeOutCubic.transform(_ctrl.value);
    setState(() => _drag = Offset.lerp(_animFrom, _animTo, t)!);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _dbgStatusCompleted += 1;
    if (_isFlying) {
      setState(() {
        if (_topIndex < _demoProfiles.length) _topIndex += 1;
        _drag = Offset.zero;
        _isFlying = false;
        _dragging = false;
      });
    } else {
      setState(() => _dragging = false);
    }
  }

  double get _screenWidth =>
      _cardSize.width == 0 ? MediaQuery.of(context).size.width : _cardSize.width;

  double get _swipeProgress {
    final w = _screenWidth;
    if (w == 0) return 0;
    return (_drag.dx / (w * 0.35)).clamp(-1.0, 1.0);
  }

  // Pointer-based swipe handling. Listener doesn't enter the gesture arena
  // so it can't be stolen by InkWells / parent scrollables.
  int? _activePointer;
  Offset _pointerStart = Offset.zero;
  DateTime _pointerStartTime = DateTime.now();

  void _onPointerDown(PointerDownEvent e) {
    if (_activePointer != null) return;
    _activePointer = e.pointer;
    _pointerStart = e.position;
    _pointerStartTime = DateTime.now();
    _dbgPanStarts += 1;
    if (_ctrl.isAnimating) {
      _ctrl.stop();
      if (_isFlying && _topIndex < _demoProfiles.length) _topIndex += 1;
      _isFlying = false;
      _drag = Offset.zero;
    }
    setState(() => _dragging = true);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.pointer != _activePointer) return;
    setState(() => _drag = e.position - _pointerStart);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    _dbgPanEnds += 1;
    final dt = DateTime.now().difference(_pointerStartTime).inMilliseconds;
    final velocityX = dt > 0 ? (_drag.dx / dt) * 1000 : 0.0;
    final triggered =
        _swipeProgress.abs() >= 0.35 || velocityX.abs() > 400;
    _dbgLastEnd = 'dx=${_drag.dx.toStringAsFixed(0)} '
        'vx=${velocityX.toStringAsFixed(0)} '
        'trig=$triggered';
    if (triggered) {
      _dbgFlyOffs += 1;
      final direction = velocityX.abs() > 400
          ? (velocityX >= 0 ? 1 : -1)
          : (_drag.dx >= 0 ? 1 : -1);
      _flyOff(direction);
    } else {
      _springBack();
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (e.pointer != _activePointer) return;
    _activePointer = null;
    _springBack();
  }

  /// Debug-only: tap the card to force-advance. Lets us confirm that the
  /// index/render pipeline works even when gesture detection is broken.
  void _debugAdvance() {
    if (_topIndex >= _demoProfiles.length) return;
    setState(() => _topIndex += 1);
  }

  void _flyOff(int direction) {
    final w = _screenWidth;
    _animFrom = _drag;
    _animTo = Offset(direction * w * 1.6, _drag.dy + 120);
    _isFlying = true;
    _ctrl
      ..duration = const Duration(milliseconds: 280)
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

  void _resetStack() {
    setState(() {
      _topIndex = 0;
      _drag = Offset.zero;
    });
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
            // TEMP debug indicator.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DEBUG v3 · top=${_topIndex + 1}/${_demoProfiles.length}',
                    style: const TextStyle(
                      color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'starts=$_dbgPanStarts ends=$_dbgPanEnds '
                    'flyoffs=$_dbgFlyOffs done=$_dbgStatusCompleted',
                    style: const TextStyle(color: Colors.amber, fontSize: 11),
                  ),
                  Text(
                    'last: $_dbgLastEnd',
                    style: const TextStyle(color: Colors.amber, fontSize: 11),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  _cardSize = Size(constraints.maxWidth, constraints.maxHeight);
                  if (_remaining <= 0) {
                    return _EmptyState(onReset: _resetStack);
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    // Two layers wrapping the same Stack:
                    //   - Listener catches raw pointer events (works on web mouse
                    //     even when the gesture arena is contested).
                    //   - GestureDetector is a fallback for native pan gestures.
                    // Whichever fires first wins; both write to the same _drag.
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerCancel,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _debugAdvance,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            for (int i = math.min(2, _remaining - 1); i >= 0; i--)
                              _buildCardAt(i),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Spacer leaves room for the floating bottom nav.
            SizedBox(height: 12 + MediaQuery.paddingOf(context).bottom + 64),
          ],
        ),
      ),
    );
  }

  void _toggleLike(_DemoProfile profile) {
    setState(() {
      if (!_liked.add(profile.name)) _liked.remove(profile.name);
    });
  }

  void _addFriend(_DemoProfile profile) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Demande envoyée à ${profile.name}'),
        duration: const Duration(seconds: 2),
        backgroundColor: WhatsAppCallTheme.bar,
      ),
    );
  }

  Widget _buildCardAt(int stackIndex) {
    final profile = _demoProfiles[_topIndex + stackIndex];
    final isTop = stackIndex == 0;
    // Cards must have explicit dimensions — Image.asset alone has no
    // intrinsic size useful here, so without this they'd shrink to nothing.
    final card = SizedBox.expand(
      child: _ProfileCard(
        profile: profile,
        overlay: isTop && _dragging ? _swipeProgress : 0,
        liked: _liked.contains(profile.name),
        onAdd: () => _addFriend(profile),
        onToggleLike: () => _toggleLike(profile),
      ),
    );

    if (!isTop) {
      // Background cards: subtle scale + vertical offset that "rise" as the
      // top card is being swiped past threshold.
      final progress = _swipeProgress.abs();
      final depth = stackIndex.toDouble();
      final scale = 1 - 0.05 * depth + 0.05 * progress * (depth == 1 ? 1 : 0);
      final dy = 14 * depth - 14 * progress * (depth == 1 ? 1 : 0);
      return Transform.translate(
        offset: Offset(0, dy),
        child: Transform.scale(
          scale: scale.clamp(0.85, 1.0),
          child: IgnorePointer(child: card),
        ),
      );
    }

    final w = _screenWidth;
    final rotation = w == 0 ? 0.0 : (_drag.dx / w) * 0.35;
    return Transform.translate(
      offset: _drag,
      child: Transform.rotate(angle: rotation, child: card),
    );
  }
}

class _DemoProfile {
  const _DemoProfile({
    required this.name,
    required this.age,
    required this.distanceKm,
    required this.flag,
    required this.bio,
  });

  final String name;
  final int age;
  final int distanceKm;
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
    required this.overlay,
    required this.liked,
    required this.onAdd,
    required this.onToggleLike,
  });

  final _DemoProfile profile;

  /// -1..1 — negative for "nope", positive for "like". Drives the corner badge.
  final double overlay;

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
          // Solid base color so the card is opaque even when the asset image
          // is missing (web build doesn't bundle assets/ yet).
          ColoredBox(color: WhatsAppCallTheme.bar),
          Image.asset(
            'assets/demo_profile.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          // Bottom gradient for legibility of the name/bio overlay.
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
          // Like / Nope corner badges, opacity driven by swipe direction.
          Positioned(
            top: 28,
            left: 22,
            child: Transform.rotate(
              angle: -0.25,
              child: _StampBadge(
                label: 'LIKE',
                color: WhatsAppCallTheme.accent,
                opacity: overlay.clamp(0, 1).toDouble(),
              ),
            ),
          ),
          Positioned(
            top: 28,
            right: 22,
            child: Transform.rotate(
              angle: 0.25,
              child: _StampBadge(
                label: 'NOPE',
                color: WhatsAppCallTheme.danger,
                opacity: (-overlay).clamp(0, 1).toDouble(),
              ),
            ),
          ),
          // Info bar at the bottom.
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
                      child: Text(
                        profile.flag,
                        style: const TextStyle(fontSize: 22),
                      ),
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

class _StampBadge extends StatelessWidget {
  const _StampBadge({
    required this.label,
    required this.color,
    required this.opacity,
  });
  final String label;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 4),
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
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
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(liked),
                size: 24,
                color: liked ? red : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onReset});
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
            const SizedBox(height: 8),
            const Text(
              "Reviens plus tard pour découvrir d'autres profils.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: WhatsAppCallTheme.subtleText,
                  fontSize: 13,
                  height: 1.4),
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
