/// Small curated list of UI-facing languages (BCP-47 primary subtag).
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.flag,
    required this.label,
  });

  /// BCP-47 primary subtag (e.g. `fr`, `en`).
  final String code;

  /// Unicode flag emoji (rendered natively by the OS / browser).
  final String flag;

  /// Native-script label shown in the picker.
  final String label;
}

const List<AppLanguage> supportedLanguages = <AppLanguage>[
  AppLanguage(code: 'fr', flag: '🇫🇷', label: 'Français'),
  AppLanguage(code: 'en', flag: '🇬🇧', label: 'English'),
  AppLanguage(code: 'es', flag: '🇪🇸', label: 'Español'),
  AppLanguage(code: 'de', flag: '🇩🇪', label: 'Deutsch'),
  AppLanguage(code: 'it', flag: '🇮🇹', label: 'Italiano'),
  AppLanguage(code: 'pt', flag: '🇵🇹', label: 'Português'),
  AppLanguage(code: 'nl', flag: '🇳🇱', label: 'Nederlands'),
  AppLanguage(code: 'ar', flag: '🇸🇦', label: 'العربية'),
  AppLanguage(code: 'ru', flag: '🇷🇺', label: 'Русский'),
  AppLanguage(code: 'zh', flag: '🇨🇳', label: '中文'),
  AppLanguage(code: 'ja', flag: '🇯🇵', label: '日本語'),
  AppLanguage(code: 'ko', flag: '🇰🇷', label: '한국어'),
];

/// Returns the language whose primary subtag matches [code] (case-insensitive),
/// or null if the code is empty or unknown.
AppLanguage? findLanguageByCode(String code) {
  final trimmed = code.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  // Drop region subtag if present (`fr-FR` -> `fr`).
  final primary = trimmed.split('-').first;
  for (final l in supportedLanguages) {
    if (l.code == primary) return l;
  }
  return null;
}
