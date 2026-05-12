import 'dart:math';

import 'package:flutter/material.dart';

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
        _error = 'Enter a room name (3+ chars) and your display name.';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Live call')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            Text(
              '1:1 rooms',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: WhatsAppCallTheme.strongText,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Share the same room name with one other person. Tokens are issued only by your backend.',
              style: TextStyle(color: WhatsAppCallTheme.subtleText, height: 1.35),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _roomCtrl,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Room name',
                hintText: 'e.g. call-with-alex',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                hintText: 'Shown to the other person',
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Translation (optional, for later)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: WhatsAppCallTheme.subtleText,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sourceLangCtrl,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'You speak (BCP-47)',
                hintText: 'e.g. en',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetLangCtrl,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Hear translation (BCP-47)',
                hintText: 'e.g. fr',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: WhatsAppCallTheme.danger, height: 1.3),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _join,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Join call'),
            ),
          ],
        ),
      ),
    );
  }
}
