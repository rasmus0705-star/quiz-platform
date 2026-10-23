// =============================================================
// sw.js – Service Worker (PWA offline-grundlag)
// v2: precacher nu selve app-sideren (ikke kun CSS/JS), så
//     holdspil-siden kan åbnes igen med dårligt mobilsignal.
// =============================================================

const CACHE = 'quiz-v2';
const PRECACHE = [
    '/',
    '/index.html',
    '/js/config.js',
    '/js/api.js',
    '/themes/standard.css',
    '/play/quiz.html',
    '/board/scoreboard.html',
    '/app/login.html',
    '/manifest.json',
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
    // Netværk først, fallback til cache (så GPS-opdateringer og
    // besvarelser altid prøver live-serveren først).
    e.respondWith(
        fetch(e.request)
            .then(res => {
                // Opdater cachen i baggrunden med friske sider, når nettet virker
                const copy = res.clone();
                caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {});
                return res;
            })
            .catch(() => caches.match(e.request))
    );
});
