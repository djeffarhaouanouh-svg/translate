import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../services/translation_api.dart';
import 'realtime_translation_port.dart';
import 'translation_route.dart';

/// Listens to the **remote** LiveKit microphone, runs OpenAI **gpt-realtime-translate**
/// (WebRTC), and plays translated audio locally in your language ([TranslationRoute.sourceBcp47]).
///
/// Renews the OpenAI side before the ephemeral credential expires and retries on failure.
class OpenAiRealtimeTranslation extends ChangeNotifier implements RealtimeTranslationPort {
  Room? _room;
  TranslationRoute? _route;
  EventsListener<RoomEvent>? _listener;

  RemoteAudioTrack? _cachedRemote;
  String? _boundPublicationSid;

  RTCPeerConnection? _pc;
  RTCVideoRenderer? _renderer;
  MediaStreamTrack? _clonedSource;
  MediaStream? _localStream;
  Timer? _refreshTimer;
  /// Recovers if the one-shot refresh timer was never rescheduled (early returns, races).
  Timer? _watchdogTimer;
  bool _busy = false;
  DateTime? _lastConnectionDropSchedule;
  bool _remoteVoiceHot = false;
  bool _wasPcConnected = false;

  @override
  Listenable? get translationListenable => this;

  @override
  TranslationFeedbackPhase get translationFeedbackPhase {
    if (_room == null || _route == null || !_route!.isConfigured) {
      return TranslationFeedbackPhase.hidden;
    }
    final pc = _pc;
    if (pc != null) {
      final cs = pc.connectionState ?? RTCPeerConnectionState.RTCPeerConnectionStateNew;
      if (cs == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        return TranslationFeedbackPhase.live;
      }
      return TranslationFeedbackPhase.working;
    }
    if (_busy) {
      return TranslationFeedbackPhase.working;
    }
    return TranslationFeedbackPhase.standby;
  }

  @override
  bool get translationRemoteVoiceHot => _remoteVoiceHot;

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

  void _cancelScheduledRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _scheduleNextRefreshRaw(Duration delay) {
    _cancelScheduledRefresh();
    if (_room == null || _route == null || !_route!.isConfigured) return;
    var d = delay;
    if (d < const Duration(seconds: 4)) {
      d = const Duration(seconds: 4);
    }
    _refreshTimer = Timer(d, () => unawaited(_refreshLoop()));
  }

