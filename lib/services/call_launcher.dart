import 'dart:math';

import 'package:flutter/material.dart';

import '../screens/call_screen.dart';
import '../translation/realtime_translation_port.dart';
import 'device_id.dart';
import 'token_api.dart';
import 'user_prefs.dart';

/// Single entry point that any screen can call to dial a friend. Wraps the
/// "derive deterministic room id from both device ids + mint LiveKit token
/// + push CallScreen" sequence so we don't duplicate it across the Chat
/// list, chat thread header, etc.
abstract final class CallLauncher {
  static String _newIdentity() {
    final r = Random();
    return 'u${DateTime.now().millisecondsSinceEpoch}${r.nextInt(999999)}';
  }

  /// Deterministic LiveKit room name derived from both device ids. Sorted
  /// pair → both peers compute the same room. Trimmed to fit the backend's
  /// 3-64 char regex.
  static String roomNameFor(String idA, String idB) {
    final a = idA.replaceAll('-', '');
    final b = idB.replaceAll('-', '');
    final aShort = a.substring(0, a.length.clamp(0, 12));
    final bShort = b.substring(0, b.length.clamp(0, 12));
    final pair = [aShort, bShort]..sort();
    return 'call-${pair[0]}-${pair[1]}';
  }

  /// Returns true if the call was launched, false otherwise (missing profile,
  /// network error, etc.). Shows a snackbar on failure when [context] is
  /// still mounted.
  static Future<bool> startCall(
    BuildContext context, {
    required String peerDeviceId,
    required RealtimeTranslationPort translation,
  }) async {
    final myId = await DeviceId.getOrCreate();
    final profile = await UserPrefs.loadProfile();
    final myName = profile?.firstName.trim() ?? '';
    final mySourceLang = profile?.sourceLang.trim() ?? '';

    if (myName.isEmpty || mySourceLang.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complète ton profil avant de lancer un appel.'),
          ),
        );
      }
      return false;
    }

    try {
      final room = roomNameFor(myId, peerDeviceId);
      final token = await fetchLiveKitToken(
        roomName: room,
        identity: _newIdentity(),
        displayName: myName,
        sourceLang: mySourceLang,
      );
      if (!context.mounted) return false;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            wsUrl: token.url,
            jwt: token.token,
            roomName: token.roomName,
            displayName: myName,
            mySourceLang: mySourceLang,
            translation: translation,
          ),
        ),
      );
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de démarrer l\'appel : $e')),
        );
      }
      return false;
    }
  }
}
