import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';

import 'translation_route.dart';

/// Abstraction for bidirectional realtime speech translation.
///
/// Next steps (server-side recommended):
/// - Create ephemeral OpenAI Realtime sessions in `backend` (never ship API keys in Flutter).
/// - Stream microphone audio to your bridge; receive translated audio or text.
/// - Optionally mix translated audio or publish via a second LiveKit track / data channel.
abstract class RealtimeTranslationPort {
  Future<void> attachToRoom(
    Room room, {
    required TranslationRoute route,
  });

  Future<void> detach();

  /// When non-null, widgets can wrap [buildTranslationAudioOverlay] in a
  /// [ListenableBuilder] so hidden WebRTC playback rebuilds.
  Listenable? get translationListenable => null;

  /// e.g. tiny [RTCVideoView] for translated remote audio (OpenAI path).
  Widget? buildTranslationAudioOverlay() => null;
}

/// Default: no processing; keeps call path simple until you add an adapter.
class NoOpRealtimeTranslation implements RealtimeTranslationPort {
  const NoOpRealtimeTranslation();
  @override
  Future<void> attachToRoom(
    Room room, {
    required TranslationRoute route,
  }) async {}

  @override
  Future<void> detach() async {}

  @override
  Listenable? get translationListenable => null;

  @override
  Widget? buildTranslationAudioOverlay() => null;
}
