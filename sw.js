// =============================================================
// sw.js – Service Worker (PWA offline-grundlag)
// =============================================================

const CACHE = 'quiz-v1';
const PRECACHE = [
    '/',
    '/js/config.js',
    '/js/api.js',
    '/themes/standard.css',
];

self.addEventListener('install', e => {
    e.waitUntil(
        caches.open(CACHE).then(c => c.addAll(PRECACHE))
    );
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
    // Netværk først, fallback til cache
    e.respondWith(
        fetch(e.request).catch(() => caches.match(e.request))
    );
});
