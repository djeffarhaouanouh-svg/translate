import 'package:flutter/foundation.dart';

import '../services/translation_api.dart';
import 'mistral_realtime_translation.dart';
import 'openai_realtime_translation.dart';
import 'realtime_translation_port.dart';

/// Picks the right realtime translation implementation by asking the
/// backend which provider is configured.
///
/// Returns OpenAI by default (and on any backend error) so the existing
/// pipeline stays the safe fallback.
Future<RealtimeTranslationPort> createRealtimeTranslation() async {
  try {
    final info = await fetchTranslationProvider();
    if (info.provider.toLowerCase() == 'mistral') {
      debugPrint('translation: using Mistral provider (backend bot)');
      return MistralRealtimeTranslation();
    }
  } catch (e) {
    debugPrint('translation: provider lookup failed → defaulting to OpenAI: $e');
  }
  debugPrint('translation: using OpenAI provider (WebRTC client→client)');
  return OpenAiRealtimeTranslation();
}
