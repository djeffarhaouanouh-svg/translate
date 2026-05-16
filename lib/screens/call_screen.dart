import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/app_strings.dart';
import '../services/auth_service.dart';
import '../services/profile_api.dart';
import '../services/usage_tracker.dart';
import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import '../translation/translation_route.dart';
import '../widgets/translation_feedback_ribbon.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.wsUrl,
    required this.jwt,
    required this.roomName,
    required this.displayName,
    required this.mySourceLang,
    required this.translation,
  });

  final String wsUrl;
  final String jwt;
  final String roomName;
  final String displayName;
  /// The local user's spoken language (BCP-47). The remote participant's
  /// language is read live from their LiveKit metadata.
  final String mySourceLang;
  final RealtimeTranslationPort translation;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Room? _room;
  String? _connectError;
  bool _connecting = true;
  bool _micOn = true;
  bool _camOn = true;
  /// When true, the local self-view fills the screen and the remote feed
  /// lives in the small PiP. Tap either to swap back.
  bool _selfMain = false;
  EventsListener<RoomEvent>? _roomEvents;

  /// The remote BCP-47 we have attached the translation pipeline with, so we
  /// only re-attach when it actually changes.
  String _attachedRemoteLang = '';
  bool _refreshingTranslation = false;
  /// Set when an event arrives while a refresh is in flight; we re-run once
  /// the in-flight call completes so the latest state is reflected.
  bool _refreshPending = false;

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  /// Parse `participant.metadata` (set as JSON in the JWT) and return the
  /// remote's `sourceLang` if present. Returns empty string on any failure.
  String _remoteLangFromMetadata(Participant p) {
    final raw = p.metadata?.trim() ?? '';
    if (raw.isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final v = decoded['sourceLang'];
        if (v is String) return v.trim();
      }
    } catch (e) {
      debugPrint('CallScreen: failed to parse remote metadata: $e');
    }
    return '';
  }

  /// Returns the first remote participant whose metadata carries a sourceLang.
  String _discoverRemoteLang(Room room) {
    for (final p in room.remoteParticipants.values) {
      final lang = _remoteLangFromMetadata(p);
      if (lang.isNotEmpty) return lang;
    }
    return '';
  }

  /// Re-attach the translation pipeline whenever the remote's language
  /// becomes known or changes. With an empty remote language the route is
  /// not configured and the pipeline stays idle. Serialized so concurrent
  /// participant / metadata events do not race the pipeline's own teardown.
  Future<void> _refreshTranslationBinding(Room room) async {
    if (_refreshingTranslation) {
      _refreshPending = true;
      return;
    }
    _refreshingTranslation = true;
    try {
      do {
        _refreshPending = false;
        final remoteLang = _discoverRemoteLang(room);
        if (remoteLang == _attachedRemoteLang) continue;
        _attachedRemoteLang = remoteLang;
        final route = TranslationRoute(
          sourceBcp47: widget.mySourceLang,
          targetBcp47: remoteLang,
        );
        await widget.translation.attachToRoom(room, route: route);
      } while (_refreshPending && mounted);
    } finally {
      _refreshingTranslation = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _start();
    unawaited(_initUsageTracking());
    UsageTracker.creditsExhausted.addListener(_onCreditsExhausted);
  }

  /// Pull the user's current credit balance and start the call timer. The
  /// call itself runs regardless — we just decide whether translation is
  /// allowed on top.
  Future<void> _initUsageTracking() async {
    final uid = AuthService.currentUserId;
    if (uid.isEmpty) return;
    final p = await ProfileApi.fetchById(uid);
    if (!mounted || p == null) return;
    UsageTracker.start(userId: uid, initialCredits: p.creditsSeconds);
    if (UsageTracker.isDisabled) return;
    if (p.creditsSeconds <= 0) {
      // Already empty before the call started — kill translation now.
      await widget.translation.detach();
    }
  }

  /// Triggered when credits hit 0 mid-call. We detach the translation
  /// pipeline so the OpenAI session stops billing, but leave the LiveKit
  /// connection alone so people can keep talking (untranslated).
  void _onCreditsExhausted() {
    if (!UsageTracker.creditsExhausted.value) return;
    unawaited(widget.translation.detach());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.t('credits_exhausted_banner')),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _start() async {
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      setState(() {
        _connecting = false;
        _connectError = 'Camera and microphone permission are required to join the call.';
      });
      return;
    }

    final room = Room();
    try {
      await room.connect(widget.wsUrl, widget.jwt);
      await room.localParticipant?.setCameraEnabled(true);
      // Disable echo cancellation / noise suppression / AGC: when two devices
      // co-locate physically they form a feedback loop that aggressive EC
      // breaks by auto-muting one publisher's mic — which manifests as
      // "only 1 of 2 can publish at a time" on the call. Trading EC for
      // deterministic bidirectional publishing.
      await room.localParticipant?.setMicrophoneEnabled(
        true,
        audioCaptureOptions: const AudioCaptureOptions(
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false,
        ),
      );
      // First attach with whatever remote-lang we already know (often nothing
      // yet). Refreshed dynamically as participants join / metadata arrives.
      await _refreshTranslationBinding(room);
      room.addListener(_onRoomChanged);
      _roomEvents = room.createListener()
        ..on<TrackSubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackUnsubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<LocalTrackPublishedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<ParticipantConnectedEvent>((_) {
          unawaited(_refreshTranslationBinding(room));
          if (mounted) setState(() {});
        })
        ..on<ParticipantDisconnectedEvent>((_) {
          unawaited(_refreshTranslationBinding(room));
          if (mounted) setState(() {});
        })
        ..on<ParticipantMetadataUpdatedEvent>((_) {
          unawaited(_refreshTranslationBinding(room));
          if (mounted) setState(() {});
        });
      if (mounted) {
        setState(() {
          _room = room;
          _connecting = false;
          _micOn = true;
          _camOn = true;
        });
      }
    } catch (e) {
      await room.disconnect();
      if (mounted) {
        setState(() {
          _connecting = false;
          _connectError = e.toString();
        });
      }
    }
  }

  RemoteParticipant? _primaryRemote(Room room) {
    final it = room.remoteParticipants.values.iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }

  String _remoteDisplayName(RemoteParticipant? p) {
    if (p == null) return '';
    final n = p.name.trim();
    if (n.isNotEmpty) return n;
    final id = p.identity;
    if (id.length > 14) return '${id.substring(0, 14)}…';
    return id;
  }

  /// Whether we should draw the small PiP at all. We always show it as
  /// long as a participant exists on the side that PiP would represent,
  /// even when their camera is off — the cell falls back to an avatar
  /// placeholder so the layout doesn't collapse mid-call.
  bool _pipFeedAvailable({
    VideoTrack? local,
    VideoTrack? remote,
    bool hasRemote = false,
  }) {
    if (_selfMain) return hasRemote;
    return true; // local participant always exists when call is up
  }

  VideoTrack? _remoteVideo(Room room) {
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (t != null) return t;
      }
    }
    return null;
  }

  VideoTrack? _localVideo(Room room) {
    final lp = room.localParticipant;
    if (lp == null) return null;
    for (final pub in lp.videoTrackPublications) {
      final t = pub.track;
      if (t != null) return t;
    }
    return null;
  }

  Future<void> _toggleMic() async {
    final room = _room;
    if (room == null) return;
    final next = !_micOn;
    await room.localParticipant?.setMicrophoneEnabled(next);
    if (mounted) setState(() => _micOn = next);
  }

  Future<void> _toggleCam() async {
    final room = _room;
    if (room == null) return;
    final next = !_camOn;
    await room.localParticipant?.setCameraEnabled(next);
    if (mounted) setState(() => _camOn = next);
  }

  Future<void> _hangUp() async {
    await widget.translation.detach();
    await _roomEvents?.dispose();
    _roomEvents = null;
    final r = _room;
    _room = null;
    if (r != null) {
      r.removeListener(_onRoomChanged);
      await r.disconnect();
      await r.dispose();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WhatsAppCallTheme.bar,
        title: const Text('Leave call?', style: TextStyle(color: WhatsAppCallTheme.strongText)),
        content: const Text(
          'You will disconnect from this room.',
          style: TextStyle(color: WhatsAppCallTheme.subtleText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: WhatsAppCallTheme.danger),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) await _hangUp();
  }

  @override
  void dispose() {
    UsageTracker.creditsExhausted.removeListener(_onCreditsExhausted);
    // Flush whatever seconds were used since the last tick before tearing
    // everything down. Fire-and-forget — disposing a State must be sync.
    unawaited(UsageTracker.stop());
    final ev = _roomEvents;
    _roomEvents = null;
    if (ev != null) unawaited(ev.dispose());
    final r = _room;
    _room = null;
    if (r != null) {
      r.removeListener(_onRoomChanged);
      unawaited(() async {
        await widget.translation.detach();
        await r.disconnect();
        await r.dispose();
      }());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_connectError != null) {
      return Scaffold(
        backgroundColor: WhatsAppCallTheme.scaffold,
        appBar: AppBar(
          backgroundColor: WhatsAppCallTheme.scaffold,
          foregroundColor: WhatsAppCallTheme.strongText,
          title: const Text('Could not join'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: WhatsAppCallTheme.danger.withValues(alpha: 0.9)),
                const SizedBox(height: 16),
                Text(
                  _connectError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WhatsAppCallTheme.subtleText, height: 1.4),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_connecting || _room == null) {
      return Scaffold(
        backgroundColor: WhatsAppCallTheme.scaffold,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 40,
                width: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: WhatsAppCallTheme.accent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Connecting to ${widget.roomName}…',
                style: const TextStyle(
                  color: WhatsAppCallTheme.subtleText,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final room = _room!;
    final remote = _remoteVideo(room);
    final local = _localVideo(room);
    final remoteCount = room.remoteParticipants.length;
    final peer = _primaryRemote(room);
    final peerName = _remoteDisplayName(peer);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _confirmLeave();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Main view priority:
                //   1. Remote video, if the remote has a published camera.
                //   2. "Camera off" placeholder for the remote (their tile
                //      stays visible, audio keeps flowing).
                //   3. Self-main local video when explicitly swapped.
                //   4. Local "camera off" placeholder when self-main + cam off.
                //   5. Empty-room placeholder if no remote yet.
                if (_selfMain && local != null && _camOn)
                  GestureDetector(
                    onTap: remoteCount > 0
                        ? () => setState(() => _selfMain = false)
                        : null,
                    child: VideoTrackRenderer(
                      local,
                      fit: VideoViewFit.cover,
                      mirrorMode: VideoViewMirrorMode.mirror,
                    ),
                  )
                else if (_selfMain && remoteCount > 0)
                  // Self-main but local cam off → still let the user tap to
                  // swap back to the remote. Show a "your camera is off"
                  // placeholder.
                  GestureDetector(
                    onTap: () => setState(() => _selfMain = false),
                    child: const _CameraOffTile(label: 'Your camera is off'),
                  )
                else if (remote != null)
                  VideoTrackRenderer(
                    remote,
                    fit: VideoViewFit.cover,
                    mirrorMode: VideoViewMirrorMode.off,
                  )
                else if (remoteCount > 0)
                  // Remote is connected but has their camera off — keep the
                  // tile visible, the call (audio + translation) is still up.
                  _CameraOffTile(
                    label: peerName.isEmpty
                        ? 'Camera off'
                        : '$peerName · camera off',
                  )
                else
                  Container(
                    color: WhatsAppCallTheme.surface,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person, size: 80, color: Colors.white.withValues(alpha: 0.28)),
                        const SizedBox(height: 14),
                        Text(
                          'Waiting for the other person…',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Share the same room name on another device.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.translation.translationListenable != null)
                  Positioned(
                    left: 10,
                    right: 10,
                    top: MediaQuery.paddingOf(context).top + 12,
                    child: ListenableBuilder(
                      listenable: widget.translation.translationListenable!,
                      builder: (context, _) {
                        return TranslationFeedbackRibbon(
                          phase: widget.translation.translationFeedbackPhase,
                          remoteHot: widget.translation.translationRemoteVoiceHot,
                          remoteParticipantCount: remoteCount,
                        );
                      },
                    ),
                  ),
                if (peerName.isNotEmpty && remote != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 132,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Text(
                              peerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // PiP: shows whichever feed is NOT the main one. Tap to
                // swap. Always rendered when the corresponding party
                // exists, even if their camera is off — falls back to a
                // tiny "camera off" tile so the layout doesn't pop.
                if (_pipFeedAvailable(
                    local: local, remote: remote, hasRemote: remoteCount > 0))
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 52,
                    right: 12,
                    width: 118,
                    height: 176,
                    child: GestureDetector(
                      onTap: () => setState(() => _selfMain = !_selfMain),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white30, width: 1.5),
                            color: Colors.black,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: () {
                            // PiP shows the "not main" side.
                            if (_selfMain) {
                              // Main = local, PiP = remote.
                              if (remote != null) {
                                return VideoTrackRenderer(
                                  remote,
                                  fit: VideoViewFit.cover,
                                  mirrorMode: VideoViewMirrorMode.off,
                                );
                              }
                              return const _CameraOffTile(compact: true);
                            }
                            // Main = remote, PiP = local.
                            if (local != null && _camOn) {
                              return VideoTrackRenderer(
                                local,
                                fit: VideoViewFit.cover,
                                mirrorMode: VideoViewMirrorMode.mirror,
                              );
                            }
                            return const _CameraOffTile(compact: true);
                          }(),
                        ),
                      ),
                    ),
                  ),
                if (widget.translation.translationListenable != null)
                  ListenableBuilder(
                    listenable: widget.translation.translationListenable!,
                    builder: (context, _) {
                      final overlay = widget.translation.buildTranslationAudioOverlay();
                      return overlay ?? const SizedBox.shrink();
                    },
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(16, 28, 16, 16 + MediaQuery.paddingOf(context).bottom),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.82),
                          Colors.black.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RoundCallButton(
                          icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                          label: _micOn ? 'Mute' : 'Unmute',
                          background: WhatsAppCallTheme.bar,
                          onTap: _toggleMic,
                        ),
                        _RoundCallButton(
                          icon: _camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                          label: _camOn ? 'Video' : 'Off',
                          background: WhatsAppCallTheme.bar,
                          onTap: _toggleCam,
                        ),
                        _RoundCallButton(
                          icon: Icons.call_end_rounded,
                          label: 'End',
                          background: WhatsAppCallTheme.danger,
                          onTap: _hangUp,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

class _RoundCallButton extends StatelessWidget {
  const _RoundCallButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: Colors.black54,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 11),
        ),
      ],
    );
  }
}

/// Placeholder rendered in place of a video feed when the participant's
/// camera is off (or the local user has theirs off in a self-main view).
/// The call audio + translation keep running underneath; this just keeps
/// the visual cell from collapsing when video drops mid-call.
class _CameraOffTile extends StatelessWidget {
  const _CameraOffTile({this.label, this.compact = false});

  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 28.0 : 64.0;
    final fontSize = compact ? 10.0 : 14.0;
    return Container(
      color: WhatsAppCallTheme.surface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.videocam_off_outlined,
            size: iconSize,
            color: Colors.white.withValues(alpha: 0.55),
          ),
          if (label != null && !compact) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                label!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
