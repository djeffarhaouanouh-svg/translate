import 'package:shared_preferences/shared_preferences.dart';

/// Local profile + onboarding flags (no server yet).
abstract final class UserPrefs {
  static const String keyOnboardingDone = 'onboarding_done';
  static const String keyFirstName = 'profile_first_name';
  static const String keySourceLang = 'profile_source_lang';
  static const String keyTargetLang = 'profile_target_lang';

  static Future<bool> isOnboardingDone() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(keyOnboardingDone) ?? false;
  }

  static Future<void> completeOnboarding({
    required String firstName,
    required String sourceLang,
    required String targetLang,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(keyOnboardingDone, true);
    await p.setString(keyFirstName, firstName.trim());
    await p.setString(keySourceLang, sourceLang.trim());
    await p.setString(keyTargetLang, targetLang.trim());
  }

  static Future<ProfileSnapshot?> loadProfile() async {
    final p = await SharedPreferences.getInstance();
    final name = p.getString(keyFirstName);
    if (name == null || name.isEmpty) return null;
    return ProfileSnapshot(
      firstName: name,
      sourceLang: p.getString(keySourceLang) ?? '',
      targetLang: p.getString(keyTargetLang) ?? '',
    );
  }

  /// Clears onboarding flag so the welcome flow shows again (e.g. from settings).
  static Future<void> resetOnboarding() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(keyOnboardingDone);
  }
}

class ProfileSnapshot {
  const ProfileSnapshot({
    required this.firstName,
    required this.sourceLang,
    required this.targetLang,
  });

  final String firstName;
  final String sourceLang;
  final String targetLang;
}
