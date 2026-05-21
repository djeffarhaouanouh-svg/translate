import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// A signed, time-limited invitation to a one-off guest call. The host
/// creates one via [GuestInviteApi.create] and shares [link]; whoever opens
/// it joins [roomName] with no account (see `GuestJoinScreen`).
class GuestInvite {
  GuestInvite({
    required this.roomName,
    required this.sig,
    required this.exp,
    required this.link,
  });

  /// LiveKit room name — always starts with `guest-`.
  final String roomName;

  /// HMAC signature minted by the backend; replayed to `/livekit/token`.
  final String sig;

  /// Expiry as epoch-milliseconds, kept as a string for transport.
  final String exp;

  /// The full web URL to share (`https://…/c/<room>?t=<sig>&e=<exp>`).
  final String link;
}

/// Thin client for `POST /invite/create`. The host must be signed in — the
/// backend reads their user id from the Supabase JWT in the Authorization
/// header and refuses the request otherwise.
abstract final class GuestInviteApi {
  /// Origin (scheme + host + port) that serves both the backend and the
  /// Flutter web build — the base for the shareable invite link.
  static Uri _origin() {
    const fromEnv = String.fromEnvironment('TOKEN_API_BASE');
    if (fromEnv.isNotEmpty) {
      return Uri.parse(fromEnv.replaceAll(RegExp(r'/$'), ''));
    }
    if (kIsWeb) return Uri.base.removeFragment();
    return Uri.parse(resolvedTokenApiBase().replaceAll(RegExp(r'/$'), ''));
  }

  static Uri _endpoint(String path) {
    final o = _origin();
    return Uri(
      scheme: o.scheme,
      host: o.host,
      port: o.hasPort ? o.port : null,
      path: path,
    );
  }

  static String _buildLink(String room, String sig, String exp) {
    final o = _origin();
    return Uri(
      scheme: o.scheme,
      host: o.host,
      port: o.hasPort ? o.port : null,
      path: '/c/$room',
      queryParameters: {'t': sig, 'e': exp},
    ).toString();
  }

  /// Parse the current web URL for a guest-invite deep link of the form
  /// `/c/<room>?t=<sig>&e=<exp>`. Returns `null` when this isn't one (the
  /// normal case — the app then boots into its usual login flow).
  static GuestInvite? fromCurrentUrl() {
    if (!kIsWeb) return null;
    final u = Uri.base;
    final seg = u.pathSegments;
    if (seg.length < 2 || seg[0] != 'c') return null;
    final room = seg[1];
    final sig = u.queryParameters['t'] ?? '';
    final exp = u.queryParameters['e'] ?? '';
    if (room.isEmpty || sig.isEmpty || exp.isEmpty) return null;
    return GuestInvite(roomName: room, sig: sig, exp: exp, link: u.toString());
  }

  /// Mints a fresh guest-call invite. Returns `null` when the host is not
  /// signed in, the network fails, or the backend rejects the request.
  static Future<GuestInvite?> create() async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      debugPrint('GuestInviteApi.create: no auth session');
      return null;
    }
    try {
      final res = await http
          .post(
            _endpoint('/invite/create'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        debugPrint(
          'GuestInviteApi.create failed: ${res.statusCode} ${res.body}',
        );
        return null;
      }
      final j = jsonDecode(res.body);
      if (j is! Map) return null;
      final room = j['roomName']?.toString() ?? '';
      final sig = j['sig']?.toString() ?? '';
      final exp = j['exp']?.toString() ?? '';
      if (room.isEmpty || sig.isEmpty || exp.isEmpty) return null;
      return GuestInvite(
        roomName: room,
        sig: sig,
        exp: exp,
        link: _buildLink(room, sig, exp),
      );
    } catch (e) {
      debugPrint('GuestInviteApi.create exception: $e');
      return null;
    }
  }
}
