import 'package:flutter/material.dart';

import '../theme/whatsapp_call_theme.dart';

/// Chat home: list of conversations. Empty until wired to a messaging backend
/// — the FAB and search are present so the layout does not shift later.
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

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
      body: const _EmptyConversations(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: WhatsAppCallTheme.accent,
        foregroundColor: Colors.white,
        onPressed: () {},
        tooltip: 'Nouvelle conversation',
        child: const Icon(Icons.chat),
      ),
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
              decoration: BoxDecoration(
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
              'Démarre une nouvelle conversation pour discuter avec quelqu\'un, '
              'et lance un appel traduit directement depuis le chat.',
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
