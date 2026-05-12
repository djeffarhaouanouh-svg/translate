import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/whatsapp_call_theme.dart';
import '../translation/realtime_translation_port.dart';
import '../translation/translation_route.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.wsUrl,
    required this.jwt,
    required this.roomName,
    required this.displayName,
    required this.translationRoute,
    required this.translation,
  });

  final String wsUrl;
  final String jwt;
  final String roomName;
  final String displayName;
  final TranslationRoute translationRoute;
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
  EventsListener<RoomEvent>? _roomEvents;

  void _onRoomChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      setState(() {
        _connecting = false;
        _connectError = 'Camera and microphone permission are required.';
      });
      return;
    }

    final room = Room();
    try {
      await room.connect(widget.wsUrl, widget.jwt);
      await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);
      await widget.translation.attachToRoom(
        room,
        route: widget.translationRoute,
      );
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
          if (mounted) setState(() {});
        })
        ..on<ParticipantDisconnectedEvent>((_) {
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

  @override
  void dispose() {
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
        appBar: AppBar(leading: CloseButton(onPressed: () => Navigator.pop(context))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _connectError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: WhatsAppCallTheme.danger),
            ),
          ),
        ),
      );
    }

    if (_connecting || _room == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final room = _room!;
    final remote = _remoteVideo(room);
    final local = _localVideo(room);
    final remoteCount = room.remoteParticipants.length;
    final connection = room.connectionState;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (remote != null)
              VideoTrackRenderer(
                remote,
                fit: VideoViewFit.cover,
                mirrorMode: VideoViewMirrorMode.off,
              )
            else
              Container(
                color: WhatsAppCallTheme.surface,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person, size: 72, color: Colors.white.withValues(alpha: 0.35)),
                    const SizedBox(height: 12),
                    Text(
                      remoteCount == 0 ? 'Waiting for the other person…' : 'No video yet…',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 16),
                    ),
                  ],
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _hangUp,
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.roomName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${widget.displayName} · ${_connectionLabel(connection)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (remoteCount > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: WhatsAppCallTheme.danger.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '2+ people',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (local != null && _camOn)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 56,
                right: 12,
                width: 112,
                height: 168,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      color: Colors.black,
                    ),
                    child: VideoTrackRenderer(
                      local,
                      fit: VideoViewFit.cover,
                      mirrorMode: VideoViewMirrorMode.mirror,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.black.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundCallButton(
                      icon: _micOn ? Icons.mic : Icons.mic_off,
                      label: _micOn ? 'Mute' : 'Unmute',
                      background: WhatsAppCallTheme.bar,
                      onTap: _toggleMic,
                    ),
                    _RoundCallButton(
                      icon: _camOn ? Icons.videocam : Icons.videocam_off,
                      label: _camOn ? 'Video' : 'Off',
                      background: WhatsAppCallTheme.bar,
                      onTap: _toggleCam,
                    ),
                    _RoundCallButton(
                      icon: Icons.call_end,
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
    );
  }

  String _connectionLabel(ConnectionState s) {
    switch (s) {
      case ConnectionState.connected:
        return 'Connected';
      case ConnectionState.connecting:
        return 'Connecting…';
      case ConnectionState.reconnecting:
        return 'Reconnecting…';
      case ConnectionState.disconnected:
        return 'Disconnected';
    }
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
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
        ),
      ],
    );
  }
}
