import 'dart:math';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/languages.dart';
import '../services/token_api.dart';
import '../services/user_prefs.dart';
import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import 'call_screen.dart';
import 'onboarding_screen.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, this.translation = const NoOpRealtimeTranslation()});

  final RealtimeTranslationPort translation;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _roomCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _sourceLang = '';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyStoredProfile());
  }

  Future<void> _applyStoredProfile() async {
    final snap = await UserPrefs.loadProfile();
    if (!mounted || snap == null) return;
    setState(() {
      _nameCtrl.text = snap.firstName;
      _sourceLang = snap.sourceLang.trim();
    });
  }

  Future<void> _openProfileEditor() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => OnboardingScreen(
          editing: true,
          onCompleted: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
    await _applyStoredProfile();
  }

  @override
  void dispose() {
    _roomCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String _newIdentity() {
    final r = Random();
    return 'u${DateTime.now().millisecondsSinceEpoch}${r.nextInt(999999)}';
  }

  Future<void> _join() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    final room = _roomCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (room.length < 3 || name.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Entre un nom de room (3+ caractères) et ton prénom.';
      });
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]{3,64}$').hasMatch(room)) {
      setState(() {
        _busy = false;
        _error =
            'Le nom de room doit faire 3 à 64 caractères : lettres, chiffres, _ et - uniquement (pas d\'espace ni #). Exemple : diner-avec-sam';
      });
      return;
    }
    if (_sourceLang.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Choisis ta langue dans ton profil avant de rejoindre.';
      });
      return;
    }
    try {
      final token = await fetchLiveKitToken(
        roomName: room,
        identity: _newIdentity(),
        displayName: name,
        // Only the user's own language is sent — the remote person's language
        // is discovered live from their participant metadata at call time.
        sourceLang: _sourceLang,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            wsUrl: token.url,
            jwt: token.token,
            roomName: token.roomName,
            displayName: name,
            mySourceLang: _sourceLang,
            translation: widget.translation,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiBase = displayTokenApiBase();
    final lang = findLanguageByCode(_sourceLang);

    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WhatsAppCallHeader(
            apiBase: apiBase,
            onEditProfile: _openProfileEditor,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rejoindre une room',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: WhatsAppCallTheme.strongText,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choisis un nom de room et partage-le avec une autre personne. '
                    'Vous devez utiliser le même nom pour vous retrouver en 1-on-1.',
                    style: TextStyle(
                      color: WhatsAppCallTheme.subtleText,
                      height: 1.4,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FieldCard(
                    child: Column(
                      children: [
                        TextField(
                          controller: _roomCtrl,
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          style: const TextStyle(color: WhatsAppCallTheme.strongText),
                          decoration: const InputDecoration(
                            labelText: 'Nom de la room',
                            hintText: 'ex. diner-avec-sam',
                            prefixIcon: Icon(Icons.tag, color: WhatsAppCallTheme.subtleText),
                          ),
                        ),
                        const Divider(height: 24),
                        TextField(
                          controller: _nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(color: WhatsAppCallTheme.strongText),
                          decoration: const InputDecoration(
                            labelText: 'Ton prénom',
                            hintText: 'Comme les autres te verront',
                            prefixIcon: Icon(Icons.person_outline, color: WhatsAppCallTheme.subtleText),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LanguageSummaryCard(language: lang, onEdit: _openProfileEditor),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: WhatsAppCallTheme.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: WhatsAppCallTheme.danger.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFFAB91),
                          height: 1.35,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _join,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: WhatsAppCallTheme.onAccent,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_rounded, size: 22),
                              SizedBox(width: 10),
                              Text('Démarrer l\'appel'),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageSummaryCard extends StatelessWidget {
  const _LanguageSummaryCard({required this.language, required this.onEdit});

  final AppLanguage? language;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Text(
            language?.flag ?? '🌐',
            style: const TextStyle(fontSize: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  language != null ? 'Tu parles ${language!.label}' : 'Aucune langue choisie',
                  style: const TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'La langue de l\'autre est détectée automatiquement.',
                  style: TextStyle(
                    color: WhatsAppCallTheme.subtleText,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            tooltip: 'Modifier ton profil',
            icon: const Icon(Icons.edit_outlined, color: WhatsAppCallTheme.subtleText),
          ),
        ],
      ),
    );
  }
}

class _WhatsAppCallHeader extends StatelessWidget {
  const _WhatsAppCallHeader({
    required this.apiBase,
    this.onEditProfile,
  });

  final String apiBase;
  final VoidCallback? onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WhatsAppCallTheme.waHeader,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.videocam, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calls',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          'LiveKit · 1-on-1',
                          style: TextStyle(
                            color: Color(0xFFB8E0D8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onEditProfile != null)
                    IconButton(
                      onPressed: onEditProfile,
                      tooltip: 'Ton profil',
                      icon: Icon(
                        Icons.manage_accounts_outlined,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Token server: $apiBase',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WhatsAppCallTheme.bar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A3942)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: child,
      ),
    );
  }
}
