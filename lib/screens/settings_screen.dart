import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/device_id.dart';
import '../services/profile_api.dart';
import '../theme/whatsapp_call_theme.dart';

/// Hosts secondary account actions: read-only email, sign out, delete
/// account. Reached from the Profile tab via a "Paramètres" button so the
/// main profile view can stay focused on identity + activity stats.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  String get _email => AuthService.currentEmail;

  Future<void> _signOut() async {
    final ok = await _confirm(
      title: AppStrings.t('profile_signout_confirm_title'),
      body: AppStrings.t('profile_signout_confirm_body'),
      destructive: false,
      confirmLabel: AppStrings.t('profile_signout'),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await AuthService.signOut();
      // The app root listens for auth changes and routes back to login.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await _confirm(
      title: 'Supprimer le compte ?',
      body:
          'Ton profil, tes amis et tes demandes seront effacés. Tu seras déconnecté immédiatement. Cette action est irréversible.',
      destructive: true,
      confirmLabel: 'Supprimer',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final uid = await DeviceId.getOrCreate();
      await ProfileApi.deleteMyProfile(uid);
      await AuthService.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required bool destructive,
    required String confirmLabel,
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (_email.isNotEmpty) _EmailRow(email: _email),
              const SizedBox(height: 24),
              _SettingsButton(
                icon: Icons.logout,
                label: AppStrings.t('profile_signout'),
                color: const Color(0xFFE53935),
                onTap: _signOut,
              ),
              const SizedBox(height: 12),
              _SettingsButton(
                icon: Icons.delete_forever,
                label: 'Supprimer le compte',
                color: const Color(0xFFE53935),
                outlined: false,
                onTap: _deleteAccount,
              ),
              if (_busy) ...[
                const SizedBox(height: 24),
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

class _EmailRow extends StatelessWidget {
  const _EmailRow({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const Icon(Icons.alternate_email,
              color: WhatsAppCallTheme.accent, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.lock_outline,
                        color: WhatsAppCallTheme.subtleText, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      AppStrings.t('profile_email_private'),
                      style: const TextStyle(
                        color: WhatsAppCallTheme.subtleText,
                        fontSize: 12,
                      ),
                    ),
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

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = true,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF2A3942)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
