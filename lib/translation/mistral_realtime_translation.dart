import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';

import '../services/translation_api.dart';
import 'realtime_translation_port.dart';
import 'translation_route.dart';

/// Translation pipeline driven by a backend LiveKit "bot" that runs Mistral
/// Voxtral STT → Mistral chat translation → Voxtral TTS, and republishes a
/// per-listener audio track named `xlate-for-<myIdentity>`.
///
/// This Flutter side is a thin orchestrator:
///   1. Tells the backend to spawn the bot in the current room.
///   2. Subscribes to the bot's track when it shows up.
///   3. Mutes the *original* speakers so the user only hears the translation
///      (avoids double audio).
class MistralRealtimeTranslation extends ChangeNotifier
    implements RealtimeTranslationPort {
  Room? _room;
  TranslationRoute? _route;
  EventsListener<RoomEvent>? _listener;
  String? _botIdentityPrefix;
  String? _roomName;
  bool _attached = false;
  bool _botRequested = false;

  static const String _defaultBotIdentityPrefix = 'xlate-bot';

  bool _isBot(Participant p) =>
      p.identity.startsWith(_botIdentityPrefix ?? _defaultBotIdentityPrefix);

  @override
  Listenable? get translationListenable => this;

  @override
  Widget? buildTranslationAudioOverlay() => null;

  @override
  TranslationFeedbackPhase get translationFeedbackPhase {
    if (_room == null || _route == null || !_route!.isConfigured) {
      return TranslationFeedbackPhase.hidden;
    }
    final hasBot = _room!.remoteParticipants.values.any(_isBot);
    if (hasBot) return TranslationFeedbackPhase.live;
    if (_botRequested) return TranslationFeedbackPhase.working;
    return TranslationFeedbackPhase.standby;
  }

  @override
  bool get translationRemoteVoiceHot {
    final r = _room;
    if (r == null) return false;
    for (final p in r.remoteParticipants.values) {
      if (_isBot(p)) continue;
      if (p.isSpeaking) return true;
    }
    return false;
  }

  @override
  Future<void> setTranslatedAudioVolume(double volume) async {
    // livekit_client 2.7.0 doesn't expose a per-track volume on RemoteAudioTrack,
    // only enable()/disable() at the publication level. Volume control would
    // require dropping below the SDK (Web AudioContext or native audio session)
    // so we keep it as a no-op for now and ship muting via enable/disable.
  }

  @override
  Future<void> attachToRoom(
    Room room, {
    required TranslationRoute route,
    String? roomName,
  }) async {
    await detach();
    _room = room;
    _route = route;
    _roomName = roomName;
    _attached = true;
    if (!route.isConfigured) return;
    if (roomName == null || roomName.isEmpty) {
      debugPrint('Mistral translation: missing roomName, agent will not spawn');
      return;
    }

    _listener = room.createListener()
      ..on<TrackSubscribedEvent>((_) => _applyTrackEnablement())
      ..on<TrackUnsubscribedEvent>((_) => _applyTrackEnablement())
      ..on<ParticipantConnectedEvent>((_) => _applyTrackEnablement())
      ..on<ParticipantDisconnectedEvent>((_) => _applyTrackEnablement())
      ..on<ActiveSpeakersChangedEvent>((_) => notifyListeners());

    unawaited(_ensureAgentSpawned());
    notifyListeners();
  }

  Future<void> _ensureAgentSpawned() async {
    final name = _roomName;
    if (name == null || name.isEmpty || !_attached) return;
    try {
      final result = await ensureTranslationAgent(roomName: name);
      _botIdentityPrefix = result.botIdentityPrefix ?? _defaultBotIdentityPrefix;
      _botRequested = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Mistral translation: ensureTranslationAgent failed: $e');
      if (_attached) {
        Future.delayed(const Duration(seconds: 4), _ensureAgentSpawned);
      }
    }
    await _applyTrackEnablement();
  }

  /// Walks every audio publication and toggles enable()/disable():
  /// - Bot tracks named `xlate-for-<myIdentity>` → enabled (we hear them).
  /// - Other bot tracks (translations for someone else) → disabled.
  /// - Human tracks → disabled while a translation track for me exists;
  ///   otherwise enabled so the user never sits in silence (e.g. bot still
  ///   warming up, no translation produced yet).
  Future<void> _applyTrackEnablement() async {
    final room = _room;
    if (room == null) return;
    final localIdentity = room.localParticipant?.identity ?? '';
    final myTrackName = 'xlate-for-$localIdentity';

    bool haveTranslationForMe = false;
    for (final p in room.remoteParticipants.values) {
      if (!_isBot(p)) continue;
      for (final pub in p.audioTrackPublications) {
        if (pub.name == myTrackName) {
          haveTranslationForMe = true;
          break;
        }
      }
      if (haveTranslationForMe) break;
    }

    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        final shouldEnable = _isBot(p)
            ? pub.name == myTrackName
            : !haveTranslationForMe;
        try {
          if (shouldEnable) {
            await pub.enable();
          } else {
            await pub.disable();
          }
        } catch (e) {
          debugPrint('Mistral translation: enable/disable failed on ${pub.name}: $e');
        }
      }
    }
    notifyListeners();
  }

  @override
  Future<void> detach() async {
    _attached = false;
    _botRequested = false;
    final room = _room;
    final routeWasConfigured = _route?.isConfigured ?? false;
    final name = _roomName;
    _room = null;
    _route = null;
    _roomName = null;
    await _listener?.dispose();
    _listener = null;

    if (room != null) {
      for (final p in room.remoteParticipants.values) {
        for (final pub in p.audioTrackPublications) {
            try {
            await pub.enable();
          } catch (_) {}
        }
      }
    }
    if (routeWasConfigured && name != null && name.isNotEmpty) {
      unawaited(stopTranslationAgent(roomName: name).catchError((_) {}));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(detach());
    super.dispose();
  }
}
