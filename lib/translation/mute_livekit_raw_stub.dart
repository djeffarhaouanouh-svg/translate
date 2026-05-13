import 'package:livekit_client/livekit_client.dart';

/// On native we cannot reliably mute only LiveKit speaker output without risking
/// the cloned track fed to OpenAI. Web uses [mute_livekit_raw_web.dart] instead.
void muteLiveKitRawRemotePlayback(RemoteAudioTrack _) {}
