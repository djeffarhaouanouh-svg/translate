/// No-op implementation used on native targets (mobile / desktop), where
/// incoming-call UX is already handled by the OS / the in-app dialog.
abstract final class CallAlert {
  static void start({String? callerName}) {}
  static void stop() {}
}
