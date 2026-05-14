import 'dart:async';

import 'package:flutter/material.dart';

import '../services/call_launcher.dart';
import '../services/chat_api.dart';
import '../services/device_id.dart';
import '../services/profile_api.dart';
import '../services/supabase_service.dart';
import '../services/translation_api.dart';
import '../services/user_prefs.dart';
import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import '../widgets/profile_avatar.dart';

/// One-to-one chat thread for [conversationId]. Title is the human-friendly
/// name shown in the header. The header phone icon dials the peer directly
/// via CallLauncher.
class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
    required this.peerDeviceId,
    this.translation = const NoOpRealtimeTranslation(),
  });

  final String conversationId;
  final String title;

  /// The other party's device id — sent with every message as `recipient`
  /// so the deployed messages schema (DM-style, NOT-NULL recipient column)
  /// accepts inserts. Also used as the peer for the call shortcut.
  final String peerDeviceId;

  final RealtimeTranslationPort translation;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  StreamSubscription<List<ChatMessage>>? _sub;
  List<ChatMessage> _messages = const [];
  String _myId = '';
  String _myName = '';
  String _myLang = '';
  RemoteProfile? _peer;
  bool _sending = false;
  String? _error;

  /// When true, replace each foreign-language message body with its
  /// translation into [_myLang]. Translations are cached by message id so we
  /// only hit OpenAI once per message.
  bool _autoTranslate = false;
  final Map<String, String> _translations = {};
  final Set<String> _translatingIds = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Toggle the auto-translate state. On turn-on, kick translation for all
  /// visible foreign-language messages.
  void _toggleAutoTranslate() {
    setState(() => _autoTranslate = !_autoTranslate);
    if (_autoTranslate) _ensureTranslationsForCurrent();
  }

  /// For every message in [_messages] whose language differs from mine and
  /// is not yet cached or in flight, fetch the translation and rebuild.
  void _ensureTranslationsForCurrent() {
    if (_myLang.isEmpty) return;
    for (final m in _messages) {
      _maybeFetchTranslation(m);
    }
  }

  void _maybeFetchTranslation(ChatMessage m) {
    if (!_autoTranslate || _myLang.isEmpty) return;
    final id = m.id;
    if (id.isEmpty) return;
    final lang = _messageLang(m);
    if (lang == _myLang) return; // already in my language
    if (_translations.containsKey(id) || _translatingIds.contains(id)) return;
    _translatingIds.add(id);
    () async {
      try {
        final out = await fetchTextTranslation(
          text: m.body,
          to: _myLang,
          from: lang.isEmpty ? null : lang,
        );
        if (!mounted) return;
        setState(() {
          _translations[id] = out;
          _translatingIds.remove(id);
        });
      } catch (_) {
        if (mounted) {
          setState(() => _translatingIds.remove(id));
        }
      }
    }();
  }

  /// Best-effort message language: prefer the explicit column we send when
  /// inserting; fall back to the sender's profile language ("their lang")
  /// if needed. Empty if unknown.
  String _messageLang(ChatMessage m) {
    // ChatMessage doesn't expose the language column today; use the peer's
    // language when the sender is the peer, else my language.
    if (m.senderId == _myId) return _myLang;
    return _peer?.language.trim() ?? '';
  }

  String _displayBodyFor(ChatMessage m) {
    if (!_autoTranslate) return m.body;
    final translated = _translations[m.id];
    if (translated != null && translated.isNotEmpty) return translated;
    return m.body;
  }

  Future<void> _bootstrap() async {
    final id = await DeviceId.getOrCreate();
    final profile = await UserPrefs.loadProfile();
    final peer = isSupabaseReady
        ? await ProfileApi.fetchById(widget.peerDeviceId)
        : null;
    if (!mounted) return;
    setState(() {
      _myId = id;
      _myName = profile?.firstName.trim() ?? '';
      _myLang = profile?.sourceLang.trim() ?? '';
      _peer = peer;
    });

    if (!isSupabaseReady) {
      setState(() => _error = 'Supabase non configuré — les messages ne sont pas disponibles.');
      return;
    }
    _sub = ChatApi.subscribeMessages(widget.conversationId).listen(
      (rows) {
        if (!mounted) return;
        setState(() => _messages = rows);
        // If auto-translate is on, kick translations for the new arrivals.
        if (_autoTranslate) {
          for (final m in rows) {
            _maybeFetchTranslation(m);
          }
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = 'Connexion temps réel perdue: $e');
      },
    );
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _inputCtrl.text.trim();
    if (body.isEmpty || _sending) return;
    if (_myId.isEmpty) return;
    if (!isSupabaseReady) {
      setState(() => _error = 'Supabase non configuré.');
      return;
    }
    setState(() => _sending = true);
    try {
      await ChatApi.sendMessage(
        conversationId: widget.conversationId,
        senderId: _myId,
        senderName: _myName.isEmpty ? 'Moi' : _myName,
        recipientId: widget.peerDeviceId,
        body: body,
        language: _myLang,
      );
      _inputCtrl.clear();
    } catch (e) {
      setState(() => _error = 'Envoi échoué: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      appBar: _ThreadHeader(
        title: widget.title,
        peer: _peer,
        autoTranslate: _autoTranslate,
        onToggleTranslate: _toggleAutoTranslate,
        onCall: () => CallLauncher.startCall(
          context,
          peerDeviceId: widget.peerDeviceId,
          translation: widget.translation,
        ),
      ),
      body: Column(
        children: [
          if (_error != null) _ErrorBanner(message: _error!),
          Expanded(child: _buildMessageList()),
          _Composer(
            controller: _inputCtrl,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Aucun message — écris le premier !',
            style: TextStyle(
              color: WhatsAppCallTheme.subtleText,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // Top-anchored layout: first (oldest) message at the top, list grows
    // downward, empty space at the bottom when the conversation is short.
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) {
        final m = _messages[i];
        final mine = m.senderId == _myId;
        return _MessageBubble(
          message: m,
          mine: mine,
          displayBody: _displayBodyFor(m),
          translating: _translatingIds.contains(m.id),
        );
      },
    );
  }
}

class _ThreadHeader extends StatelessWidget implements PreferredSizeWidget {
  const _ThreadHeader({
    required this.title,
    required this.peer,
    required this.autoTranslate,
    required this.onToggleTranslate,
    required this.onCall,
  });
  final String title;
  final RemoteProfile? peer;
  final bool autoTranslate;
  final VoidCallback onToggleTranslate;
  final VoidCallback onCall;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          ProfileAvatar(
            displayName: title,
            avatarUrl: peer?.avatarUrl,
            avatarColorHex: peer?.avatarColor,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Center(
            child: _TranslatePill(active: autoTranslate, onTap: onToggleTranslate),
          ),
        ),
        IconButton(
          tooltip: 'Appel vidéo',
          onPressed: onCall,
          icon: const Icon(Icons.videocam_outlined),
        ),
      ],
    );
  }
}

