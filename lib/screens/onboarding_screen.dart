import 'package:flutter/material.dart';

import '../services/user_prefs.dart';
import '../theme/whatsapp_call_theme.dart';

/// First-run flow: first name + translation languages (stored locally).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onCompleted,
    this.editing = false,
  });

  final VoidCallback onCompleted;

  /// When true, opened from settings to update profile (does not flip onboarding flag off).
  final bool editing;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _nameCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final snap = await UserPrefs.loadProfile();
    if (!mounted || snap == null) return;
    setState(() {
      _nameCtrl.text = snap.firstName;
      _sourceCtrl.text = snap.sourceLang;
      _targetCtrl.text = snap.targetLang;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _sourceCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your first name.')),
      );
      return;
    }
    await UserPrefs.completeOnboarding(
      firstName: name,
      sourceLang: _sourceCtrl.text.trim(),
      targetLang: _targetCtrl.text.trim(),
    );
    if (!mounted) return;
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.editing) {
      return Scaffold(
        backgroundColor: WhatsAppCallTheme.scaffold,
        appBar: AppBar(
          title: const Text('Your profile'),
          backgroundColor: WhatsAppCallTheme.waHeader,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: WhatsAppCallTheme.strongText),
                  decoration: const InputDecoration(
                    labelText: 'First name',
                    hintText: 'e.g. Alex',
                    prefixIcon: Icon(Icons.badge_outlined, color: WhatsAppCallTheme.subtleText),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _sourceCtrl,
                  autocorrect: false,
                  style: const TextStyle(color: WhatsAppCallTheme.strongText),
                  decoration: const InputDecoration(
                    labelText: 'Your spoken language (BCP-47)',
                    hintText: 'fr',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _targetCtrl,
                  autocorrect: false,
                  style: const TextStyle(color: WhatsAppCallTheme.strongText),
                  decoration: const InputDecoration(
                    labelText: "The other person's language (BCP-47)",
                    hintText: 'en',
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _finish,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OnboardingHeader(page: _page),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _StepWelcome(
                    nameCtrl: _nameCtrl,
                    onNext: () {
                      if (_nameCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter your first name.')),
                        );
                        return;
                      }
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      );
                    },
                  ),
                  _StepLanguages(
                    sourceCtrl: _sourceCtrl,
                    targetCtrl: _targetCtrl,
                    onBack: () => _pageController.previousPage(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                    ),
                    onFinish: _finish,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WhatsAppCallTheme.waHeader,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              page == 0 ? 'Welcome' : 'Translation',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              page == 0
                  ? 'Tell us how to call you in calls.'
                  : 'These map to OpenAI Realtime later: your language vs theirs (bidirectional).',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _Dot(active: page == 0),
                const SizedBox(width: 8),
                _Dot(active: page == 1),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 22 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _StepWelcome extends StatelessWidget {
  const _StepWelcome({
    required this.nameCtrl,
    required this.onNext,
  });

  final TextEditingController nameCtrl;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: WhatsAppCallTheme.strongText, fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'First name',
              hintText: 'e.g. Alex',
              prefixIcon: Icon(Icons.badge_outlined, color: WhatsAppCallTheme.subtleText),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: onNext,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class _StepLanguages extends StatelessWidget {
  const _StepLanguages({
    required this.sourceCtrl,
    required this.targetCtrl,
    required this.onBack,
    required this.onFinish,
  });

  final TextEditingController sourceCtrl;
  final TextEditingController targetCtrl;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: sourceCtrl,
            autocorrect: false,
            style: const TextStyle(color: WhatsAppCallTheme.strongText),
            decoration: const InputDecoration(
              labelText: 'Your spoken language (BCP-47)',
              hintText: 'fr',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: targetCtrl,
            autocorrect: false,
            style: const TextStyle(color: WhatsAppCallTheme.strongText),
            decoration: const InputDecoration(
              labelText: "The other person's language (BCP-47)",
              hintText: 'en',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Example: you choose fr + en — you speak French; the other speaks English. '
            'Later, OpenAI will translate your voice to English for them and their voice to French for you. '
            'Leave blank if you only want plain video calls for now.',
            style: TextStyle(color: WhatsAppCallTheme.subtleText, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              TextButton(onPressed: onBack, child: const Text('Back')),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onFinish,
                  child: const Text('Get started'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
