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
      senderId: m['sender_id']?.toString() ?? '',
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
    required String body,
  }) async {
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'sender_name': senderName,
      'body': body,
    });
  }

  /// Live stream of all messages in a conversation, ordered chronologically.
  /// Re-emits the entire list on every insert; this is fine for typical chat
  /// scrollback sizes (a few hundred rows).
  static Stream<List<ChatMessage>> subscribeMessages(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map((rows) => rows
            .map((m) => ChatMessage.fromMap(Map<String, dynamic>.from(m)))
            .toList(growable: false));
  }
}
