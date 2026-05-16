import 'package:flutter/foundation.dart';

import 'chat_api.dart';
import 'profile_api.dart';
import 'supabase_service.dart';
import 'user_prefs.dart';

/// Convenience entry point for the "👋 first message" we send when the user
/// adds someone as a friend, so the conversation already exists on both
/// sides without anyone having to manually type a greeting.
///
/// Coucou-via-Discover already inserts a chat message of its own
/// (see `DiscoverScreen._sendHello`); add-as-friend used to only insert
/// a `friendships` row and left the chat list empty until someone broke
/// the silence. This helper closes that gap.
abstract final class Greetings {
  static Future<void> sendIntroMessage({
    required String myId,
    required String peerId,
    String body = '👋',
  }) async {
    if (!isSupabaseReady) return;
    if (myId.isEmpty || peerId.isEmpty || myId == peerId) return;
    try {
      final myProfile = await ProfileApi.fetchById(myId);
      final local = await UserPrefs.loadProfile();
      final myName = (myProfile?.displayName.trim().isNotEmpty ?? false)
          ? myProfile!.displayName
          : (local?.firstName.trim() ?? '');
      final myLang = (myProfile?.language.trim().isNotEmpty ?? false)
          ? myProfile!.language
          : (local?.sourceLang ?? '');
      final ids = [myId, peerId]..sort();
      final convId = 'dm-${ids[0]}-${ids[1]}';
      await ChatApi.sendMessage(
        conversationId: convId,
        senderId: myId,
        senderName: myName,
        recipientId: peerId,
        body: body,
        language: myLang,
      );
    } catch (e) {
      // Best-effort: a failed greeting must not block the friend-add
      // flow itself. The user can always send a message manually.
      debugPrint('Greetings.sendIntroMessage failed: $e');
    }
  }
}
