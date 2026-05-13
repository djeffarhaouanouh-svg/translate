import 'dart:async';

import 'package:flutter/material.dart';

import '../services/chat_api.dart';
import '../services/device_id.dart';
import '../services/supabase_service.dart';
import '../services/user_prefs.dart';
import '../theme/whatsapp_call_theme.dart';

/// One-to-one chat thread for [conversationId]. Title is the human-friendly
/// name shown in the header (replacing the legacy phone-number look).
class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
    required this.peerDeviceId,
  });

  final String conversationId;
  final String title;

  /// The other party's device id — sent with every message as `recipient`
  /// so the deployed messages schema (DM-style, NOT-NULL recipient column)
  /// accepts inserts.
  final String peerDeviceId;

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
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final id = await DeviceId.getOrCreate();
    final profile = await UserPrefs.loadProfile();
    if (!mounted) return;
    setState(() {
      _myId = id;
      _myName = profile?.firstName.trim() ?? '';
      _myLang = profile?.sourceLang.trim() ?? '';
    });

    if (!isSupabaseReady) {
      setState(() => _error = 'Supabase non configuré — les messages ne sont pas disponibles.');
      return;
    }
    _sub = ChatApi.subscribeMessages(widget.conversationId).listen(
      (rows) {
        if (!mounted) return;
        setState(() => _messages = rows);
        // reverse:true ListView keeps new items at the bottom automatically;
        // no manual scrollToBottom needed.
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = 'Connexion temps réel perdue: $e');
      },
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
      appBar: _ThreadHeader(title: widget.title),
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
    // WhatsApp-style: messages stick to the bottom (empty space at top, last
    // message just above the composer). reverse:true renders the list from
    // the bottom up; we flip the index so the chronological order is kept.
    return ListView.builder(
      controller: _scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) {
        // Flip index because reverse:true renders index 0 at the bottom and
        // we want the newest (last in the chronological list) at the bottom.
        final m = _messages[_messages.length - 1 - i];
        final mine = m.senderId == _myId;
        return _MessageBubble(message: m, mine: mine);
      },
    );
  }
}

class _ThreadHeader extends StatelessWidget implements PreferredSizeWidget {
  const _ThreadHeader({required this.title});
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            child: const Icon(Icons.person, color: Colors.white, size: 20),
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
        IconButton(
          tooltip: 'Appel vidéo',
          onPressed: () {},
          icon: const Icon(Icons.videocam_outlined),
        ),
        IconButton(
          tooltip: 'Appel vocal',
          onPressed: () {},
          icon: const Icon(Icons.call_outlined),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

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
              message.body,
              style: const TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontSize: 15,
                height: 1.3,
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
