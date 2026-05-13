import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatConversation {
  const ChatConversation({required this.id, required this.title});
  final String id;
  final String title;

  Map<String, dynamic> toMap() => {'id': id, 'title': title};

  static ChatConversation? fromMap(Map<String, dynamic> m) {
    final id = m['id']?.toString();
    final title = m['title']?.toString();
    if (id == null || id.isEmpty || title == null || title.isEmpty) return null;
    return ChatConversation(id: id, title: title);
  }
}

/// Local persistence of the user's recent chat threads. Lives in
/// SharedPreferences (the messages themselves are in Supabase). This avoids
/// needing a "conversation membership" table while there is no auth.
abstract final class ChatPrefs {
  static const _key = 'chat_conversations';

  static Future<List<ChatConversation>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => ChatConversation.fromMap(Map<String, dynamic>.from(m)))
          .whereType<ChatConversation>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> upsert(ChatConversation conv) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    final filtered = list.where((c) => c.id != conv.id).toList()..insert(0, conv);
    await p.setString(_key, jsonEncode(filtered.map((c) => c.toMap()).toList()));
  }

  static Future<void> remove(String id) async {
    final p = await SharedPreferences.getInstance();
    final list = await load();
    final filtered = list.where((c) => c.id != id).toList(growable: false);
    await p.setString(_key, jsonEncode(filtered.map((c) => c.toMap()).toList()));
  }
}
