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
/// Only [TrackSource.microphone] (or unknown-labeled mic) is sent to OpenAI — never
/// [TrackSource.screenShareAudio], so tab/system capture is not translated (avoids re-feeding
/// TTS or call audio published as screen-audio).
///
/// Translated audio plays on a **second** WebRTC connection; OS echo cancellation may not
/// fully remove that playback from **your** mic. Prefer headphones / lower speaker volume
/// so the remote party does not send leaked translation back into this pipeline.
///
/// Renews the OpenAI side before the ephemeral credential expires. Renewals build the new
/// pipeline in parallel with the old one and only swap once it reaches Connected, so the
/// user does not hear a silence gap during session rollover.
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
      // Seamless renewal needs headroom: build new pipeline, wait for it to
      // reach Connected, then swap. 25s comfortably covers SDP + ICE.
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
          if (t is RemoteAudioTrack && _eligibleRemoteAudioForTranslation(t)) return t;
        }
      }
    }
    return null;
  }

  /// Never use screen-share / system-capture audio for speech translation.
  static bool _eligibleRemoteAudioForTranslation(RemoteAudioTrack t) =>
      t.source != TrackSource.screenShareAudio;

  /// Prefer the remote **microphone** so we do not translate screen/tab audio (which can
  /// include our own translated output played on speakers elsewhere in the graph).
  static ({RemoteAudioTrack track, String sid})? _pickTranslationRemoteTrack(Room room) {
    RemoteAudioTrack? fallback;
    String? fallbackSid;

    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        final t = pub.track;
        if (t is! RemoteAudioTrack) continue;
        if (!_eligibleRemoteAudioForTranslation(t)) continue;
        if (t.source == TrackSource.microphone) {
          return (track: t, sid: pub.sid);
        }
        if (fallback == null) {
          fallback = t;
          fallbackSid = pub.sid;
        }
      }
    }

    if (fallback != null && fallbackSid != null) {
      return (track: fallback, sid: fallbackSid);
    }
    return null;
  }

  void _maybeUpgradeTranslationBinding() {
    final room = _room;
    final route = _route;
    if (room == null || route == null || !route.isConfigured) return;

    final pick = _pickTranslationRemoteTrack(room);
    if (pick == null) {
      if (_boundPublicationSid != null || _pc != null) {
        unawaited(_onRemoteTrackEnded());
      }
      return;
    }

    if (_busy) return;
    if (_pc != null && _boundPublicationSid == pick.sid) return;
    unawaited(_bindRemoteAudio(pick.track, pick.sid));
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

  /// Build a new translation pipeline without installing it as the active one.
  /// The inbound translated audio is held muted (via [_InboundAudioCtl]) until
  /// the caller installs the handle, so an overlapping seamless renewal does
  /// not double up audio with the still-playing old pipeline.
  Future<_PipelineHandle> _buildPipeline(
    RemoteAudioTrack remote,
    String publicationSid,
    Room roomRef,
  ) async {
    final route = _route;
    if (route == null || !route.isConfigured) {
      throw StateError('not_configured');
    }

    final session = await fetchTranslationSession(outputLanguage: route.sourceBcp47);
    if (!identical(_room, roomRef)) {
      throw StateError('room_changed_after_session');
    }

    final secret = pickClientSecret(session);
    if (secret == null || secret.isEmpty) {
      debugPrint('OpenAi translation: no client_secret in session response');
      throw StateError('missing client_secret');
    }

    final connectedCompleter = Completer<bool>();
    final inboundCtl = _InboundAudioCtl();

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

      final pcRef = pc;
      pcRef.onConnectionState = (RTCPeerConnectionState s) {
        // Only drive the live reconnect logic when this pc is the active one;
        // during a seamless build we are not yet `_pc`.
        if (identical(pcRef, _pc)) {
          _onPcConnectionState(s);
        }
        if (!connectedCompleter.isCompleted) {
          if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
            connectedCompleter.complete(true);
          } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
              s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
            connectedCompleter.complete(false);
          }
        }
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
        if (event.track.kind == 'audio') {
          inboundCtl.attach(event.track);
        }
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

      final handle = _PipelineHandle(
        pc: pc,
        renderer: renderer,
        clonedSource: cloned,
        localStream: ms,
        publicationSid: publicationSid,
        session: session,
        connectedFuture: connectedCompleter.future,
        inboundCtl: inboundCtl,
      );
      pc = null;
      renderer = null;
      cloned = null;
      ms = null;
      return handle;
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
  }

  /// Install a freshly built handle as the active pipeline. Caller must have
  /// torn down any prior pipeline; for hot renewals use [_seamlessRenew].
  void _installHandle(_PipelineHandle h) {
    _pc = h.pc;
    _renderer = h.renderer;
    _clonedSource = h.clonedSource;
    _localStream = h.localStream;
    _boundPublicationSid = h.publicationSid;
    h.inboundCtl.unmute();
    notifyListeners();
    _scheduleNextRefreshFromSession(h.session);
  }

  Future<void> _disposeHandle(_PipelineHandle h) async {
    try {
      h.pc.onConnectionState = null;
    } catch (_) {}
    try {
      await h.pc.close();
    } catch (_) {}
    try {
      await h.localStream.dispose();
    } catch (_) {}
    try {
      await h.clonedSource.stop();
    } catch (_) {}
    try {
      h.renderer.srcObject = null;
      await h.renderer.dispose();
    } catch (_) {}
  }

  Future<void> _disposeOldResources({
    RTCPeerConnection? pc,
    MediaStream? localStream,
    MediaStreamTrack? clonedSource,
    RTCVideoRenderer? renderer,
  }) async {
    if (pc != null) {
      try {
        pc.onConnectionState = null;
      } catch (_) {}
      try {
        await pc.close();
      } catch (_) {}
    }
    if (localStream != null) {
      try {
        await localStream.dispose();
      } catch (_) {}
    }
    if (clonedSource != null) {
      try {
        await clonedSource.stop();
      } catch (_) {}
    }
    if (renderer != null) {
      try {
        renderer.srcObject = null;
        await renderer.dispose();
      } catch (_) {}
    }
  }

  /// Cold-start path. Caller must have ensured no prior pipeline is active.
  Future<void> _openPipelineCore(
    RemoteAudioTrack remote,
    String publicationSid,
    Room roomRef,
  ) async {
    final h = await _buildPipeline(remote, publicationSid, roomRef);
    if (!identical(_room, roomRef)) {
      await _disposeHandle(h);
      throw StateError('room_changed_after_build');
    }
    _installHandle(h);

    // Defensive: never stay without a refresh timer.
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

  /// Hot-renew path. Builds a new pipeline alongside the current one, waits
  /// for the new pc to reach Connected, then atomically swaps refs and
  /// disposes the old pipeline in the background. The user does not hear a
  /// gap because the old pipeline keeps producing audio until the swap.
  ///
  /// Returns false if the new pipeline could not be brought up; the old
  /// pipeline is preserved so audio continues until the next attempt.
  Future<bool> _seamlessRenew(
    RemoteAudioTrack remote,
    String publicationSid,
    Room roomRef,
  ) async {
    _PipelineHandle handle;
    try {
      handle = await _buildPipeline(remote, publicationSid, roomRef);
    } catch (e, st) {
      debugPrint('OpenAi translation seamless build failed: $e\n$st');
      return false;
    }

    if (!identical(_room, roomRef)) {
      await _disposeHandle(handle);
      return false;
    }

    final connected = await handle.connectedFuture.timeout(
      const Duration(seconds: 6),
      onTimeout: () => false,
    );

    if (!identical(_room, roomRef)) {
      await _disposeHandle(handle);
      return false;
    }

    if (!connected) {
      debugPrint('OpenAi translation seamless: new pc did not connect in time');
      await _disposeHandle(handle);
      return false;
    }

    // Atomic swap.
    final oldPc = _pc;
    final oldRenderer = _renderer;
    final oldStream = _localStream;
    final oldCloned = _clonedSource;

    _pc = handle.pc;
    _renderer = handle.renderer;
    _clonedSource = handle.clonedSource;
    _localStream = handle.localStream;
    _boundPublicationSid = handle.publicationSid;
    // The new pc just reached Connected; mark it so the next state callback
    // does not fire a second haptic.
    _wasPcConnected = true;

    handle.inboundCtl.unmute();

    notifyListeners();
    _scheduleNextRefreshFromSession(handle.session);

    unawaited(_disposeOldResources(
      pc: oldPc,
      localStream: oldStream,
      clonedSource: oldCloned,
      renderer: oldRenderer,
    ));

    return true;
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
      if (_pc != null) {
        final ok = await _seamlessRenew(remote, sid, roomRef);
        if (!ok) {
          // Old pipeline is still running; retry seamless renewal shortly
          // rather than tearing it down (which would inflict the gap we are
          // trying to avoid).
          _scheduleNextRefreshRaw(const Duration(seconds: 4));
        }
      } else {
        await _openPipelineCore(remote, sid, roomRef);
      }
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

    _maybeUpgradeTranslationBinding();
  }

  void _onTrackSubscribed(TrackSubscribedEvent e) {
    final t = e.track;
    if (t is RemoteAudioTrack && _eligibleRemoteAudioForTranslation(t)) {
      _maybeUpgradeTranslationBinding();
    }
  }

  void _onTrackUnsubscribed(TrackUnsubscribedEvent e) {
    final t = e.track;
    if (t is RemoteAudioTrack) {
      _maybeUpgradeTranslationBinding();
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
    if (!_eligibleRemoteAudioForTranslation(remote)) return;
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

/// Resolves the race between the WebRTC onTrack callback (which may fire
/// before or after the pipeline is installed) and the install path. The
/// inbound translated audio stays muted until [unmute] is called, so a
/// pipeline built for a seamless renewal cannot start playing alongside the
/// still-active old pipeline.
class _InboundAudioCtl {
  MediaStreamTrack? _track;
  bool _unmuted = false;

  void attach(MediaStreamTrack t) {
    _track = t;
    if (!_unmuted) {
      try {
        t.enabled = false;
      } catch (_) {}
    }
  }

  void unmute() {
    _unmuted = true;
    final t = _track;
    if (t != null) {
      try {
        t.enabled = true;
      } catch (_) {}
    }
  }
}

class _PipelineHandle {
  _PipelineHandle({
    required this.pc,
    required this.renderer,
    required this.clonedSource,
    required this.localStream,
    required this.publicationSid,
    required this.session,
    required this.connectedFuture,
    required this.inboundCtl,
  });
  final RTCPeerConnection pc;
  final RTCVideoRenderer renderer;
  final MediaStreamTrack clonedSource;
  final MediaStream localStream;
  final String publicationSid;
  final Map<String, dynamic> session;
  /// Completes true on Connected, false on Failed/Closed (or via timeout).
  final Future<bool> connectedFuture;
  final _InboundAudioCtl inboundCtl;
}
