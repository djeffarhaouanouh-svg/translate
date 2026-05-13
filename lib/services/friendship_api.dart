import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_api.dart';
import 'supabase_service.dart';

class IncomingFriendRequest {
  const IncomingFriendRequest({required this.friendship, this.requester});
  final Friendship friendship;
  final RemoteProfile? requester;
}

enum FriendshipStatus { none, pendingOutgoing, pendingIncoming, accepted, rejected }

class FriendshipCounts {
  const FriendshipCounts({required this.followers, required this.following});
  final int followers;
  final int following;
}

enum FriendDirection { followers, following }

class Friendship {
  const Friendship({
    required this.id,
    required this.requester,
    required this.addressee,
    required this.status,
  });

  final String id;
  final String requester;
  final String addressee;
  final String status;

  factory Friendship.fromMap(Map<String, dynamic> m) => Friendship(
        id: m['id']?.toString() ?? '',
        requester: m['requester']?.toString() ?? '',
        addressee: m['addressee']?.toString() ?? '',
        status: m['status']?.toString() ?? 'pending',
      );

  /// The "other side" of the relation from [meId]'s perspective.
  String peerOf(String meId) => requester == meId ? addressee : requester;
}

abstract final class FriendshipApi {
  static SupabaseClient get _c => Supabase.instance.client;

