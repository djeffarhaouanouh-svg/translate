import 'package:supabase_flutter/supabase_flutter.dart';

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String body;
  final DateTime createdAt;

  factory ChatMessage.fromMap(Map<String, dynamic> m) {
    final created = m['created_at'];
    return ChatMessage(
      id: m['id']?.toString() ?? '',
      conversationId: m['conversation_id']?.toString() ?? '',
      // Read either `sender` (existing column on user's table) or
      // `sender_id` (the name my earlier migration assumed) — whichever
      // is populated.
      senderId: (m['sender'] ?? m['sender_id'])?.toString() ?? '',
      senderName: m['sender_name']?.toString() ?? '',
      body: m['body']?.toString() ?? '',
      createdAt: created is String
          ? DateTime.tryParse(created)?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Thin wrapper over the Supabase `messages` table. All methods assume
/// [Supabase.initialize] has succeeded — callers should gate on
/// [isSupabaseReady] before invoking.
abstract final class ChatApi {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Most-recent-first window of past messages for a conversation.
  static Future<List<ChatMessage>> fetchMessages(
    String conversationId, {
    int limit = 200,
  }) async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(limit);
    return (rows as List)
        .map((r) => ChatMessage.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }

  static Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    required String recipientId,
    required String body,
    required String language,
  }) async {
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender': senderId,
      'recipient': recipientId,
      'sender_name': senderName,
      'body': body,
      'language': language,
    });
  }

  /// Latest message per conversation that involves [meId]. Used by the
  /// chat list to render WhatsApp-style "last message" previews and to
  /// order rows by recent activity.
  static Future<Map<String, ChatMessage>> fetchLatestPerConversation(
    String meId, {
    int limit = 200,
  }) async {
    if (meId.isEmpty) return const {};
    final rows = await _client
        .from('messages')
        .select()
        .or('sender.eq.$meId,recipient.eq.$meId')
        .order('created_at', ascending: false)
        .limit(limit);
    final out = <String, ChatMessage>{};
    for (final r in rows as List) {
      final msg = ChatMessage.fromMap(Map<String, dynamic>.from(r as Map));
      if (msg.conversationId.isEmpty) continue;
      out.putIfAbsent(msg.conversationId, () => msg);
    }
    return out;
  }

  /// Live stream of all messages in a conversation, ordered chronologically
  /// ascending (oldest first, newest last) so the UI can render them
  /// top-to-bottom in chronological order. Re-emits the entire list on
  /// every insert; fine for typical chat scrollback sizes.
  static Stream<List<ChatMessage>> subscribeMessages(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((rows) {
          final list = rows
              .map((m) => ChatMessage.fromMap(Map<String, dynamic>.from(m)))
              .toList();
          // Defensive client-side sort in case the stream ignored the order
          // hint (some Supabase realtime builds default to descending).
          list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return List<ChatMessage>.unmodifiable(list);
        });
  }
}