/// Dark pill with a glowing orb on one side — taps toggle the auto-translate
/// state. Mimics a physical switch where the "on" position lights up.
class _TranslatePill extends StatelessWidget {
  const _TranslatePill({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const w = 44.0;
    const h = 22.0;
    const ball = 18.0;
    final orbColor = active ? const Color(0xFFFF6A00) : WhatsAppCallTheme.subtleText;
    return Tooltip(
      message: active ? 'Traduction auto activée' : 'Traduire les messages',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: w,
          height: h,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xFF2A3942),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: active ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: ball,
              height: ball,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: active
                    ? const RadialGradient(
                        colors: [Color(0xFFFFC15A), Color(0xFFFF6A00)],
                      )
                    : null,
                color: active ? null : Colors.white.withValues(alpha: 0.35),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: orbColor.withValues(alpha: 0.55),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.displayBody,
    required this.translating,
  });
  final ChatMessage message;
  final bool mine;
  /// Body text actually rendered — may be the translated version when the
  /// thread-level auto-translate toggle is on.
  final String displayBody;
  /// Show a subtle indicator while the translation is being fetched.
  final bool translating;

  @override
  Widget build(BuildContext context) {
    final bg = mine ? WhatsAppCallTheme.accentMuted : WhatsAppCallTheme.bubbleIncoming;
    final align = mine ? Alignment.centerRight : Alignment.centerLeft;
    final radius = mine
        ? const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(14),
          );

    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine && message.senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.senderName,
                  style: const TextStyle(
                    color: WhatsAppCallTheme.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            Text(
              displayBody,
              style: TextStyle(
                color: translating
                    ? WhatsAppCallTheme.strongText.withValues(alpha: 0.55)
                    : WhatsAppCallTheme.strongText,
                fontSize: 15,
                height: 1.3,
                fontStyle: translating ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                time,
                style: TextStyle(
                  color: WhatsAppCallTheme.strongText.withValues(alpha: 0.55),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        color: WhatsAppCallTheme.bar,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: TextField(
                  controller: controller,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: WhatsAppCallTheme.strongText),
                  decoration: InputDecoration(
                    hintText: 'Message',
                    hintStyle: const TextStyle(color: WhatsAppCallTheme.subtleText),
                    filled: true,
                    fillColor: WhatsAppCallTheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: WhatsAppCallTheme.accent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: sending
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      color: WhatsAppCallTheme.danger.withValues(alpha: 0.18),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFFFAB91), fontSize: 12, height: 1.35),
      ),
    );
  }
}