  /// Pending invitations addressed TO me, hydrated with the requester's
  /// profile so the UI can render avatar + name without a second query.
  static Future<List<IncomingFriendRequest>> fetchIncomingPendingWithProfiles(
    String meId,
  ) async {
    if (!isSupabaseReady || meId.isEmpty) return const [];
    final rows = await _c
        .from('friendships')
        .select()
        .eq('addressee', meId)
        .eq('status', 'pending');
    final friendships = (rows as List)
        .map((r) => Friendship.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
    if (friendships.isEmpty) return const [];

    final requesterIds = friendships
        .map((f) => f.requester)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final profiles = await ProfileApi.fetchByIds(requesterIds);
    final byId = {for (final p in profiles) p.id: p};
    return [
      for (final f in friendships)
        IncomingFriendRequest(friendship: f, requester: byId[f.requester]),
    ];
  }

  /// Accepted friends, hydrated with profile rows. Direction picks which
  /// side of the relation [meId] is on:
  /// - followers  → people who sent ME a request that I accepted.
  /// - following  → people I sent a request to and they accepted.
  static Future<List<RemoteProfile>> fetchAcceptedPeers({
    required String meId,
    required FriendDirection direction,
  }) async {
    if (!isSupabaseReady || meId.isEmpty) return const [];
    final filterColumn =
        direction == FriendDirection.followers ? 'addressee' : 'requester';
    final peerColumn =
        direction == FriendDirection.followers ? 'requester' : 'addressee';
    final rows = await _c
        .from('friendships')
        .select()
        .eq(filterColumn, meId)
        .eq('status', 'accepted');
    final friendships = (rows as List)
        .map((r) => Friendship.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
    if (friendships.isEmpty) return const [];
    final peerIds = friendships
        .map((f) => peerColumn == 'requester' ? f.requester : f.addressee)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return ProfileApi.fetchByIds(peerIds);
  }

  /// Counts for the profile screen.
  /// - `followers`  = accepted friendships where I am the addressee.
  /// - `following`  = accepted friendships where I am the requester.
  static Future<FriendshipCounts> countsFor(String userId) async {
    if (!isSupabaseReady || userId.isEmpty) {
      return const FriendshipCounts(followers: 0, following: 0);
    }
    try {
      final followers = await _c
          .from('friendships')
          .select('id')
          .eq('addressee', userId)
          .eq('status', 'accepted');
      final following = await _c
          .from('friendships')
          .select('id')
          .eq('requester', userId)
          .eq('status', 'accepted');
      return FriendshipCounts(
        followers: (followers as List).length,
        following: (following as List).length,
      );
    } catch (e) {
      debugPrint('FriendshipApi.countsFor failed: $e');
      return const FriendshipCounts(followers: 0, following: 0);
    }
  }

  /// Fetch every friendship row involving [meId] in either direction.
  static Future<List<Friendship>> fetchMine(String meId) async {
    if (!isSupabaseReady || meId.isEmpty) return const [];
    final rows = await _c
        .from('friendships')
        .select()
        .or('requester.eq.$meId,addressee.eq.$meId');
    return (rows as List)
        .map((r) => Friendship.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }

  /// Send a follow request from [meId] to [peerId]. Idempotent on the same
  /// direction. If [peerId] already has a row pointing at [meId] (i.e. they
  /// came first), this is treated as a "follow back" and the new row lands
  /// with status='accepted' directly — no second approval needed. Any
  /// still-pending reverse row is flipped to accepted at the same time, so
  /// both sides converge to the mutual state in one tap.
  static Future<Friendship?> sendRequest({
    required String meId,
    required String peerId,
  }) async {
    if (!isSupabaseReady) return null;
    if (meId.isEmpty || peerId.isEmpty || meId == peerId) return null;

    // 1. Same-direction row → idempotent.
    final sameDir = await _c
        .from('friendships')
        .select()
        .eq('requester', meId)
        .eq('addressee', peerId)
        .limit(1)
        .maybeSingle();
    if (sameDir != null) {
      return Friendship.fromMap(Map<String, dynamic>.from(sameDir));
    }

    // 2. Reverse row → peer already follows me; auto-accept on this side and
    //    upgrade their row to accepted if still pending.
    final reverse = await _c
        .from('friendships')
        .select()
        .eq('requester', peerId)
        .eq('addressee', meId)
        .limit(1)
        .maybeSingle();
    final autoAccept = reverse != null;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    if (reverse != null) {
      final reverseFs =
          Friendship.fromMap(Map<String, dynamic>.from(reverse));
      if (reverseFs.status == 'pending') {
        try {
          await _c.from('friendships').update({
            'status': 'accepted',
            'responded_at': nowIso,
          }).eq('id', reverseFs.id);
        } catch (e) {
          debugPrint('FriendshipApi.sendRequest reverse-accept failed: $e');
        }
      }
    }

    final payload = <String, dynamic>{
      'requester': meId,
      'addressee': peerId,
      'status': autoAccept ? 'accepted' : 'pending',
    };
    if (autoAccept) {
      payload['responded_at'] = nowIso;
    }
    final inserted = await _c
        .from('friendships')
        .insert(payload)
        .select()
        .single();
    return Friendship.fromMap(Map<String, dynamic>.from(inserted));
  }

  static Future<void> accept(String friendshipId) async {
    if (!isSupabaseReady) return;
    await _c.from('friendships').update({
      'status': 'accepted',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', friendshipId);
  }

  static Future<void> reject(String friendshipId) async {
    if (!isSupabaseReady) return;
    await _c.from('friendships').update({
      'status': 'rejected',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', friendshipId);
  }

  static Future<void> remove(String friendshipId) async {
    if (!isSupabaseReady) return;
    await _c.from('friendships').delete().eq('id', friendshipId);
  }

  /// Derive how I (`meId`) currently stand with [peerId] given a list of my
  /// friendships. Useful for tagging each search result with a status pill.
  static (FriendshipStatus, Friendship?) statusWith(
    String meId,
    String peerId,
    List<Friendship> mine,
  ) {
    for (final f in mine) {
      final involvesPeer =
          (f.requester == meId && f.addressee == peerId) ||
              (f.requester == peerId && f.addressee == meId);
      if (!involvesPeer) continue;
      switch (f.status) {
        case 'accepted':
          return (FriendshipStatus.accepted, f);
        case 'rejected':
          return (FriendshipStatus.rejected, f);
        case 'pending':
          if (f.requester == meId) {
            return (FriendshipStatus.pendingOutgoing, f);
          }
          return (FriendshipStatus.pendingIncoming, f);
      }
    }
    return (FriendshipStatus.none, null);
  }
}
