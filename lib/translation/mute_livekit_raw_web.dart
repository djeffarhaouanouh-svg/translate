import 'package:livekit_client/livekit_client.dart';
import 'package:web/web.dart' as web;

/// Prefer muting the LiveKit-managed HTML audio element so the underlying
/// receiver track keeps feeding the translation peer connection.
void muteLiveKitRawRemotePlayback(RemoteAudioTrack track) {
  final id = 'livekit_audio_${track.getCid()}';
  final el = web.document.getElementById(id);
  if (el case final web.HTMLAudioElement a) {
    a.volume = 0;
  }
}
