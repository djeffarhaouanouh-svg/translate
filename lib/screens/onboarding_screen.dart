import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/device_id.dart';
import '../services/languages.dart';
import '../services/profile_api.dart';
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
  String? _selectedLang;
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
      final stored = snap.sourceLang.trim();
      if (stored.isNotEmpty && findLanguageByCode(stored) != null) {
        _selectedLang = findLanguageByCode(stored)!.code;
      }
    });
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
    // Mirror to Supabase so other users can discover this profile in search.
    // Best-effort: failure here does not block onboarding.
    final deviceId = await DeviceId.getOrCreate();
    await ProfileApi.upsertMyProfile(
      deviceId: deviceId,
      displayName: name,
      language: _selectedLang!,
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
                    hintText: AppStrings.t('onb_first_name_hint'),
                    prefixIcon: const Icon(Icons.badge_outlined, color: WhatsAppCallTheme.subtleText),
                  ),
                ),
                const SizedBox(height: 24),
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
