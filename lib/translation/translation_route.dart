/// Language routing for a future OpenAI Realtime (or other) translation pipeline.
class TranslationRoute {
  const TranslationRoute({
    required this.sourceBcp47,
    required this.targetBcp47,
  });

  /// Empty strings mean "not configured" — UI can hide translation controls.
  final String sourceBcp47;
  final String targetBcp47;

  bool get isConfigured =>
      sourceBcp47.trim().isNotEmpty && targetBcp47.trim().isNotEmpty;
}
