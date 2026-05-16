// Service worker dedicated to push notifications. Lives next to (not
// instead of) the Flutter web service worker — Flutter's SW is
// generated at build time and we don't want to fight it. We register
// this one with a non-root scope so they don't collide.
//
// Payload shape (set by backend/notify.js):
//   {
//     title, body,
//     type:  'message' | 'friend_request' | 'incoming_call' | 'like',
//     data:  { conversationId?, callerId?, … }
//   }

self.addEventListener('install', (event) => {
  // Activate immediately so the first registration starts handling
  // pushes without a page reload.
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    // Fall back to the raw text body if the sender didn't JSON-encode.
    try {
      payload = { title: 'Swayco', body: event.data?.text() || '' };
    } catch (_) {
      payload = { title: 'Swayco', body: '' };
    }
  }

  const title = payload.title || 'Swayco';
  const body = payload.body || '';
  const type = payload.type || 'generic';
  const data = payload.data || {};

  // Incoming-call pushes get a tight TTL + high-attention vibration
  // pattern. Everything else uses the default OS sound.
  const isCall = type === 'incoming_call';

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      tag: type === 'message' && data.conversationId
        ? `msg-${data.conversationId}`
        : type,
      renotify: isCall, // ring through coalescing for calls
      requireInteraction: isCall,
      icon: '/icons/Icon-192.png',
      badge: '/favicon.png',
      vibrate: isCall ? [300, 200, 300, 200, 300] : [120],
      data: { type, ...data, openedAt: Date.now() },
    }),
  );
});

// When the user clicks a notification, focus an existing tab if open,
// otherwise open a fresh one at the app root. (We could deep-link to
// the relevant conversation / caller, but that requires the Flutter
// router to read the URL on cold start — keep this simple for now.)
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    (async () => {
      const all = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      for (const client of all) {
        if ('focus' in client) {
          await client.focus();
          return;
        }
      }
      if (self.clients.openWindow) {
        await self.clients.openWindow('/');
      }
    })(),
  );
});
