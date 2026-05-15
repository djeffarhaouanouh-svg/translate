import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/device_id.dart';
import '../services/languages.dart';
import '../services/profile_api.dart';
import '../services/supabase_service.dart';
import '../services/user_prefs.dart';
import '../theme/whatsapp_call_theme.dart';

/// First-run flow: first name + the user's own spoken language (stored locally).
/// The remote participant's language is discovered from their LiveKit metadata
/// at call time — no manual entry needed.
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
  final _bioCtrl = TextEditingController();
  String? _selectedLang;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// Local UserPrefs first (instant), then — in editing mode — overlay with
  /// the latest Supabase row so the field reflects what other users see, not
  /// just what was last typed on this device.
  Future<void> _prefill() async {
    final snap = await UserPrefs.loadProfile();
    if (!mounted) return;
    if (snap != null) {
      setState(() {
        _nameCtrl.text = snap.firstName;
        final stored = snap.sourceLang.trim();
        if (stored.isNotEmpty && findLanguageByCode(stored) != null) {
          _selectedLang = findLanguageByCode(stored)!.code;
        }
      });
    }
    if (!widget.editing || !isSupabaseReady) return;
    try {
      final uid = await DeviceId.getOrCreate();
      final remote = await ProfileApi.fetchById(uid);
      if (!mounted || remote == null) return;
      setState(() {
        if (remote.displayName.trim().isNotEmpty) {
          _nameCtrl.text = remote.displayName;
        }
        if (remote.bio.isNotEmpty) {
          _bioCtrl.text = remote.bio;
        }
        if (remote.language.trim().isNotEmpty &&
            findLanguageByCode(remote.language) != null) {
          _selectedLang = remote.language;
        }
      });
    } catch (_) {}
  }

  /// Flip the UI to the newly chosen language immediately, even while the
  /// user is still on the language picker, so the "Save / Get started"
  /// button label updates in real time.
  void _onLanguageSelected(String code) {
    AppStrings.setFromCode(code);
    setState(() => _selectedLang = code);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('onb_need_name'))),
      );
      return;
    }
    if (_selectedLang == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('onb_need_language'))),
      );
      return;
    }
    await UserPrefs.completeOnboarding(
      firstName: name,
      sourceLang: _selectedLang!,
      // Other person's language is now discovered live from their metadata.
      targetLang: '',
    );
    // Make the rest of the app speak the user's chosen language right away.
    AppStrings.setFromCode(_selectedLang!);
    // Only push to Supabase if we already have an auth user — otherwise
    // the FK `profiles.id REFERENCES auth.users(id)` would fail. The
    // initial onboarding runs pre-login by design; the upsert happens
    // post-signin from `main.dart::_hydrateAuthedSession`.
    if (AuthService.isAuthenticated) {
      final deviceId = await DeviceId.getOrCreate();
      await ProfileApi.upsertMyProfile(
        deviceId: deviceId,
        displayName: name,
        language: _selectedLang!,
      );
      // Bio is only edited via this screen in editing mode (the first-run
      // welcome flow keeps the form to name + language). Persist it
      // separately because upsertMyProfile doesn't carry the bio column.
      if (widget.editing) {
        await ProfileApi.updateMyBio(
          userId: deviceId,
          bio: _bioCtrl.text.trim(),
        );
      }
    }
    if (!mounted) return;
    widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.editing) {
      return Scaffold(
        backgroundColor: WhatsAppCallTheme.scaffold,
        appBar: AppBar(
          title: Text(AppStrings.t('onb_profile_title')),
          backgroundColor: WhatsAppCallTheme.scaffold,
          foregroundColor: WhatsAppCallTheme.strongText,
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
                  decoration: InputDecoration(
                    labelText: AppStrings.t('onb_first_name_label'),
                    // The label floats up because the controller is
                    // pre-populated by `_prefill`; the hint is only seen on
                    // a brand-new account that landed here directly.
                    hintText: AppStrings.t('onb_first_name_hint'),
                    prefixIcon: const Icon(Icons.badge_outlined,
                        color: WhatsAppCallTheme.subtleText),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _bioCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: profileBioMaxLength,
                  maxLines: 3,
                  minLines: 2,
                  style: const TextStyle(color: WhatsAppCallTheme.strongText),
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    hintText: 'Présente-toi en 2 mots ✏️',
                    prefixIcon: Icon(Icons.short_text,
                        color: WhatsAppCallTheme.subtleText),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.t('onb_language_picker_label'),
                  style: const TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                _LanguageGrid(
                  selected: _selectedLang,
                  onSelect: _onLanguageSelected,
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _finish,
                  child: Text(AppStrings.t('onb_save')),
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
                          SnackBar(content: Text(AppStrings.t('onb_need_name'))),
                        );
                        return;
                      }
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                      );
                    },
                  ),
                  _StepLanguage(
                    selected: _selectedLang,
                    onSelect: _onLanguageSelected,
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
      color: WhatsAppCallTheme.scaffold,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              page == 0
                  ? AppStrings.t('onb_welcome_title')
                  : AppStrings.t('onb_language_title'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              page == 0
                  ? AppStrings.t('onb_welcome_subtitle')
                  : AppStrings.t('onb_language_subtitle'),
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
            decoration: InputDecoration(
              labelText: AppStrings.t('onb_first_name_label'),
              hintText: AppStrings.t('onb_first_name_hint'),
              prefixIcon: const Icon(Icons.badge_outlined, color: WhatsAppCallTheme.subtleText),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: onNext,
            child: Text(AppStrings.t('onb_next')),
          ),
        ],
      ),
    );
  }
}

class _StepLanguage extends StatelessWidget {
  const _StepLanguage({
    required this.selected,
    required this.onSelect,
    required this.onBack,
    required this.onFinish,
  });

  final String? selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LanguageGrid(selected: selected, onSelect: onSelect),
          const SizedBox(height: 12),
          Text(
            AppStrings.t('onb_translation_help'),
            style: const TextStyle(color: WhatsAppCallTheme.subtleText, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              TextButton(onPressed: onBack, child: Text(AppStrings.t('onb_back'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onFinish,
                  child: Text(AppStrings.t('onb_finish')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageGrid extends StatelessWidget {
  const _LanguageGrid({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final lang in supportedLanguages)
          _LanguageChip(
            language: lang,
            selected: lang.code == selected,
            onTap: () => onSelect(lang.code),
          ),
      ],
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? WhatsAppCallTheme.accent : WhatsAppCallTheme.bar;
    final border = selected ? WhatsAppCallTheme.accent : Colors.white.withValues(alpha: 0.08);
    final fg = selected ? Colors.white : WhatsAppCallTheme.strongText;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(language.flag, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Text(
                language.label,
                style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
