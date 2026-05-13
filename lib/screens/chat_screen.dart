import 'package:flutter/material.dart';

import '../services/chat_prefs.dart';
import '../services/device_id.dart';
import '../theme/whatsapp_call_theme.dart';
import 'chat_thread_screen.dart';

/// Chat home: list of locally-known conversations + FAB to start a new one.
/// Messages live in Supabase; the list of "rooms I have entered" stays local
/// because there is no auth-backed conversation membership yet.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<ChatConversation> _conversations = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
    // Warm up DeviceId so the first send in a thread does not block on storage.
    DeviceId.getOrCreate();
  }

  Future<void> _reload() async {
    final list = await ChatPrefs.load();
    if (!mounted) return;
    setState(() {
      _conversations = list;
      _loading = false;
    });
  }

  Future<void> _openNewConversationDialog() async {
    final created = await showDialog<ChatConversation>(
      context: context,
      builder: (ctx) => const _NewConversationDialog(),
    );
    if (created == null || !mounted) return;
    await ChatPrefs.upsert(created);
    await _reload();
    if (!mounted) return;
    _openThread(created);
  }

  Future<void> _openThread(ChatConversation conv) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          conversationId: conv.id,
          title: conv.title,
        ),
      ),
    );
    // Refresh — last activity time / unread counts will land here later.
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppCallTheme.scaffold,
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            tooltip: 'Rechercher',
            onPressed: () {},
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: WhatsAppCallTheme.accent),
            )
          : _conversations.isEmpty
              ? const _EmptyConversations()
              : _ConversationList(
                  items: _conversations,
                  onTap: _openThread,
                  onLongPress: (c) async {
                    await ChatPrefs.remove(c.id);
                    await _reload();
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: WhatsAppCallTheme.accent,
        foregroundColor: Colors.white,
        onPressed: _openNewConversationDialog,
        tooltip: 'Nouvelle conversation',
        child: const Icon(Icons.chat),
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.items,
    required this.onTap,
    required this.onLongPress,
  });

  final List<ChatConversation> items;
  final ValueChanged<ChatConversation> onTap;
  final ValueChanged<ChatConversation> onLongPress;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        color: Color(0xFF1F2C34),
      ),
      itemBuilder: (ctx, i) {
        final c = items[i];
        return ListTile(
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: WhatsAppCallTheme.bar,
            child: Text(
              c.title.isNotEmpty ? c.title.characters.first.toUpperCase() : '?',
              style: const TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          title: Text(
            c.title,
            style: const TextStyle(
              color: WhatsAppCallTheme.strongText,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            'ID : ${c.id}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: WhatsAppCallTheme.subtleText, fontSize: 12),
          ),
          onTap: () => onTap(c),
          onLongPress: () => onLongPress(c),
        );
      },
    );
  }
}

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: WhatsAppCallTheme.bar,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: WhatsAppCallTheme.subtleText,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Aucune conversation pour le moment',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WhatsAppCallTheme.strongText,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Crée une nouvelle conversation en partageant un identifiant '
              'avec quelqu\'un. Vous verrez vos messages en temps réel.',
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
    );
  }
}

class _NewConversationDialog extends StatefulWidget {
  const _NewConversationDialog();

  @override
  State<_NewConversationDialog> createState() => _NewConversationDialogState();
}

class _NewConversationDialogState extends State<_NewConversationDialog> {
  final _idCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _idCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _idCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    if (id.isEmpty || title.isEmpty) {
      setState(() => _error = 'Renseigne un identifiant et un nom.');
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]{3,64}$').hasMatch(id)) {
      setState(() => _error =
          'Identifiant invalide : 3-64 caractères (lettres, chiffres, _ et -).');
      return;
    }
    Navigator.of(context).pop(ChatConversation(id: id, title: title));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: WhatsAppCallTheme.bar,
      title: const Text(
        'Nouvelle conversation',
        style: TextStyle(color: WhatsAppCallTheme.strongText),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _idCtrl,
            autocorrect: false,
            style: const TextStyle(color: WhatsAppCallTheme.strongText),
            decoration: const InputDecoration(
              labelText: 'Identifiant de la conversation',
              hintText: 'ex. diner-avec-sam',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: WhatsAppCallTheme.strongText),
            decoration: const InputDecoration(
              labelText: 'Nom affiché',
              hintText: 'ex. Sam',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFFFAB91), fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
