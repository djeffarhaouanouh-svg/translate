import 'dart:math';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/token_api.dart';
import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import '../translation/translation_route.dart';
import 'call_screen.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, this.translation = const NoOpRealtimeTranslation()});

  final RealtimeTranslationPort translation;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _roomCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _sourceLangCtrl = TextEditingController();
  final _targetLangCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _roomCtrl.dispose();
    _nameCtrl.dispose();
    _sourceLangCtrl.dispose();
    _targetLangCtrl.dispose();
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
        _error = 'Enter a room name (3+ characters) and your display name.';
      });
      return;
    }
    try {
      final token = await fetchLiveKitToken(
        roomName: room,
        identity: _newIdentity(),
        displayName: name,
        sourceLang: _sourceLangCtrl.text.trim(),
        targetLang: _targetLangCtrl.text.trim(),
      );
      if (!mounted) return;
      final route = TranslationRoute(
        sourceBcp47: _sourceLangCtrl.text.trim(),
        targetBcp47: _targetLangCtrl.text.trim(),
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            wsUrl: token.url,
            jwt: token.token,
            roomName: token.roomName,
            displayName: name,
            translationRoute: route,
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
    final apiBase = resolvedTokenApiBase();

    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WhatsAppCallHeader(apiBase: apiBase),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Join a room',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: WhatsAppCallTheme.strongText,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pick any room name and share it with one other person. '
                    'Both of you must use the same name to connect 1-on-1.',
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
                            labelText: 'Room name',
                            hintText: 'e.g. dinner-with-sam',
                            prefixIcon: Icon(Icons.tag, color: WhatsAppCallTheme.subtleText),
                          ),
                        ),
                        const Divider(height: 24),
                        TextField(
                          controller: _nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(color: WhatsAppCallTheme.strongText),
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            hintText: 'As others will see you',
                            prefixIcon: Icon(Icons.person_outline, color: WhatsAppCallTheme.subtleText),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                      collapsedBackgroundColor: WhatsAppCallTheme.bar,
                      backgroundColor: WhatsAppCallTheme.bar,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      iconColor: WhatsAppCallTheme.subtleText,
                      collapsedIconColor: WhatsAppCallTheme.subtleText,
                      title: const Text(
                        'Translation (optional)',
                        style: TextStyle(
                          color: WhatsAppCallTheme.strongText,
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: const Text(
                        'Reserved for future realtime translation',
                        style: TextStyle(color: WhatsAppCallTheme.subtleText, fontSize: 12),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            children: [
                              TextField(
                                controller: _sourceLangCtrl,
                                autocorrect: false,
                                style: const TextStyle(color: WhatsAppCallTheme.strongText),
                                decoration: const InputDecoration(
                                  labelText: 'You speak (BCP-47)',
                                  hintText: 'en',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _targetLangCtrl,
                                autocorrect: false,
                                style: const TextStyle(color: WhatsAppCallTheme.strongText),
                                decoration: const InputDecoration(
                                  labelText: 'Target language (BCP-47)',
                                  hintText: 'fr',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
                              Text('Start video call'),
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

class _WhatsAppCallHeader extends StatelessWidget {
  const _WhatsAppCallHeader({required this.apiBase});

  final String apiBase;

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
                  const Expanded(
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
