// =============================================================
// sw.js – Service Worker (PWA offline-grundlag)
// v5 (hjælp + tjekliste kan åbnes uden dækning; v4: biblioteker og skrifttyper ligger nu på egen server (vendor/, fonts/) og forhåndscaches,
//     så spillesiden stadig kan åbne ved dårlig dækning. Cacher KUN egne filer –
//     aldrig Supabase-kald eller kort-tiles. Netværk først, cache som nødløsning.
// =============================================================

const CACHE = 'jagten-v5';
const FILES = [
  'index.html',
  'privatliv.html',
  'hjaelp.html',
  'tjekliste.html',
  'js/config.js',
  'js/api.js',
  'js/map-config.js',
  'js/map.js',
  'js/themes.js',
  'play/quiz.html',
  'board/scoreboard.html',
  'app/login.html',
  'vendor/supabase.js',
  'vendor/NoSleep.min.js',
  'vendor/leaflet/leaflet.js',
  'vendor/leaflet/leaflet.css',
  'vendor/maplibre/maplibre-gl.js',
  'vendor/maplibre/maplibre-gl.css',
  'vendor/maplibre/leaflet-maplibre-gl.js',
  'fonts/fonts.css',
  'fonts/syne-latin-700-normal.woff2',
  'fonts/syne-latin-800-normal.woff2',
  'fonts/inter-latin-400-normal.woff2',
  'fonts/inter-latin-600-normal.woff2',
  'fonts/inter-latin-700-normal.woff2',
  'fonts/fredoka-latin-500-normal.woff2',
  'fonts/fredoka-latin-600-normal.woff2',
  'fonts/playfair-display-latin-700-normal.woff2',
  'fonts/special-elite-latin-400-normal.woff2',
  'manifest.json',
  'favicon.svg',
  'icons/icon-192.png',
  'icons/apple-touch-icon.png',
  '404.html',
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
