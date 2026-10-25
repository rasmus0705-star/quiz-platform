// =============================================================
// sw.js – Service Worker (PWA offline-grundlag)
// v3: relative stier (virker på GitHub Pages under /quiz-platform/),
//     cacher KUN egne filer – aldrig Supabase-kald eller kort-tiles.
// =============================================================

const CACHE = 'jagten-v3';
const FILES = [
  'index.html',
  'js/config.js',
  'js/api.js',
  'play/quiz.html',
  'board/scoreboard.html',
  'app/login.html',
  'manifest.json',
];

self.addEventListener('install', e => {
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // én fil der mangler må ikke vælte hele installationen
    await Promise.all(FILES.map(f =>
      cache.add(new URL(f, self.registration.scope)).catch(() => {})
    ));
  })());
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  const req = e.request;
  const url = new URL(req.url);

  // Kun egne GET-filer. Supabase (API, storage, functions), tiles og CDN går direkte til nettet.
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;

  // Netværk først (altid friske filer efter et push) – cache som nødløsning ved dårligt signal
  e.respondWith(
    fetch(req)
      .then(res => {
        if (res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
        }
        return res;
      })
      .catch(() => caches.match(req))
  );
});