  void _scheduleNextRefreshFromSession(Map<String, dynamic> session) {
    final at = pickSessionExpiresAt(session);
    final now = DateTime.now();
    Duration delay;
    if (at != null) {
      // Renew well before server-side expiry (short-lived client secrets).
      delay = at.difference(now) - const Duration(seconds: 25);
      if (delay < const Duration(seconds: 15)) {
        delay = const Duration(seconds: 15);
      }
    } else {
      delay = const Duration(seconds: 35);
    }
    _scheduleNextRefreshRaw(delay);
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 22), (_) => _watchdogTick());
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  void _watchdogTick() {
    if (_room == null || _route == null || !_route!.isConfigured) return;
    if (_boundPublicationSid == null && _cachedRemote == null) return;
    if (_busy) return;

    // Lost the one-shot renewal timer (e.g. silent early-return in open pipeline).
    if (_refreshTimer == null) {
      debugPrint('OpenAi translation: watchdog — no refresh timer, re-arming');
      _scheduleNextRefreshRaw(const Duration(seconds: 2));
      return;
    }

    final pc = _pc;
    if (pc != null) {
      final cs = pc.connectionState ?? RTCPeerConnectionState.RTCPeerConnectionStateNew;
      if (cs == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          cs == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          cs == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        debugPrint('OpenAi translation: watchdog — pc state $cs, forcing refresh');
        _scheduleNextRefreshRaw(const Duration(seconds: 2));
      }
    }
  }

  RemoteAudioTrack? _resolveRemoteAudio() {
    final sid = _boundPublicationSid;
    final room = _room;
    if (sid == null || room == null) return null;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        if (pub.sid == sid) {
          final t = pub.track;
          if (t is RemoteAudioTrack) return t;
        }
      }
    }
    return null;
  }

  void _onPcConnectionState(RTCPeerConnectionState state) {
    final nowConnected = state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    if (nowConnected && !_wasPcConnected && !kIsWeb) {
      HapticFeedback.lightImpact();
    }
    _wasPcConnected = nowConnected;
    notifyListeners();

    if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
      if (_room == null) return;
      final now = DateTime.now();
      if (_lastConnectionDropSchedule != null &&
          now.difference(_lastConnectionDropSchedule!) < const Duration(seconds: 3)) {
        return;
      }
      _lastConnectionDropSchedule = now;
      _scheduleNextRefreshRaw(const Duration(seconds: 2));
    }
  }

  void _onActiveSpeakersChanged(ActiveSpeakersChangedEvent e) {
    final hot = e.speakers.any((p) => p is RemoteParticipant);
    if (hot != _remoteVoiceHot) {
      _remoteVoiceHot = hot;
      notifyListeners();
    }
  }

  Future<void> _stopMedia() async {
    final pc = _pc;
    _pc = null;
    _wasPcConnected = false;
    if (pc != null) {
      try {
        pc.onConnectionState = null;
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

  /// Opens WebRTC to OpenAI; caller must set [_busy] if needed.
  Future<void> _openPipelineCore(
    RemoteAudioTrack remote,
    String publicationSid,
    Room roomRef,
  ) async {
    final route = _route;
    if (route == null || !route.isConfigured) return;

    final session = await fetchTranslationSession(outputLanguage: route.sourceBcp47);
    if (!identical(_room, roomRef)) {
      throw StateError('room_changed_after_session');
    }

    final secret = pickClientSecret(session);
    if (secret == null || secret.isEmpty) {
      debugPrint('OpenAi translation: no client_secret in session response');
      throw StateError('missing client_secret');
    }

    RTCPeerConnection? pc;
    RTCVideoRenderer? renderer;
    MediaStreamTrack? cloned;
    MediaStream? ms;

    try {
      pc = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });

      pc.onConnectionState = (RTCPeerConnectionState s) {
        if (!identical(pc, _pc)) return;
        _onPcConnectionState(s);
      };

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

      cloned = await remote.mediaStreamTrack.clone();
      ms = await createLocalMediaStream('openai_translation_src');
      await ms.addTrack(cloned);
      await pc.addTrack(cloned, ms);

      renderer = RTCVideoRenderer();
      await renderer.initialize();
      final playbackRenderer = renderer;

      pc.onTrack = (RTCTrackEvent event) {
        if (event.streams.isEmpty) return;
        playbackRenderer.srcObject = event.streams[0];
        notifyListeners();
      };

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      final sdp = offer.sdp;
      if (sdp == null || sdp.isEmpty) {
        debugPrint('OpenAi translation: empty local SDP');
        throw StateError('empty local SDP');
      }

      if (!identical(_room, roomRef)) {
        throw StateError('room_changed_before_sdp');
      }

      final answerSdp = await postTranslationCallsSdp(clientSecret: secret, sdpOffer: sdp);
      if (!identical(_room, roomRef)) {
        throw StateError('room_changed_after_sdp');
      }

      await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));

      _pc = pc;
      _renderer = renderer;
      _clonedSource = cloned;
      _localStream = ms;
      _boundPublicationSid = publicationSid;
      pc = null;
      renderer = null;
      cloned = null;
      ms = null;

      notifyListeners();

      // Keep LiveKit remote audio audible (original). Translated audio plays from the
      // OpenAI WebRTC renderer when it arrives — user hears both.
      _scheduleNextRefreshFromSession(session);
    } finally {
      if (renderer != null) {
        try {
          renderer.srcObject = null;
          await renderer.dispose();
        } catch (_) {}
      }
      if (cloned != null) {
        try {
          await cloned.stop();
        } catch (_) {}
      }
      if (ms != null) {
        try {
          await ms.dispose();
        } catch (_) {}
      }
      if (pc != null) {
        try {
          pc.onConnectionState = null;
          await pc.close();
        } catch (_) {}
      }
    }

    // If open failed without throwing (should not happen), never stay without a timer.
    if (_room != null &&
        identical(_room, roomRef) &&
        _route != null &&
        _route!.isConfigured &&
        _pc == null &&
        _refreshTimer == null &&
        !_busy) {
      debugPrint('OpenAi translation: pipeline ended without PC and without timer — retry');
      _scheduleNextRefreshRaw(const Duration(seconds: 4));
    }
  }

  Future<void> _refreshLoop() async {
    _refreshTimer = null;
    if (_room == null || _route == null || !_route!.isConfigured) return;
    if (_busy) {
      _scheduleNextRefreshRaw(const Duration(seconds: 3));
      return;
    }

    final remote = _resolveRemoteAudio() ?? _cachedRemote;
    final sid = _boundPublicationSid;
    if (remote == null || sid == null) {
      _scheduleNextRefreshRaw(const Duration(seconds: 4));
      return;
    }

    final roomRef = _room;
    if (roomRef == null) return;

    _busy = true;
    try {
      await _stopMedia();
      if (!identical(_room, roomRef)) return;
      await _openPipelineCore(remote, sid, roomRef);
    } catch (e, st) {
      debugPrint('OpenAi translation refresh: $e\n$st');
      await _stopMedia();
      _scheduleNextRefreshRaw(const Duration(seconds: 6));
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> attachToRoom(Room room, {required TranslationRoute route}) async {
    await detach();
    _room = room;
    _route = route;
    if (!route.isConfigured) return;

    _listener = room.createListener()
      ..on<TrackSubscribedEvent>(_onTrackSubscribed)
      ..on<TrackUnsubscribedEvent>(_onTrackUnsubscribed)
      ..on<ActiveSpeakersChangedEvent>(_onActiveSpeakersChanged);

    notifyListeners();

    _startWatchdog();

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
    if (_boundPublicationSid != null && sid == _boundPublicationSid) {
      unawaited(_onRemoteTrackEnded());
    }
  }

  Future<void> _onRemoteTrackEnded() async {
    _cancelScheduledRefresh();
    _stopWatchdog();
    _cachedRemote = null;
    _boundPublicationSid = null;
    _remoteVoiceHot = false;
    await _stopMedia();
  }

  Future<void> _bindRemoteAudio(RemoteAudioTrack remote, String publicationSid) async {
    final roomRef = _room;
    final route = _route;
    if (roomRef == null || route == null || !route.isConfigured) return;
    if (_busy) return;
    if (_pc != null && _boundPublicationSid == publicationSid) return;

    _cachedRemote = remote;
    _boundPublicationSid = publicationSid;

    _busy = true;
    try {
      if (_pc != null) {
        await _stopMedia();
      }
      if (!identical(_room, roomRef)) return;
      await _openPipelineCore(remote, publicationSid, roomRef);
    } catch (e, st) {
      debugPrint('OpenAi translation failed: $e\n$st');
      await _stopMedia();
      _scheduleNextRefreshRaw(const Duration(seconds: 6));
    } finally {
      _busy = false;
    }
  }

  Future<void> _fullDetachMediaAndTimer() async {
    _cancelScheduledRefresh();
    _stopWatchdog();
    _cachedRemote = null;
    _boundPublicationSid = null;
    _remoteVoiceHot = false;
    await _stopMedia();
  }

  @override
  Future<void> detach() async {
    await _fullDetachMediaAndTimer();
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
