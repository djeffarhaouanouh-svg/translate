import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../services/translation_api.dart';
import 'mute_livekit_raw_stub.dart' if (dart.library.html) 'mute_livekit_raw_web.dart';
import 'realtime_translation_port.dart';
import 'translation_route.dart';

/// Listens to the **remote** LiveKit microphone, runs OpenAI **gpt-realtime-translate**
/// (WebRTC), and plays translated audio locally in your language ([TranslationRoute.sourceBcp47]).
///
/// Ephemeral secrets and SDP are obtained via your token server (`/translation/...`).
class OpenAiRealtimeTranslation extends ChangeNotifier implements RealtimeTranslationPort {
  Room? _room;
  TranslationRoute? _route;
  EventsListener<RoomEvent>? _listener;

  RTCPeerConnection? _pc;
  RTCVideoRenderer? _renderer;
  MediaStreamTrack? _clonedSource;
  MediaStream? _localStream;
  String? _boundSid;
  bool _busy = false;

  @override
  Listenable? get translationListenable => this;

  @override
  Widget? buildTranslationAudioOverlay() {
    final r = _renderer;
    if (r == null) return null;
    return Positioned(
      left: -20,
      bottom: -20,
      width: 4,
      height: 4,
      child: Opacity(
        opacity: 0.02,
        child: RTCVideoView(
          r,
          mirror: false,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ),
    );
  }

  @override
  Future<void> attachToRoom(Room room, {required TranslationRoute route}) async {
    await detach();
    _room = room;
    _route = route;
    if (!route.isConfigured) return;

    _listener = room.createListener()
      ..on<TrackSubscribedEvent>(_onTrackSubscribed)
      ..on<TrackUnsubscribedEvent>(_onTrackUnsubscribed);

    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        final t = pub.track;
        if (t is RemoteAudioTrack) {
          unawaited(_bindRemoteAudio(t, pub.sid));
          return;
        }
      }
    }
  }

  void _onTrackSubscribed(TrackSubscribedEvent e) {
    final t = e.track;
    if (t is RemoteAudioTrack) {
      unawaited(_bindRemoteAudio(t, e.publication.sid));
    }
  }

  void _onTrackUnsubscribed(TrackUnsubscribedEvent e) {
    final sid = e.publication.sid;
    if (_boundSid != null && sid == _boundSid) {
      unawaited(_tearDown());
    }
  }

  Future<void> _bindRemoteAudio(RemoteAudioTrack remote, String publicationSid) async {
    final roomRef = _room;
    final route = _route;
    if (roomRef == null || route == null || !route.isConfigured) return;
    if (_busy || _pc != null) return;

    _busy = true;
    try {
      final session = await fetchTranslationSession(outputLanguage: route.sourceBcp47);
      if (!identical(_room, roomRef)) return;
      final secret = pickClientSecret(session);
      if (secret == null || secret.isEmpty) {
        debugPrint('OpenAi translation: no client_secret in session response');
        return;
      }

      final pc = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });

      final dc = await pc.createDataChannel(
        'oai-events',
        RTCDataChannelInit(),
      );
      dc.onMessage = (RTCDataChannelMessage m) {
        if (m.isBinary) return;
        final t = m.text;
        if (t.length < 400) {
          debugPrint('OpenAI translation dc: $t');
        }
      };

      final cloned = await remote.mediaStreamTrack.clone();
      _clonedSource = cloned;

      final ms = await createLocalMediaStream('openai_translation_src');
      await ms.addTrack(cloned);
      _localStream = ms;
      await pc.addTrack(cloned, ms);

      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _renderer = renderer;

      pc.onTrack = (RTCTrackEvent event) {
        if (event.streams.isEmpty) return;
        renderer.srcObject = event.streams[0];
        notifyListeners();
      };

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      final sdp = offer.sdp;
      if (sdp == null || sdp.isEmpty) {
        debugPrint('OpenAi translation: empty local SDP');
        await _tearDown();
        return;
      }

      final answerSdp = await postTranslationCallsSdp(clientSecret: secret, sdpOffer: sdp);
      if (!identical(_room, roomRef)) return;
      await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));

      _pc = pc;
      _boundSid = publicationSid;
      notifyListeners();

      if (kIsWeb) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          muteLiveKitRawRemotePlayback(remote);
        });
      } else {
        muteLiveKitRawRemotePlayback(remote);
      }
    } catch (e, st) {
      debugPrint('OpenAi translation failed: $e\n$st');
      await _tearDown();
    } finally {
      _busy = false;
    }
  }

  Future<void> _tearDown() async {
    final pc = _pc;
    _pc = null;
    _boundSid = null;

    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
    }

    final ls = _localStream;
    _localStream = null;
    if (ls != null) {
      try {
        await ls.dispose();
      } catch (_) {}
    }

    final c = _clonedSource;
    _clonedSource = null;
    if (c != null) {
      try {
        await c.stop();
      } catch (_) {}
    }

    final r = _renderer;
    _renderer = null;
    if (r != null) {
      try {
        r.srcObject = null;
        await r.dispose();
      } catch (_) {}
    }
    notifyListeners();
  }

  @override
  Future<void> detach() async {
    await _tearDown();
    await _listener?.dispose();
    _listener = null;
    _room = null;
    _route = null;
  }

  @override
  void dispose() {
    unawaited(detach());
    super.dispose();
  }
}
