import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/device_id.dart';
import '../services/profile_api.dart';
import '../theme/whatsapp_call_theme.dart';
import 'onboarding_screen.dart';

/// Hosts every secondary account-level action that doesn't belong on the
/// main profile view: account management, notification toggles, privacy,
/// language & translation prefs, subscription, help/legal. Keeps the
/// Profile tab focused on identity (avatar / bio / stats).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Toggle preferences are stored in SharedPreferences. Keys are namespaced
  // so they don't collide with the existing UserPrefs keys.
  static const _kPush = 'pref_push_enabled';
  static const _kSounds = 'pref_sounds_enabled';
  static const _kInAppSounds = 'pref_in_app_sounds_enabled';
  static const _kHideOnline = 'pref_hide_online';
  static const _kAutoTranslate = 'pref_auto_translate_default';
  static const _kAudioOutput = 'pref_audio_output'; // 'speaker' | 'earpiece'

  bool _busy = false;
  bool _push = true;
  bool _sounds = true;
  bool _inAppSounds = true;
  bool _hideOnline = false;
  bool _autoTranslate = false;
  String _audioOutput = 'speaker';

  String get _email => AuthService.currentEmail;
  // Hardcoded for now — a follow-up can switch this to package_info_plus
  // (would require adding the package + a sync in initState).
  static const String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _push = p.getBool(_kPush) ?? true;
      _sounds = p.getBool(_kSounds) ?? true;
      _inAppSounds = p.getBool(_kInAppSounds) ?? true;
      _hideOnline = p.getBool(_kHideOnline) ?? false;
      _autoTranslate = p.getBool(_kAutoTranslate) ?? false;
      _audioOutput = p.getString(_kAudioOutput) ?? 'speaker';
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
  }

  // ───── Actions ─────────────────────────────────────────────────────────

  Future<void> _changePassword() async {
    if (_email.isEmpty) {
      _toast('Adresse email introuvable.');
      return;
    }
    final ok = await _confirm(
      title: 'Changer le mot de passe',
      body:
          'Un email avec un lien de réinitialisation va être envoyé à $_email. Tu pourras choisir un nouveau mot de passe en cliquant sur le lien.',
      confirmLabel: 'Envoyer le lien',
      destructive: false,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await AuthService.resetPassword(_email);
      if (!mounted) return;
      _toast('Email envoyé. Vérifie ta boîte.');
    } catch (e) {
      if (!mounted) return;
      _toast('Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await _confirm(
      title: AppStrings.t('profile_signout_confirm_title'),
      body: AppStrings.t('profile_signout_confirm_body'),
      confirmLabel: AppStrings.t('profile_signout'),
      destructive: false,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await AuthService.signOut();
    } catch (e) {
      if (!mounted) return;
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await _confirm(
      title: 'Supprimer le compte ?',
      body:
          'Ton profil, tes amis et tes demandes seront effacés. Tu seras déconnecté immédiatement. Cette action est irréversible.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final uid = await DeviceId.getOrCreate();
      await ProfileApi.deleteMyProfile(uid);
      await AuthService.signOut();
    } catch (e) {
      if (!mounted) return;
      _toast('Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLanguageEditor() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => OnboardingScreen(
          editing: true,
          onCompleted: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _pickAudioOutput() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: WhatsAppCallTheme.bar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Sortie audio',
                  style: TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _AudioOutputOption(
              label: 'Haut-parleur',
              icon: Icons.volume_up,
              value: 'speaker',
              selected: _audioOutput == 'speaker',
              onTap: () => Navigator.of(ctx).pop('speaker'),
            ),
            _AudioOutputOption(
              label: 'Écouteur',
              icon: Icons.hearing,
              value: 'earpiece',
              selected: _audioOutput == 'earpiece',
              onTap: () => Navigator.of(ctx).pop('earpiece'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null && picked != _audioOutput) {
      setState(() => _audioOutput = picked);
      await _saveString(_kAudioOutput, picked);
    }
  }

  void _openBlockedUsers() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const _BlockedUsersScreen()),
    );
  }

  void _manageSubscription() {
    _toast(
      'La gestion d\'abonnement se fait depuis ton App Store / Play Store.',
    );
  }

  void _restorePurchases() {
    _toast('Restauration des achats — bientôt disponible.');
  }

  void _openHelp() => _toast('Centre d\'aide — bientôt disponible.');
  void _contactSupport() =>
      _toast('Écris-nous à support@swayco.app (à venir : ouverture mailto).');
  void _openTerms() => _toast('Conditions d\'utilisation — bientôt en ligne.');
  void _openPrivacy() => _toast('Politique de confidentialité — bientôt en ligne.');

  // ───── Helpers ─────────────────────────────────────────────────────────

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    required bool destructive,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WhatsAppCallTheme.bar,
        title: Text(title,
            style: const TextStyle(color: WhatsAppCallTheme.strongText)),
        content: Text(body,
            style: const TextStyle(color: WhatsAppCallTheme.subtleText)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: destructive
                  ? const Color(0xFFE53935)
                  : WhatsAppCallTheme.accent,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: WhatsAppCallTheme.bar,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ───── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      appBar: AppBar(
        backgroundColor: WhatsAppCallTheme.scaffold,
        foregroundColor: WhatsAppCallTheme.strongText,
        elevation: 0,
        title: const Text(
          'Paramètres',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ─── Compte ───
              const _SectionHeader(label: 'Compte'),
              _SettingsCard(children: [
                _SettingsRow(
                  icon: Icons.alternate_email,
                  label: 'Email',
                  trailing: _SubtleText(_email.isEmpty ? '—' : _email),
                ),
                _SettingsRow(
                  icon: Icons.lock_reset,
                  label: 'Changer le mot de passe',
                  onTap: _changePassword,
                ),
                _SettingsRow(
                  icon: Icons.logout,
                  label: AppStrings.t('profile_signout'),
                  color: const Color(0xFFE53935),
                  onTap: _signOut,
                ),
                _SettingsRow(
                  icon: Icons.delete_forever,
                  label: 'Supprimer le compte',
                  color: const Color(0xFFE53935),
                  onTap: _deleteAccount,
                ),
              ]),

              // ─── Notifications ───
              const _SectionHeader(label: 'Notifications'),
              _SettingsCard(children: [
                _SettingsToggleRow(
                  icon: Icons.notifications_active_outlined,
                  label: 'Notifications push',
                  value: _push,
                  onChanged: (v) {
                    setState(() => _push = v);
                    _saveBool(_kPush, v);
                  },
                ),
                _SettingsToggleRow(
                  icon: Icons.volume_up_outlined,
                  label: 'Sons des notifications',
                  value: _sounds,
                  onChanged: (v) {
                    setState(() => _sounds = v);
                    _saveBool(_kSounds, v);
                  },
                ),
                _SettingsToggleRow(
                  icon: Icons.music_note_outlined,
                  label: 'Sons dans l\'app',
                  value: _inAppSounds,
                  onChanged: (v) {
                    setState(() => _inAppSounds = v);
                    _saveBool(_kInAppSounds, v);
                  },
                ),
              ]),

              // ─── Confidentialité ───
              const _SectionHeader(label: 'Confidentialité'),
              _SettingsCard(children: [
                _SettingsRow(
                  icon: Icons.block,
                  label: 'Liste des bloqués',
                  onTap: _openBlockedUsers,
                ),
                _SettingsToggleRow(
                  icon: Icons.visibility_off_outlined,
                  label: 'Cacher mon statut en ligne',
                  value: _hideOnline,
                  onChanged: (v) {
                    setState(() => _hideOnline = v);
                    _saveBool(_kHideOnline, v);
                  },
                ),
              ]),

              // ─── Langue & traduction ───
              const _SectionHeader(label: 'Langue & traduction'),
              _SettingsCard(children: [
                _SettingsRow(
                  icon: Icons.language,
                  label: 'Langue de l\'interface',
                  onTap: _openLanguageEditor,
                ),
                _SettingsToggleRow(
                  icon: Icons.translate,
                  label: 'Auto-traduction par défaut',
                  value: _autoTranslate,
                  onChanged: (v) {
                    setState(() => _autoTranslate = v);
                    _saveBool(_kAutoTranslate, v);
                  },
                ),
                _SettingsRow(
                  icon: Icons.speaker_outlined,
                  label: 'Sortie audio',
                  trailing: _SubtleText(
                      _audioOutput == 'speaker' ? 'Haut-parleur' : 'Écouteur'),
                  onTap: _pickAudioOutput,
                ),
              ]),

              // ─── Abonnement ───
              const _SectionHeader(label: 'Abonnement'),
              _SettingsCard(children: [
                _SettingsRow(
                  icon: Icons.workspace_premium_outlined,
                  label: 'Gérer mon abonnement',
                  onTap: _manageSubscription,
                ),
                _SettingsRow(
                  icon: Icons.restart_alt,
                  label: 'Restaurer un achat',
                  onTap: _restorePurchases,
                ),
              ]),

              // ─── Aide & légal ───
              const _SectionHeader(label: 'Aide & légal'),
              _SettingsCard(children: [
                _SettingsRow(
                  icon: Icons.help_outline,
                  label: 'Centre d\'aide / FAQ',
                  onTap: _openHelp,
                ),
                _SettingsRow(
                  icon: Icons.mail_outline,
                  label: 'Contacter le support',
                  onTap: _contactSupport,
                ),
                _SettingsRow(
                  icon: Icons.gavel_outlined,
                  label: 'Conditions d\'utilisation',
                  onTap: _openTerms,
                ),
                _SettingsRow(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Politique de confidentialité',
                  onTap: _openPrivacy,
                ),
                _SettingsRow(
                  icon: Icons.info_outline,
                  label: 'Version',
                  trailing: _SubtleText(_appVersion),
                ),
              ]),

              if (_busy) ...[
                const SizedBox(height: 20),
                const Center(
                  child: CircularProgressIndicator(
                      color: WhatsAppCallTheme.accent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ───── Section header / cards / rows ────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: WhatsAppCallTheme.subtleText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final divided = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      divided.add(children[i]);
      if (i != children.length - 1) {
        divided.add(Divider(
          height: 1,
          thickness: 1,
          indent: 52,
          color: Colors.white.withValues(alpha: 0.06),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: divided),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.color,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? WhatsAppCallTheme.strongText;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: fg),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 8),
            ],
            if (onTap != null && trailing == null)
              const Icon(Icons.chevron_right,
                  color: WhatsAppCallTheme.subtleText, size: 22)
            else if (onTap != null)
              const Icon(Icons.chevron_right,
                  color: WhatsAppCallTheme.subtleText, size: 22),
          ],
        ),
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 22, color: WhatsAppCallTheme.strongText),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: WhatsAppCallTheme.strongText,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: WhatsAppCallTheme.accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubtleText extends StatelessWidget {
  const _SubtleText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: WhatsAppCallTheme.subtleText,
        fontSize: 13,
      ),
    );
  }
}

class _AudioOutputOption extends StatelessWidget {
  const _AudioOutputOption({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: WhatsAppCallTheme.strongText),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: WhatsAppCallTheme.strongText,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check, color: WhatsAppCallTheme.accent),
          ],
        ),
      ),
    );
  }
}

// ───── Blocked-users sub-screen (placeholder) ───────────────────────────

class _BlockedUsersScreen extends StatelessWidget {
  const _BlockedUsersScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      appBar: AppBar(
        backgroundColor: WhatsAppCallTheme.scaffold,
        foregroundColor: WhatsAppCallTheme.strongText,
        elevation: 0,
        title: const Text(
          'Bloqués',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block,
                  size: 56, color: WhatsAppCallTheme.subtleText),
              SizedBox(height: 14),
              Text(
                'Aucun utilisateur bloqué',
                style: TextStyle(
                  color: WhatsAppCallTheme.strongText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Tu pourras bloquer un profil depuis sa fiche ou un fil de discussion.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: WhatsAppCallTheme.subtleText,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
