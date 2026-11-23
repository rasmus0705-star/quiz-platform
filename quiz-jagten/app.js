'use strict';
/* Quizjagten – PWA med solo, duel og selskabsspil.
   Spørgsmål læses fra questions.json. Live-spil bruger Supabase Realtime (kun broadcast/presence, ingen tabeller). */

const CFG = Object.assign({
  APP_NAVN: 'Quizjagten', VIS_KLADDER: false,
  SUPABASE_URL: '', SUPABASE_ANON_KEY: '', LIVE_SEKUNDER: 20
}, window.QUIZ_CONFIG || {});

const KAT = {
  historie: 'Historie', geografi: 'Geografi', natur: 'Natur', sport: 'Sport',
  underholdning: 'Underholdning', videnskab: 'Videnskab', sprog_kultur: 'Sprog & kultur', mad_drikke: 'Mad & drikke', blandet: 'Blandet'
};
const NIV = { 1: 'Let', 2: 'Middel', 3: 'Svær', 4: 'Ekspert' };
const POINT = { 1: 1, 2: 2, 3: 3, 4: 5 };
const SHAPES = ['▲', '◆', '●', '■'];
const SUPABASE_JS = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js';
const QR_JS = 'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js';

let ALL = [];      // hele banken (til udfordrings-links)
let BANK = [];     // kun spilbare spørgsmål (alle typer)
let BANK_MC = [];  // spilbare med svarmuligheder (mc + sandt/falsk)
let cleanup = null;
let installPrompt = null;
let wakeLock = null;

/* ---------- Hjælpere ---------- */
const app = document.getElementById('app');
const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { } }
};

function render(html) {
  app.innerHTML = html;
  window.scrollTo(0, 0);
  $$('[data-home]').forEach(b => b.addEventListener('click', goHome));
}
function goHome() {
  if (cleanup) { try { cleanup(); } catch { } cleanup = null; }
  releaseWake();
  home();
}
function toast(msg) {
  const t = $('#toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(toast._t); toast._t = setTimeout(() => t.classList.remove('show'), 2600);
}
function loadScript(src) {
  return new Promise((res, rej) => {
    if ([...document.scripts].some(s => s.src === src)) return res();
    const s = document.createElement('script'); s.src = src; s.onload = res; s.onerror = () => rej(new Error('Kunne ikke hente ' + src));
    document.head.appendChild(s);
  });
}
async function keepAwake() { try { wakeLock = await navigator.wakeLock?.request('screen'); } catch { } }
function releaseWake() { try { wakeLock?.release(); } catch { } wakeLock = null; }
const today = (offset = 0) => { const d = new Date(); d.setDate(d.getDate() + offset); return d.toLocaleDateString('sv-SE'); };

/* Seedet tilfældighed, så alle får de samme spørgsmål (dagens quiz) */
function seedFrom(str) { let h = 1779033703 ^ str.length; for (let i = 0; i < str.length; i++) { h = Math.imul(h ^ str.charCodeAt(i), 3432918353); h = h << 13 | h >>> 19; } return h >>> 0; }
function rngFrom(seed) {
  let a = seedFrom(String(seed));
  return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
}
function shuffle(arr, rnd = Math.random) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

/* ---------- Udvælgelse af spørgsmål ---------- */
function pick({ kat = null, niv = null, n = 10, rnd = Math.random, exclude = new Set(), alle = false } = {}) {
  const pool = (alle ? BANK : BANK_MC).filter(q => !exclude.has(q.id) && (!kat || kat.includes(q.kategori)) && (!niv || q.niveau === niv));
  return shuffle(pool, rnd).slice(0, n);
}
function levelsFor(n) {
  const pattern = [1, 2, 1, 2, 3, 2, 3, 1, 4, 3];
  return Array.from({ length: n }, (_, i) => pattern[i % pattern.length]).sort((a, b) => a - b);
}
function pickMixed({ kat = null, levels = levelsFor(10), rnd = Math.random, exclude = new Set(), alle = false } = {}) {
  const used = new Set(exclude), out = [];
  for (const lv of levels) {
    const q = pick({ kat, niv: lv, n: 1, rnd, exclude: used, alle })[0] || pick({ kat, n: 1, rnd, exclude: used, alle })[0];
    if (q) { used.add(q.id); out.push(q); }
  }
  return out;
}
function pickSet({ kat, niv, n, rnd, alle = false }) { return niv ? pick({ kat, niv, n, rnd, alle }) : pickMixed({ kat, levels: levelsFor(n), rnd, alle }); }
function optionsFor(q, rnd = Math.random) {
  if (q.type === 'fri') return { opts: [], correct: -1 };
  if (q.type === 'sandt_falsk') return { opts: ['Sandt', 'Falsk'], correct: q.korrekt === 'Sandt' ? 0 : 1 };
  const opts = shuffle([q.korrekt, ...q.forkerte], rnd);
  return { opts, correct: opts.indexOf(q.korrekt) };
}

/* ---------- Statistik og fejlmeldinger (Supabase, valgfrit) ---------- */
const SB_OK = !!(CFG.SUPABASE_URL && CFG.SUPABASE_ANON_KEY);
function rpc(fn, body) {
  const key = CFG.SUPABASE_ANON_KEY;
  const headers = { 'Content-Type': 'application/json', apikey: key };
  if (key.startsWith('eyJ')) headers.Authorization = 'Bearer ' + key; // gammel anon-nøgle (JWT)
  return fetch(`${CFG.SUPABASE_URL.replace(/\/$/, '')}/rest/v1/rpc/${fn}`, {
    method: 'POST', keepalive: true, headers, body: JSON.stringify(body)
  }).then(r => { if (!r.ok) throw new Error('Supabase svarede ' + r.status); });
}

/* Svar lægges i kø (localStorage) og sendes samlet – virker også efter offline-spil */
function logAnswer(qid, ok) {
  if (!SB_OK || CFG.LOG_SVAR === false || !qid) return;
  const queue = store.get('svar-ko', []);
  queue.push({ q: qid, ok: !!ok });
  store.set('svar-ko', queue.slice(-500));
  clearTimeout(logAnswer._t);
  logAnswer._t = setTimeout(flushAnswers, queue.length >= 10 ? 0 : 4000);
}
let flushing = false;
async function flushAnswers() {
  if (!SB_OK || flushing || !navigator.onLine) return;
  const batch = store.get('svar-ko', []).slice(0, 50);
  if (!batch.length) return;
  flushing = true;
  try {
    await rpc('log_answers', { answers: batch });
    store.set('svar-ko', store.get('svar-ko', []).slice(batch.length));
    flushing = false;
    if (store.get('svar-ko', []).length) flushAnswers();
  } catch { flushing = false; } // prøves igen næste gang
}
window.addEventListener('online', flushAnswers);
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') flushAnswers(); });

const reportHtml = () => SB_OK ? '<div class="report" id="rep"><button class="linkbtn" id="repbtn">Meld fejl i spørgsmålet</button></div>' : '';
function bindReport(q) {
  const btn = $('#repbtn');
  if (!btn) return;
  btn.onclick = () => {
    $('#rep').innerHTML = `<div class="chips" id="reasons">${[['forkert_svar', 'Forkert svar'], ['uklart', 'Uklart spørgsmål'], ['foraeldet', 'Forældet'], ['andet', 'Andet']]
      .map(([v, l]) => `<button class="chip" data-v="${v}" aria-pressed="false">${l}</button>`).join('')}</div>
      <input type="text" id="repc" maxlength="500" placeholder="Kommentar (valgfri)" style="margin-top:10px">
      <button class="btn" id="repsend" disabled>Send fejlmelding</button>`;
    let reason = null;
    $$('#reasons .chip').forEach(c => c.onclick = () => {
      $$('#reasons .chip').forEach(x => x.setAttribute('aria-pressed', 'false'));
      c.setAttribute('aria-pressed', 'true'); reason = c.dataset.v; $('#repsend').disabled = false;
    });
    $('#repsend').onclick = async () => {
      $('#repsend').disabled = true;
      try {
        await rpc('report_question', { p_qid: q.id, p_reason: reason, p_comment: $('#repc').value });
        $('#rep').innerHTML = '<p class="hint">Tak – fejlmeldingen er sendt.</p>';
      } catch {
        toast('Fejlmeldingen blev ikke sendt – tjek forbindelsen og prøv igen');
        $('#repsend').disabled = false;
      }
    };
  };
}

/* ---------- UI-byggeklodser ---------- */
const dots = n => `<span class="niv" aria-label="Sværhedsgrad: ${NIV[n]}">${[1, 2, 3, 4].map(i => `<b class="${i <= n ? 'on' : ''}"></b>`).join('')}<em>${NIV[n]}</em></span>`;
const topbar = (info = '', score = '', progress = null) => `
  <div class="top"><button class="x" data-home aria-label="Til forsiden">✕</button>
    <div class="info">${info}${progress !== null ? `<div class="progress"><i style="width:${progress}%"></i></div>` : ''}</div>
    <div class="score">${score}</div></div>`;
const tilesHtml = (opts, cls = '') => `<div class="tiles ${cls}">${opts.map((o, i) =>
  `<button class="tile a${i}" data-i="${i}"><span class="shape" aria-hidden="true">${SHAPES[i]}</span><span>${esc(o)}</span></button>`).join('')}</div>`;

function markTiles(chosen, correct) {
  $$('.tile').forEach((b, j) => {
    b.disabled = true;
    if (j === correct) b.classList.add('right');
    else if (j === chosen) b.classList.add('wrong');
    else b.classList.add('dim');
  });
}

/* Stiller ét spørgsmål og venter på svar + "Næste" */
function ask(q, { head = '', rnd = Math.random, next = 'Næste' } = {}) {
  return new Promise(resolve => {
    const { opts, correct } = optionsFor(q, rnd);
    const t0 = performance.now();
    render(`<div class="screen">${head}
      <div class="qmeta"><span>${esc(KAT[q.kategori] || q.kategori)}</span>${dots(q.niveau)}</div>
      <h2 class="question">${esc(q.spoergsmaal)}</h2>
      ${tilesHtml(opts)}
      <div id="after" aria-live="polite"></div></div>`);
    $$('.tile').forEach(b => b.addEventListener('click', () => {
      const i = +b.dataset.i, ok = i === correct, ms = performance.now() - t0;
      markTiles(i, correct);
      logAnswer(q.id, ok);
      navigator.vibrate?.(ok ? 40 : [60, 40, 60]);
      const label = typeof next === 'function' ? next(ok) : next;
      $('#after').innerHTML = `<div class="verdict ${ok ? 'ok' : 'no'}">${ok ? 'Rigtigt' : 'Forkert'}</div>
        <p class="explain">${esc(q.forklaring)}</p><button class="btn primary" id="next">${label}</button>${reportHtml()}`;
      bindReport(q);
      $('#next').focus();
      $('#next').onclick = () => resolve({ q, ok, ms });
    }, { once: true }));
  });
}

/* Opsætning: kategorier, niveau, antal */
function setupFields({ count = true, defaultN = 10, mixedLabel = 'Blandet' } = {}) {
  return `
  <div class="field"><span class="lbl">Emner</span><small class="hint">Vælg de emner, du vil have spørgsmål fra. Vælg alle for en blandet quiz.</small><div class="chips" id="kats">
    ${Object.entries(KAT).map(([k, v]) => `<button class="chip" data-k="${k}" aria-pressed="true">${v}</button>`).join('')}
  </div></div>
  <div class="field"><span class="lbl">Sværhedsgrad</span><small class="hint">Vælg niveau, eller bland alle niveauer.</small>${seg('niv', [['mix', mixedLabel], ['1', 'Let'], ['2', 'Middel'], ['3', 'Svær'], ['4', 'Ekspert']], 'mix')}</div>
  ${count ? `<div class="field"><span class="lbl">Antal spørgsmål</span><small class="hint">Hvor mange spørgsmål quizzen skal indeholde.</small>${seg('n', [['5', '5'], ['10', '10'], ['15', '15'], ['20', '20']], String(defaultN))}</div>` : ''}`;
}
function seg(id, items, val) {
  return `<div class="seg" id="${id}" role="group">${items.map(([v, l]) => `<button data-v="${v}" aria-pressed="${v === val}">${l}</button>`).join('')}</div>`;
}
function bindSetup() {
  $$('#kats .chip').forEach(c => c.onclick = () => c.setAttribute('aria-pressed', c.getAttribute('aria-pressed') !== 'true'));
  $$('.seg').forEach(s => s.querySelectorAll('button').forEach(b => b.onclick = () => {
    s.querySelectorAll('button').forEach(x => x.setAttribute('aria-pressed', 'false')); b.setAttribute('aria-pressed', 'true');
  }));
}
const segVal = id => $(`#${id} [aria-pressed=true]`)?.dataset.v;
function readSetup() {
  const kats = $$('#kats .chip[aria-pressed=true]').map(c => c.dataset.k);
  const niv = segVal('niv');
  return {
    kat: kats.length && kats.length < Object.keys(KAT).length ? kats : null,
    niv: niv && niv !== 'mix' ? +niv : null,
    n: +(segVal('n') || 10)
  };
}

function recap(results) {
  return `<ul class="recap">${results.map(r => `<li><span class="mk ${r.ok ? 'ok' : 'no'}">${r.ok ? '✓' : '✗'}</span>
    <div>${esc(r.q.spoergsmaal)}<small>${esc(r.q.korrekt)}</small></div></li>`).join('')}</ul>`;
}

const INSTALL_SNOOZE_KEY = 'quizjagten-install-dismissed-until';
function isStandalone() {
  return Boolean(window.matchMedia?.('(display-mode: standalone)').matches || navigator.standalone === true || store.get('quizjagten-installed', false));
}
function installHelpText() {
  const ua = navigator.userAgent || '';
  const ios = /iPhone|iPad|iPod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (ios) return 'På iPhone eller iPad: Åbn siden i Safari, tryk på Del, vælg “Føj til hjemmeskærm”, og tryk derefter på “Tilføj”.';
  if (/Android/i.test(ua)) return 'På Android: Åbn browserens menu (⋮), og vælg “Installer app” eller “Føj til startskærm”.';
  return 'Åbn browserens menu eller installationsikonet ved adresselinjen, og vælg “Installer Quizjagten”.';
}
function installPopupStyles() {
  if ($('#quiz-install-styles')) return;
  const style = document.createElement('style');
  style.id = 'quiz-install-styles';
  style.textContent = `
    .quiz-install-backdrop{position:fixed;inset:0;z-index:100;display:grid;place-items:center;padding:18px;background:rgba(5,7,20,.78);backdrop-filter:blur(8px);animation:quiz-install-in .18s ease-out}
    .quiz-install-card{position:relative;width:min(100%,460px);padding:26px;border:1px solid rgba(255,255,255,.14);border-radius:24px;background:#222c73;color:#f5f3ff;box-shadow:0 24px 80px rgba(0,0,0,.5)}
    .quiz-install-close{position:absolute;top:12px;right:12px;width:38px;height:38px;border:0;border-radius:50%;background:rgba(255,255,255,.1);color:#fff;font-size:1.4rem;cursor:pointer}
    .quiz-install-mark{display:grid;place-items:center;width:56px;height:56px;margin:0 0 14px;border-radius:17px;background:#ffc933;color:#17205a;font-size:1.8rem}
    .quiz-install-card h2{margin:0 38px 8px 0;font-size:1.55rem;line-height:1.15}
    .quiz-install-card p{margin:0 0 18px;color:#d5d8f2;line-height:1.5}
    .quiz-install-actions{display:grid;gap:9px}
    .quiz-install-actions .btn{margin:0}
    .quiz-install-later{border:0;background:transparent;color:#d5d8f2;padding:9px;cursor:pointer;font:inherit}
    @keyframes quiz-install-in{from{opacity:0}to{opacity:1}}
    @media(prefers-reduced-motion:reduce){.quiz-install-backdrop{animation:none}}
  `;
  document.head.appendChild(style);
}
function closeInstallPopup(snooze = true) {
  $('#quiz-install-backdrop')?.remove();
  if (snooze) store.set(INSTALL_SNOOZE_KEY, Date.now() + 7 * 864e5);
}
function showInstallPopup() {
  if (isStandalone() || $('#quiz-install-backdrop')) return;
  installPopupStyles();
  const backdrop = document.createElement('div');
  backdrop.id = 'quiz-install-backdrop';
  backdrop.className = 'quiz-install-backdrop';
  const dialog = document.createElement('section');
  dialog.className = 'quiz-install-card';
  dialog.setAttribute('role', 'dialog');
  dialog.setAttribute('aria-modal', 'true');
  dialog.setAttribute('aria-labelledby', 'quiz-install-title');
  const close = document.createElement('button');
  close.className = 'quiz-install-close';
  close.type = 'button';
  close.setAttribute('aria-label', 'Luk installationsvejledningen');
  close.textContent = '×';
  close.onclick = () => closeInstallPopup();
  const mark = document.createElement('div');
  mark.className = 'quiz-install-mark';
  mark.setAttribute('aria-hidden', 'true');
  mark.textContent = '↓';
  const title = document.createElement('h2');
  title.id = 'quiz-install-title';
  title.textContent = 'Hent Quizjagten';
  const description = document.createElement('p');
  description.textContent = installPrompt
    ? 'Installér quizzen på din enhed, så den ligger klar på hjemmeskærmen og kan åbnes som en app.'
    : installHelpText();
  const actions = document.createElement('div');
  actions.className = 'quiz-install-actions';
  if (installPrompt) {
    const installButton = document.createElement('button');
    installButton.className = 'btn primary';
    installButton.type = 'button';
    installButton.textContent = 'Installér Quizjagten';
    installButton.onclick = async () => {
      const promptEvent = installPrompt;
      if (!promptEvent) return closeInstallPopup();
      installButton.disabled = true;
      try {
        await promptEvent.prompt();
        const choice = await promptEvent.userChoice;
        if (choice?.outcome === 'accepted') store.set('quizjagten-installed', true);
      } catch { /* browseren kan afvise prompten */ }
      installPrompt = null;
      closeInstallPopup();
    };
    actions.append(installButton);
  } else {
    const doneButton = document.createElement('button');
    doneButton.className = 'btn primary';
    doneButton.type = 'button';
    doneButton.textContent = 'Forstået';
    doneButton.onclick = () => closeInstallPopup();
    actions.append(doneButton);
  }
  const later = document.createElement('button');
  later.className = 'quiz-install-later';
  later.type = 'button';
  later.textContent = 'Ikke nu';
  later.onclick = () => closeInstallPopup();
  actions.append(later);
  dialog.append(close, mark, title, description, actions);
  backdrop.append(dialog);
  backdrop.addEventListener('click', event => { if (event.target === backdrop) closeInstallPopup(); });
  backdrop.addEventListener('keydown', event => { if (event.key === 'Escape') closeInstallPopup(); });
  document.body.append(backdrop);
  (installPrompt ? actions.querySelector('.btn') : close).focus();
}
function scheduleInstallPopup() {
  if (isStandalone() || Date.now() < Number(store.get(INSTALL_SNOOZE_KEY, 0))) return;
  clearTimeout(scheduleInstallPopup.timer);
  scheduleInstallPopup.timer = setTimeout(showInstallPopup, 1800);
}

/* ---------- Forside ---------- */
function home() {
  history.replaceState(null, '', location.pathname);
  const live = !!(CFG.SUPABASE_URL && CFG.SUPABASE_ANON_KEY);
  const mode = (m, ic, cls, title, desc, disabled = false) =>
    `<button class="mode" data-m="${m}" ${disabled ? 'disabled' : ''}><span class="ic ${cls}" aria-hidden="true">${ic}</span><strong>${title}</strong><span class="d">${desc}</span></button>`;
  const dag = store.get('dag-' + today());
  render(`<div class="home-shell">
    <nav class="home-nav" aria-label="Hovedmenu">
      <a class="home-logo" href="#" aria-label="Quizjagten forsiden">Quizjagten</a>
      <div class="home-nav-links">
        <a href="#spiltyper">Spiltyper</a>
        <a href="#saadan">S&aring;dan spiller du</a>
        <a href="#kilder">Kilder</a>
        <button class="home-install" id="install" hidden>Hent app</button>
      </div>
    </nav>
    <section class="home-hero">
      <div class="hero-eyebrow"><span></span> Almen viden &middot; 9 emner &middot; solo og selskab</div>
      <h1 class="home-title"><span class="line-dim">Velkommen til</span><span class="line-gold">Quizjagten</span></h1>
      <p class="home-sub">Spil alene eller sammen med vennerne. V&aelig;lg blandt ${BANK.length.toLocaleString('da-DK')} sp&oslash;rgsm&aring;l i 9 emner.</p>
      <div class="home-actions">
        <button class="home-primary hero-cta">Spil dagens quiz <span aria-hidden="true">&rarr;</span></button>
        <a class="home-ghost" href="#spiltyper">V&aelig;lg spiltyper</a>
      </div>
      <div class="home-proof"><span>${BANK.length.toLocaleString('da-DK')} sp&oslash;rgsm&aring;l</span><i></i><span>9 emner</span><i></i><span>Alene eller sammen</span></div>
    </section>
    <section class="home-content" id="spiltyper">
      <div class="home-section-heading">
        <p class="home-kicker">Hvad vil du spille?</p><h2>En quiz til enhver anledning</h2>
        <p>V&aelig;lg en spiltype, og kom i gang med det samme.</p>
      </div>
      ${BANK.length ? '' : '<p class="explain">Der er ingen godkendte sp&oslash;rgsm&aring;l endnu. S&aelig;t status til "godkendt" i questions.json, eller sl&aring; VIS_KLADDER til i config.js.</p>'}
      <div class="home-groups">
        <section class="group"><h2>Alene</h2><div class="modes">
          ${mode('dag', '&#9728;', 'a3', 'Dagens quiz', dag ? 'Klaret i dag: ' + dag.ok + ' af ' + dag.n + ' rigtige' : 'Samme 10 sp&oslash;rgsm&aring;l for alle i dag')}
          ${mode('traen', '&#9673;', 'a1', 'Tr&aelig;ning', 'V&aelig;lg selv emner og sv&aelig;rhedsgrad')}
          ${mode('surv', '&#9829;', 'a0', 'Survival', '&Eacute;t forkert svar, og det er slut. Rekord: ' + store.get('surv-best', 0))}
        </div></section>
        <section class="group"><h2>To spillere</h2><div class="modes">
          ${mode('spoerg', '?', 'a3', 'Sp&oslash;rg l&oslash;s', 'L&aelig;s op og svar frit &ndash; med eller uden point og tur')}
          ${mode('duel', '&#8644;', 'a2', 'Duel p&aring; &eacute;n telefon', 'Send telefonen frem og tilbage')}
          ${mode('udfordr', '&#9993;', 'a1', 'Udfordr en ven', 'Send et link &ndash; I f&aring;r de samme sp&oslash;rgsm&aring;l')}
        </div></section>
        <section class="group"><h2>Selskab</h2><div class="modes">
          ${mode('host', '&#9635;', 'a3', 'Live p&aring; storsk&aelig;rm', live ? 'Alle svarer p&aring; deres egen telefon' : 'Kr&aelig;ver Supabase-n&oslash;gler i config.js', !live)}
          ${mode('join', '#', 'a2', 'Deltag i live-spil', 'Har du f&aring;et en kode?', !live)}
          ${mode('qm', '&#9835;', 'a0', 'Quizmaster', '&Eacute;n l&aelig;ser op &ndash; ingen andre sk&aelig;rme')}
        </div></section>
      </div>
    </section>
    <section class="home-how" id="saadan">
      <div class="home-how-copy">
        <p class="home-kicker">Let at komme i gang</p><h2>V&aelig;lg et spil.<br>Find jeres svar.</h2>
        <p>Spil en hurtig quiz alene, send en udfordring til en ven, eller lav en quiz for hele selskabet. I kan v&aelig;lge emner og sv&aelig;rhedsgrad, n&aring;r spiltypen giver mulighed for det.</p>
      </div>
      <div class="home-steps">
        <div><span>01</span><p><strong>V&aelig;lg spiltype</strong><small>Dagens quiz, duel, survival og meget mere.</small></p></div>
        <div><span>02</span><p><strong>Svar p&aring; sp&oslash;rgsm&aring;l</strong><small>F&aring; point for hvert rigtigt svar.</small></p></div>
        <div><span>03</span><p><strong>Spil igen eller del</strong><small>Udfordr vennerne, eller forts&aelig;t sammen.</small></p></div>
      </div>
    </section>
    <footer class="home-footer" id="kilder">
      <a class="home-logo" href="#">Quizjagten</a><div>
        <p>Nogle sp&oslash;rgsm&aring;l er oversat og bearbejdet fra <a href="https://the-trivia-api.com/" target="_blank" rel="noopener noreferrer">The Trivia API</a> under <a href="https://creativecommons.org/licenses/by-nc/4.0/" target="_blank" rel="noopener noreferrer">CC BY-NC 4.0</a>. Overs&aelig;ttelserne er redigeret.</p>
        <p><a href="https://psch.dk/?v=quiz" target="_blank" rel="noopener noreferrer">Sp&oslash;rgsm&aring;l er hentet fra psch.dk - Trivia Quizdatabase</a>.</p>
      </div>
    </footer>
  </div>`);
  const routes = { dag: dagens, traen: traening, surv: survival, spoerg: spoergSetup, duel: duelSetup, udfordr: udfordrSetup, host: liveHostSetup, join: () => liveJoin(), qm: quizmasterSetup };
  $$('.mode').forEach(b => b.onclick = () => BANK.length || ['join'].includes(b.dataset.m) ? routes[b.dataset.m]() : toast('Der er ingen sp\u00f8rgsm\u00e5l endnu'));
  $('.hero-cta').onclick = () => routes.dag();
  const installBtn = $('#install');
  if (!isStandalone()) {
    installBtn.hidden = false;
    installBtn.onclick = showInstallPopup;
    scheduleInstallPopup();
  }
}

/* ---------- Træning ---------- */
function traening() {
  render(`<div class="screen">${topbar()}<h1 class="title">Træning</h1>
    <p class="lead">Point efter sværhedsgrad: Let 1, Middel 2, Svær 3, Ekspert 5.</p>
    ${setupFields()}<button class="btn primary" id="go">Start</button></div>`);
  bindSetup();
  $('#go').onclick = async () => {
    const s = readSetup();
    const qs = pickSet(s);
    if (!qs.length) return toast('Ingen spørgsmål passer – vælg flere emner');
    let score = 0; const res = [];
    for (let i = 0; i < qs.length; i++) {
      const r = await ask(qs[i], { head: topbar(`${i + 1} af ${qs.length}`, `${score} p`, i / qs.length * 100), next: i === qs.length - 1 ? 'Se resultat' : 'Næste' });
      if (r.ok) score += POINT[qs[i].niveau];
      res.push(r);
    }
    const max = qs.reduce((a, q) => a + POINT[q.niveau], 0);
    render(`<div class="screen">${topbar()}<h1 class="title">Færdig</h1>
      <div class="big-score">${score}</div><p class="lead">af ${max} mulige point · ${res.filter(r => r.ok).length} af ${qs.length} rigtige</p>
      ${recap(res)}<button class="btn primary" id="again">Spil igen</button><button class="btn" data-home>Til forsiden</button></div>`);
    $('#again').onclick = traening;
  };
}

/* ---------- Dagens quiz ---------- */
async function dagens() {
  const key = 'dag-' + today();
  const done = store.get(key);
  if (done) return dagResultat(done);
  const qs = pickMixed({ rnd: rngFrom('dag-' + today()) });
  const optRnd = rngFrom('svar-' + today());
  const res = [];
  for (let i = 0; i < qs.length; i++) {
    const ok = res.filter(r => r.ok).length;
    res.push(await ask(qs[i], { rnd: optRnd, head: topbar(`Dagens quiz · ${i + 1} af ${qs.length}`, `${ok} ✓`, i / qs.length * 100), next: i === qs.length - 1 ? 'Se resultat' : 'Næste' }));
  }
  const r = { n: res.length, ok: res.filter(x => x.ok).length, bits: res.map(x => x.ok ? 1 : 0).join(''), ids: qs.map(q => q.id) };
  store.set(key, r);
  dagResultat(r);
}
function dagStreak() {
  let n = 0; while (store.get('dag-' + today(-n))) n++;
  return n;
}
function dagResultat(r) {
  const grid = [...r.bits].map(b => b === '1' ? '🟩' : '🟥').join('');
  const dato = new Date().toLocaleDateString('da-DK', { day: 'numeric', month: 'long' });
  const text = `${CFG.APP_NAVN} ${dato}\n${grid}\n${r.ok}/${r.n} rigtige\n${location.origin + location.pathname}`;
  const streak = dagStreak();
  const qs = (r.ids || []).map(id => ALL.find(q => q.id === id)).filter(Boolean);
  render(`<div class="screen">${topbar()}<h1 class="title">Dagens quiz</h1>
    <div class="big-score">${r.ok}/${r.n}</div>
    <p class="lead">${streak > 1 ? `${streak} dage i træk. ` : ''}Nye spørgsmål i morgen.</p>
    <div class="grid-share">${grid}</div>
    <button class="btn primary" id="share">Del resultat</button>
    ${qs.length ? recap(qs.map((q, i) => ({ q, ok: r.bits[i] === '1' }))) : ''}
    <button class="btn" data-home>Til forsiden</button></div>`);
  $('#share').onclick = () => shareText(text, 'Resultatet er kopieret');
}
async function shareText(text, copiedMsg = 'Kopieret') {
  if (navigator.share) { try { await navigator.share({ text }); return; } catch (e) { if (e.name === 'AbortError') return; } }
  try { await navigator.clipboard.writeText(text); toast(copiedMsg); } catch { prompt('Kopiér teksten:', text); }
}

/* ---------- Survival ---------- */
function survival() {
  const best = store.get('surv-best', 0);
  render(`<div class="screen">${topbar()}<h1 class="title">Survival</h1>
    <p class="lead">Svar rigtigt så længe du kan. For hver 3 rigtige bliver det sværere. Ét forkert svar, og spillet slutter.</p>
    <div class="big-score">${best}</div><p class="lead">din rekord</p>
    <button class="btn primary" id="go">Start</button></div>`);
  $('#go').onclick = async () => {
    let streak = 0; const used = new Set(); let last = null;
    while (true) {
      const lv = Math.min(4, 1 + Math.floor(streak / 3));
      const q = pick({ niv: lv, n: 1, exclude: used })[0] || pick({ n: 1, exclude: used })[0];
      if (!q) break;
      used.add(q.id);
      last = await ask(q, { head: topbar(`Survival · ${NIV[lv]}`, `${streak} i træk`), next: ok => ok ? 'Næste' : 'Se resultat' });
      if (!last.ok) break;
      streak++;
    }
    const nyRekord = streak > best;
    if (nyRekord) store.set('surv-best', streak);
    render(`<div class="screen">${topbar()}<h1 class="title">${nyRekord ? 'Ny rekord' : 'Slut'}</h1>
      <div class="big-score">${streak}</div><p class="lead">rigtige i træk${nyRekord ? '' : ` · rekord ${best}`}</p>
      ${last && !last.ok ? `<p class="explain">Svaret var: ${esc(last.q.korrekt)}</p>` : ''}
      ${!last || last.ok ? '<p class="explain">Du har besvaret alle spørgsmål i banken!</p>' : ''}
      <button class="btn primary" id="again">Prøv igen</button><button class="btn" data-home>Til forsiden</button></div>`);
    $('#again').onclick = survival;
  };
}

/* ---------- Spørg løs (oplæsning uden svarmuligheder) ---------- */
const playerRow = (p, i) => `<div class="row" style="margin-bottom:8px">
  <input type="text" maxlength="20" placeholder="Navn" value="${esc(p.name)}" aria-label="Spiller ${i + 1}">
  <select aria-label="Sværhedsgrad for spiller ${i + 1}">${[['std', 'Som valgt'], ['1', 'Let'], ['2', 'Middel'], ['3', 'Svær'], ['4', 'Ekspert']]
    .map(([v, l]) => `<option value="${v}" ${v === p.niv ? 'selected' : ''}>${l}</option>`).join('')}</select></div>`;

function spoergSetup() {
  const saved = store.get('spoerg-sidst', []);
  render(`<div class="screen">${topbar()}<h1 class="title">Spørg løs</h1>
    <p class="lead">Du læser spørgsmålet højt, og der svares frit uden svarmuligheder. Kun du ser svaret.</p>
    ${setupFields({ count: false })}
    <div class="field"><span class="lbl">Spillere eller hold (valgfrit)</span>
      <div id="pl">${saved.map(playerRow).join('')}</div>
      <div class="row"><button class="btn" id="add">Tilføj spiller</button><button class="btn" id="rem">Fjern</button></div>
      <p class="hint">Uden spillere er der hverken tur eller point – bare spørgsmål og svar. Med spillere holder appen styr på, hvis tur det er, og hver kan have sin egen sværhedsgrad.</p></div>
    <button class="btn primary" id="go">Start</button></div>`);
  bindSetup();
  const rows = () => $$('#pl .row');
  $('#add').onclick = () => { if (rows().length < 10) $('#pl').insertAdjacentHTML('beforeend', playerRow({ name: '', niv: 'std' }, rows().length)); };
  $('#rem').onclick = () => rows().at(-1)?.remove();
  $('#go').onclick = () => {
    const players = rows().map((r, i) => ({
      name: r.querySelector('input').value.trim() || `Spiller ${i + 1}`,
      niv: r.querySelector('select').value, score: 0, right: 0, asked: 0
    }));
    store.set('spoerg-sidst', players.map(p => ({ name: p.name, niv: p.niv })));
    spoergPlay(readSetup(), players);
  };
}

function spoergPlay(s, players) {
  const used = new Set(), scored = players.length > 0;
  let turn = 0, asked = 0;
  keepAwake();

  function show() {
    const p = scored ? players[turn] : null;
    const niv = p && p.niv !== 'std' ? +p.niv : s.niv;
    const q = pick({ kat: s.kat, niv, n: 1, exclude: used, alle: true })[0];
    if (!q) { toast('Der er ikke flere spørgsmål med de valg'); return finish(); }
    used.add(q.id);
    const board = scored ? `<div class="teams">${players.map((x, i) =>
      `<span class="team ${i === turn ? 'turn' : ''}">${esc(x.name)}<b>${x.score}</b></span>`).join('')}</div>` : '';
    render(`<div class="screen">${topbar(scored ? '' : `Spørgsmål ${asked + 1}`)}${board}
      ${p ? `<p class="turnlbl">Spørgsmål til</p><h2 class="turnname">${esc(p.name)}</h2>` : ''}
      <div class="qmeta"><span>${esc(KAT[q.kategori] || q.kategori)}${scored ? ` · ${POINT[q.niveau]} point` : ''}</span>${dots(q.niveau)}</div>
      <h2 class="question">${esc(q.spoergsmaal)}</h2>
      <div id="hintbox"></div>
      <div id="after"><button class="btn primary" id="show">Vis svar</button>
        <div class="row">${q.type === 'mc' ? '<button class="btn" id="hint">Hjælp: vis svarmuligheder</button>' : ''}<button class="btn" id="skip">Spring over</button></div></div>
      ${scored ? '<button class="btn ghost" id="end">Afslut og se stilling</button>' : ''}</div>`);

    let hint = false;
    if ($('#hint')) $('#hint').onclick = () => {
      hint = true;
      $('#hintbox').innerHTML = `<ul class="hintlist">${optionsFor(q).opts.map((o, i) =>
        `<li><span aria-hidden="true">${SHAPES[i]}</span> ${esc(o)}</li>`).join('')}</ul>`;
      $('#hint').remove();
    };
    $('#skip').onclick = show; // samme spiller får et nyt spørgsmål
    if ($('#end')) $('#end').onclick = finish;
    $('#show').onclick = () => {
      const pts = hint ? Math.ceil(POINT[q.niveau] / 2) : POINT[q.niveau];
      asked++;
      $('#after').innerHTML = `<div class="answer">${esc(q.korrekt)}</div><p class="explain">${esc(q.forklaring)}</p>
        ${scored ? `<div class="row"><button class="btn ok" id="right">Rigtigt +${pts}</button><button class="btn no" id="wrong">Forkert</button></div>`
          : '<button class="btn primary" id="next">Næste spørgsmål</button>'}${reportHtml()}`;
      bindReport(q);
      const advance = ok => {
        if (p) {
          p.asked++; if (ok) { p.score += pts; p.right++; }
          if (!hint) logAnswer(q.id, ok);
          turn = (turn + 1) % players.length;
        }
        show();
      };
      if (scored) { $('#right').onclick = () => advance(true); $('#wrong').onclick = () => advance(false); }
      else $('#next').onclick = () => advance(false);
    };
  }

  function finish() {
    releaseWake();
    if (!scored) return goHome();
    const order = [...players].sort((a, b) => b.score - a.score);
    const tie = order.length > 1 && order[0].score === order[1].score;
    render(`<div class="screen">${topbar()}<h1 class="title">${tie ? 'Uafgjort' : `${esc(order[0].name)} fører`}</h1>
      <ol class="board">${order.map(x => `<li>${esc(x.name)}<span class="g" style="color:var(--daemp)">${x.right} af ${x.asked} rigtige</span><span class="p">${x.score}</span></li>`).join('')}</ol>
      <button class="btn primary" id="cont">Fortsæt spillet</button><button class="btn" id="new">Nyt spil</button><button class="btn" data-home>Til forsiden</button></div>`);
    $('#cont').onclick = () => { keepAwake(); show(); };
    $('#new').onclick = spoergSetup;
  }
  show();
}

/* ---------- Duel på én telefon ---------- */
const nivOpts = sel => [['mix', 'Blandet'], ['1', 'Let'], ['2', 'Middel'], ['3', 'Svær'], ['4', 'Ekspert']]
  .map(([v, l]) => `<option value="${v}" ${v === sel ? 'selected' : ''}>${l}</option>`).join('');

function duelSetup(prev) {
  const p = prev || store.get('duel-sidst', { names: ['', ''], nivs: ['mix', 'mix'], rounds: '5' });
  render(`<div class="screen">${topbar()}<h1 class="title">Duel på én telefon</h1>
    <p class="lead">Hver spiller vælger sin egen sværhedsgrad. Alle rigtige svar giver 1 point – så kan børn og voksne dyste fair.</p>
    ${[0, 1].map(i => `<div class="field"><label for="n${i}">Spiller ${i + 1}</label>
      <div class="row"><input type="text" id="n${i}" maxlength="16" placeholder="Navn" value="${esc(p.names[i])}">
      <select id="l${i}" aria-label="Sværhedsgrad for spiller ${i + 1}">${nivOpts(p.nivs[i])}</select></div></div>`).join('')}
    <div class="field"><span class="lbl">Runder</span>${seg('n', [['3', '3'], ['5', '5'], ['10', '10']], p.rounds)}</div>
    <button class="btn primary" id="go">Start duel</button></div>`);
  bindSetup();
  $('#go').onclick = () => {
    const cfg = {
      names: [0, 1].map(i => $('#n' + i).value.trim() || `Spiller ${i + 1}`),
      nivs: [0, 1].map(i => $('#l' + i).value),
      rounds: segVal('n')
    };
    store.set('duel-sidst', cfg);
    duelPlay(cfg);
  };
}
function handoff(name, sub) {
  return new Promise(res => {
    render(`<div class="screen">${topbar()}<div class="handoff"><p>Giv telefonen til</p><h1>${esc(name)}</h1>
      <button class="btn primary" id="ready">Jeg er klar</button><p style="margin-top:16px">${esc(sub)}</p></div></div>`);
    $('#ready').onclick = res;
  });
}
async function duelPlay(cfg) {
  const R = +cfg.rounds, score = [0, 0], used = new Set();
  for (let r = 0; r < R; r++) {
    for (let p = 0; p < 2; p++) {
      await handoff(cfg.names[p], `Runde ${r + 1} af ${R} · ${score[0]}–${score[1]}`);
      const niv = cfg.nivs[p] === 'mix' ? levelsFor(R)[r] : +cfg.nivs[p];
      const q = pick({ niv, n: 1, exclude: used })[0] || pick({ n: 1, exclude: used })[0];
      if (!q) { toast('Ikke flere spørgsmål'); break; }
      used.add(q.id);
      const res = await ask(q, { head: topbar(`${esc(cfg.names[p])} · runde ${r + 1}`, `${score[0]}–${score[1]}`) });
      if (res.ok) score[p]++;
    }
  }
  const winner = score[0] === score[1] ? null : score[0] > score[1] ? 0 : 1;
  render(`<div class="screen">${topbar()}<h1 class="title">${winner === null ? 'Uafgjort' : `${esc(cfg.names[winner])} vinder`}</h1>
    <div class="versus"><div><div class="s">${score[0]}</div><div class="n">${esc(cfg.names[0])}</div></div><div class="vs">mod</div>
    <div><div class="s">${score[1]}</div><div class="n">${esc(cfg.names[1])}</div></div></div>
    <button class="btn primary" id="again">Omkamp</button><button class="btn" id="setup">Ret indstillinger</button><button class="btn" data-home>Til forsiden</button></div>`);
  $('#again').onclick = () => duelPlay(cfg);
  $('#setup').onclick = () => duelSetup(cfg);
}

/* ---------- Udfordr en ven (via link, ingen server) ---------- */
function udfordrSetup() {
  render(`<div class="screen">${topbar()}<h1 class="title">Udfordr en ven</h1>
    <p class="lead">Du spiller 10 spørgsmål og får et link. Din ven får præcis de samme spørgsmål – og så sammenligner I.</p>
    <div class="field"><label for="nm">Dit navn</label><input type="text" id="nm" maxlength="16" value="${esc(store.get('navn', ''))}"></div>
    <div class="field"><span class="lbl">Sværhedsgrad</span>${seg('niv', [['mix', 'Blandet'], ['1', 'Let'], ['2', 'Middel'], ['3', 'Svær'], ['4', 'Ekspert']], 'mix')}</div>
    <button class="btn primary" id="go">Start</button></div>`);
  bindSetup();
  $('#go').onclick = async () => {
    const name = $('#nm').value.trim() || 'En ven'; store.set('navn', name);
    const niv = segVal('niv');
    const qs = pickSet({ kat: null, niv: niv === 'mix' ? null : +niv, n: 10 });
    const ids = qs.map(q => q.id);
    const bits = await playChallenge(qs, ids, `${esc(name)} udfordrer`);
    const link = challengeLink({ duel: ids.join(','), fra: name, r: bits });
    render(`<div class="screen">${topbar()}<h1 class="title">Send udfordringen</h1>
      <div class="big-score">${count(bits)}/${ids.length}</div><p class="lead">Kan din ven slå det?</p>
      <button class="btn primary" id="share">Send link</button><button class="btn" data-home>Til forsiden</button></div>`);
    $('#share').onclick = () => shareText(`${name} har fået ${count(bits)}/${ids.length} i ${CFG.APP_NAVN}. Kan du slå det?\n${link}`, 'Linket er kopieret');
  };
}
const count = bits => [...bits].filter(b => b === '1').length;
function challengeLink(params) { return location.origin + location.pathname + '?' + new URLSearchParams(params).toString(); }
async function playChallenge(qs, ids, label) {
  const rnd = rngFrom(ids.join(','));
  const map = Object.fromEntries(qs.map(q => [q.id, q]));
  let bits = '', played = 0;
  for (const id of ids) {
    const q = map[id];
    if (!q) { bits += '-'; continue; }
    const r = await ask(q, { rnd, head: topbar(`${label} · ${played + 1} af ${qs.length}`, `${count(bits)} ✓`, played / qs.length * 100), next: played === qs.length - 1 ? 'Se resultat' : 'Næste' });
    bits += r.ok ? '1' : '0'; played++;
  }
  return bits;
}
function compareView(ids, a, aBits, b, bBits, replyLink) {
  const qs = ids.map(id => ALL.find(q => q.id === id));
  const sa = count(aBits), sb = count(bBits);
  const title = sa === sb ? 'Uafgjort' : `${esc(sa > sb ? a : b)} vinder`;
  const mk = c => c === '1' ? '<span class="ok">✓</span>' : c === '0' ? '<span class="no">✗</span>' : '–';
  render(`<div class="screen">${topbar()}<h1 class="title">${title}</h1>
    <div class="versus"><div><div class="s">${sa}</div><div class="n">${esc(a)}</div></div><div class="vs">mod</div>
    <div><div class="s">${sb}</div><div class="n">${esc(b)}</div></div></div>
    ${replyLink ? '<button class="btn primary" id="reply">Send resultatet tilbage</button>' : ''}
    <table class="cmp"><tr><th>Spørgsmål</th><th>${esc(a)}</th><th>${esc(b)}</th></tr>
    ${qs.map((q, i) => `<tr><td>${q ? esc(q.spoergsmaal) : '(findes ikke længere)'}</td><td>${mk(aBits[i])}</td><td>${mk(bBits[i])}</td></tr>`).join('')}</table>
    <button class="btn" id="new">Lav din egen udfordring</button><button class="btn" data-home>Til forsiden</button></div>`);
  if (replyLink) $('#reply').onclick = () => shareText(`Jeg fik ${sb}/${ids.length} mod dine ${sa} i ${CFG.APP_NAVN}:\n${replyLink}`, 'Linket er kopieret');
  $('#new').onclick = udfordrSetup;
}
function receiveChallenge(p) {
  const ids = (p.get('duel') || '').split(',').filter(Boolean).slice(0, 30);
  const fra = (p.get('fra') || 'En ven').slice(0, 16), r = (p.get('r') || '').replace(/[^01-]/g, '');
  if (p.has('mr')) return compareView(ids, fra, r, (p.get('mod') || 'Modstander').slice(0, 16), p.get('mr').replace(/[^01-]/g, ''), null);
  const qs = ids.map(id => ALL.find(q => q.id === id)).filter(Boolean);
  if (!qs.length) { toast('Spørgsmålene i linket findes ikke'); return home(); }
  render(`<div class="screen">${topbar()}<div class="handoff"><p>Du er blevet udfordret af</p><h1>${esc(fra)}</h1>
    <p>${qs.length} spørgsmål – de samme som ${esc(fra)} fik.</p>
    <div class="field" style="text-align:left"><label for="nm">Dit navn</label><input type="text" id="nm" maxlength="16" value="${esc(store.get('navn', ''))}"></div>
    <button class="btn primary" id="go">Tag udfordringen</button></div></div>`);
  $('#go').onclick = async () => {
    const me = $('#nm').value.trim() || 'Modstander'; store.set('navn', me);
    const mine = await playChallenge(qs, ids, `Mod ${esc(fra)}`);
    compareView(ids, fra, r, me, mine, challengeLink({ duel: ids.join(','), fra, r, mod: me, mr: mine }));
  };
}

/* ---------- Quizmaster (én skærm, læses op) ---------- */
function quizmasterSetup() {
  const saved = store.get('qm-hold', ['Hold 1', 'Hold 2']);
  render(`<div class="screen">${topbar()}<h1 class="title">Quizmaster</h1>
    <p class="lead">Du læser spørgsmålene op og giver point. Holdene skal ikke bruge telefon.</p>
    <div class="field"><span class="lbl">Hold</span><div id="teams">${saved.map((t, i) => teamInput(t, i)).join('')}</div>
    <div class="row"><button class="btn" id="add">Tilføj hold</button><button class="btn" id="rem">Fjern hold</button></div></div>
    ${setupFields({ defaultN: 15 })}<button class="btn primary" id="go">Start</button></div>`);
  bindSetup();
  const teams = () => $$('#teams input');
  $('#add').onclick = () => { if (teams().length < 8) $('#teams').insertAdjacentHTML('beforeend', teamInput(`Hold ${teams().length + 1}`, teams().length)); };
  $('#rem').onclick = () => { if (teams().length > 1) teams().at(-1).remove(); };
  $('#go').onclick = () => {
    const names = teams().map((t, i) => t.value.trim() || `Hold ${i + 1}`);
    store.set('qm-hold', names);
    const qs = pickSet({ ...readSetup(), alle: true });
    if (!qs.length) return toast('Ingen spørgsmål passer – vælg flere emner');
    quizmasterPlay(names, qs);
  };
}
const teamInput = (v, i) => `<input type="text" maxlength="20" value="${esc(v)}" aria-label="Hold ${i + 1}" style="margin-bottom:8px">`;
async function quizmasterPlay(names, qs) {
  const score = names.map(() => 0);
  keepAwake();
  const board = () => `<div class="teams">${names.map((n, i) => `<span class="team">${esc(n)}<b>${score[i]}</b></span>`).join('')}</div>`;
  for (let i = 0; i < qs.length; i++) {
    const q = qs[i], { opts, correct } = optionsFor(q);
    await new Promise(res => {
      render(`<div class="screen wide">${topbar(`Spørgsmål ${i + 1} af ${qs.length}`, '', i / qs.length * 100)}${board()}
        <div class="qmeta"><span>${esc(KAT[q.kategori])} · ${POINT[q.niveau]} point</span>${dots(q.niveau)}</div>
        <h2 class="question">${esc(q.spoergsmaal)}</h2>${opts.length ? tilesHtml(opts) : ''}
        <div id="after"><button class="btn primary" id="show">Vis svar</button></div></div>`);
      $$('.tile').forEach(t => t.disabled = true);
      $('#show').onclick = () => {
        markTiles(-1, correct);
        $('#after').innerHTML = `${opts.length ? '' : `<div class="answer">${esc(q.korrekt)}</div>`}<p class="explain" style="margin-top:18px">${esc(q.forklaring)}</p>
          <div class="field"><span class="lbl">Hvem svarede rigtigt?</span><div class="row" style="flex-wrap:wrap">
          ${names.map((n, j) => `<button class="toggle-team" data-j="${j}" aria-pressed="false">${esc(n)}</button>`).join('')}</div></div>
          <button class="btn primary" id="next">${i === qs.length - 1 ? 'Se vinderen' : 'Næste spørgsmål'}</button>${reportHtml()}`;
        bindReport(q);
        $$('.toggle-team').forEach(b => b.onclick = () => b.setAttribute('aria-pressed', b.getAttribute('aria-pressed') !== 'true'));
        $('#next').onclick = () => {
          $$('.toggle-team').forEach(b => {
            const ok = b.getAttribute('aria-pressed') === 'true';
            if (ok) score[+b.dataset.j] += POINT[q.niveau];
            logAnswer(q.id, ok);
          });
          res();
        };
      };
    });
  }
  releaseWake();
  const order = names.map((n, i) => ({ n, s: score[i] })).sort((a, b) => b.s - a.s);
  render(`<div class="screen wide">${topbar()}<h1 class="title">${esc(order[0].n)} vinder</h1>
    <ol class="board">${order.map(o => `<li>${esc(o.n)}<span class="p">${o.s}</span></li>`).join('')}</ol>
    <button class="btn primary" id="again">Nyt spil</button><button class="btn" data-home>Til forsiden</button></div>`);
  $('#again').onclick = quizmasterSetup;
}

/* ---------- Live (Kahoot-stil) med Supabase Realtime ---------- */
function liveMissing() {
  render(`<div class="screen">${topbar()}<h1 class="title">Live-spil er ikke sat op</h1>
    <p class="lead">Indsæt SUPABASE_URL og SUPABASE_ANON_KEY i config.js for at bruge live-spil.</p>
    <button class="btn" data-home>Til forsiden</button></div>`);
}
async function sbClient() {
  await loadScript(SUPABASE_JS);
  return window.supabase.createClient(CFG.SUPABASE_URL, CFG.SUPABASE_ANON_KEY);
}
const genCode = () => Array.from({ length: 4 }, () => 'ABCDEFGHJKLMNPQRSTUVWXYZ'[Math.floor(Math.random() * 24)]).join('');
const ranking = players => Object.entries(players).map(([id, p]) => ({ id, name: p.name, score: p.score })).sort((a, b) => b.score - a.score);

function liveHostSetup() {
  if (!CFG.SUPABASE_URL) return liveMissing();
  render(`<div class="screen">${topbar()}<h1 class="title">Live på storskærm</h1>
    <p class="lead">Vis denne skærm på TV eller computer. Deltagerne svarer på deres egen telefon – hurtige svar giver flest point.</p>
    ${setupFields({ defaultN: 15 })}
    <div class="field"><span class="lbl">Sekunder pr. spørgsmål</span><small class="hint">Hvor lang tid deltagerne har til hvert svar.</small>${seg('sek', [['10', '10'], ['20', '20'], ['30', '30']], String(CFG.LIVE_SEKUNDER))}</div>
    <label class="auto-next"><input id="auto-next" type="checkbox" checked><span><strong>Gå automatisk videre</strong><small class="hint">Vis først svar og stilling. Gå videre efter 7 sekunder, når alle har svaret eller tiden er gået.</small></span></label>
    <button class="btn primary" id="go">Opret rum</button></div>`);
  bindSetup();
  $('#go').onclick = () => {
    const s = readSetup(); s.sek = +segVal('sek'); s.autoNext = $('#auto-next').checked;
    s.qs = pickSet(s);
    if (!s.qs.length) return toast('Ingen spørgsmål passer – vælg flere emner');
    liveHost(s).catch(e => { toast(e.message); goHome(); });
  };
}

async function liveHost(s) {
  render(`<div class="screen"><p class="loading">Opretter rum …</p></div>`);
  const sb = await sbClient();
  const code = genCode();
  const ch = sb.channel('quiz-' + code, { config: { broadcast: { self: false }, presence: { key: 'host' } } });
  const players = {};             // id -> {name, score, online}
  let st = { phase: 'lobby' };    // offentlig tilstand
  let answers = {}, qStart = 0, tick = null, autoTimer = null, cur = null, streaks = {}, removeGraphicListeners = () => {};
  keepAwake();
  cleanup = () => { clearInterval(tick); clearTimeout(autoTimer); removeGraphicListeners(); sb.removeChannel(ch); };

  const send = payload => ch.send({ type: 'broadcast', event: 'state', payload });
  const publicState = () => st.phase === 'q' ? { ...st, remaining: Math.max(0, st.deadline - Date.now()) } : st;
  const online = () => Object.entries(players).filter(([, p]) => p.online);

  ch.on('presence', { event: 'sync' }, () => {
    const ps = ch.presenceState();
    Object.values(players).forEach(p => p.online = false);
    for (const [id, metas] of Object.entries(ps)) {
      if (id === 'host') continue;
      const m = metas[0] || {};
      players[id] = players[id] || { name: String(m.name || 'Gæst').slice(0, 16), score: 0 };
      players[id].online = true;
    }
    if (st.phase === 'lobby') lobby(); else if (st.phase === 'q') updateCount();
  });
  ch.on('broadcast', { event: 'hello' }, () => send(stripPrivate(publicState())));
  ch.on('broadcast', { event: 'answer' }, ({ payload: a }) => {
    if (st.phase !== 'q' || a.qi !== st.qi || answers[a.id] || !Number.isInteger(a.choice)) return;
    answers[a.id] = { choice: a.choice, ms: Date.now() - qStart };
    if (!players[a.id]) players[a.id] = { name: String(a.name || 'Gæst').slice(0, 16), score: 0, online: true };
    updateCount();
    if (online().length && online().every(([id]) => answers[id])) reveal('all');
  });

  await new Promise((res, rej) => ch.subscribe(async status => {
    if (status === 'SUBSCRIBED') { await ch.track({ role: 'host' }); res(); }
    else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') rej(new Error('Kunne ikke forbinde til Supabase'));
  }));

  const joinUrl = location.origin + location.pathname + '?rum=' + code;
  function lobby() {
    const list = online();
    if (!$('#roomcode')) {
      render(`<div class="screen wide">${topbar()}<div class="lobby">
        <div><p class="lead">Gå ind på</p><p class="joinurl">${esc(location.host + location.pathname)}</p>
          <p class="lead">og tast koden</p><div class="roomcode" id="roomcode">${code}</div><div id="qr"></div></div>
        <div><h1 class="title" id="pc"></h1><div class="names" id="names"></div>
          <button class="btn primary" id="start" disabled>Start quizzen</button>
          <p class="explain" style="margin-top:12px">${s.qs.length} spørgsmål · ${s.sek} sekunder pr. spørgsmål</p></div></div></div>`);
      loadScript(QR_JS).then(() => new QRCode($('#qr'), { text: joinUrl, width: 180, height: 180, colorDark: '#17205A', colorLight: '#ffffff' })).catch(() => { });
      $('#start').onclick = () => nextQ(0);
    }
    $('#pc').textContent = list.length ? `${list.length} ${list.length === 1 ? 'deltager' : 'deltagere'}` : 'Venter på deltagere';
    $('#names').innerHTML = list.map(([, p]) => `<span>${esc(p.name)}</span>`).join('');
    $('#start').disabled = !list.length;
  }

  function nextQ(i) {
    cur = s.qs[i];
    const { opts, correct } = optionsFor(cur);
    answers = {}; qStart = Date.now();
    st = { phase: 'q', qi: i, total: s.qs.length, text: cur.spoergsmaal, kat: KAT[cur.kategori], niv: cur.niveau, opts, deadline: qStart + s.sek * 1000, sek: s.sek };
    st._correct = correct; // sendes ikke (fjernes i publicState nedenfor)
    send(stripPrivate(publicState()));
    render(`<div class="screen wide">${topbar(`Spørgsmål ${i + 1} af ${s.qs.length}`, '<span class="timer" id="t"></span>', i / s.qs.length * 100)}
      <div class="qmeta"><span>${esc(st.kat)}</span>${dots(st.niv)}</div>
      <h2 class="question">${esc(st.text)}</h2>${tilesHtml(opts)}
      <p class="explain" id="cnt" style="margin-top:18px"></p><button class="btn" id="now">Vis svar nu</button></div>`);
    $$('.tile').forEach(t => t.disabled = true);
    $('#now').onclick = () => reveal('manual');
    updateCount();
    clearInterval(tick);
    const upd = () => { const left = Math.ceil((st.deadline - Date.now()) / 1000); if ($('#t')) $('#t').textContent = Math.max(0, left); if (left <= 0) reveal('timeout'); };
    upd(); tick = setInterval(upd, 250);
  }
  function updateCount() {
    if ($('#cnt')) $('#cnt').textContent = `${Object.keys(answers).length} af ${online().length} har svaret`;
  }
  function reveal(cause = 'manual') {
    if (st.phase !== 'q') return;
    clearInterval(tick);
    const correct = st._correct, gained = {}, counts = st.opts.map(() => 0);
    for (const [id, a] of Object.entries(answers)) {
      if (a.choice >= 0 && a.choice < counts.length) counts[a.choice]++;
      logAnswer(cur.id, a.choice === correct);
      if (a.choice === correct) {
        streaks[id] = (streaks[id] || 0) + 1;
        const bonus = streaks[id] >= 2 ? 100 * Math.min(streaks[id], 5) : 0;
        const pts = Math.round(500 + 500 * Math.max(0, 1 - a.ms / (s.sek * 1000))) + bonus;
        gained[id] = pts; players[id].score += pts;
      } else streaks[id] = 0;
    }
    for (const id of Object.keys(players)) if (!answers[id]) streaks[id] = 0;
    const rank = ranking(players);
    const last = st.qi === st.total - 1;
    st = { phase: 'reveal', qi: st.qi, total: st.total, opts: st.opts, correct, gained, ranking: rank, last };
    send(st);
    const boardPlayers = Object.entries(players).map(([id, p]) => ({
      id, name: p.name, score: p.score, gain: gained[id] || 0,
      from: p.score - (gained[id] || 0), streak: streaks[id] || 0
    }));
    const autoCountdown = s.autoNext ? `<p class="auto-countdown" id="auto-countdown" aria-live="polite">${cause === 'all' ? 'Alle har svaret' : cause === 'timeout' ? 'Tiden er gået' : 'Svarene er vist'} · næste spørgsmål om <b>7</b> sek.</p>` : '';
    render(`<div class="screen wide live-reveal">${topbar(`Spørgsmål ${st.qi + 1} af ${st.total}`, '', (st.qi + 1) / st.total * 100)}
      <p class="reveal-question">${esc(cur.spoergsmaal)}</p>
      <div class="reveal-controls"><div class="answer-reveal"><strong>Rigtigt svar:</strong> ${esc(st.opts[correct])}</div><button class="btn graphic-fullscreen" id="graphic-fullscreen">⛶ Vis kun grafikken</button></div>
      <div class="scoreboard-frame-wrap"><iframe id="scoreboard-frame" title="Animeret live-scoreboard" src="scoreboard.html?embed=1" allow="fullscreen" allowfullscreen loading="eager"></iframe></div>
      ${autoCountdown}
      <button class="btn primary" id="next">${last ? 'Se vinderen' : 'Næste spørgsmål'}</button>${reportHtml()}
      <details class="answer-explanation"><summary>Vis svarfordeling og forklaring</summary><div class="tiles reveal-tiles">${st.opts.map((o, i) => `<button class="tile a${i} ${i === correct ? 'right' : 'dim'}" disabled>
        <span class="shape" aria-hidden="true">${SHAPES[i]}</span><span>${esc(o)}</span><span class="cnt">${counts[i]}</span></button>`).join('')}</div>
      <p>${esc(cur.forklaring)}</p></details></div>`);
    bindReport(cur);
    const board = $('#scoreboard-frame');
    board.addEventListener('load', () => board.contentWindow.postMessage({
      type: 'quizjagten-round', round: st.qi + 1, last, players: boardPlayers
    }, location.origin), { once: true });
    $('#graphic-fullscreen').onclick = async () => {
      try {
        await board.requestFullscreen();
        board.contentWindow.postMessage({ type: 'quizjagten-graphic-mode', enabled: true }, location.origin);
      } catch { toast('Fuld skærm understøttes ikke i denne browser'); }
    };
    const syncGraphicMode = () => {
      if (!document.fullscreenElement && board.isConnected) board.contentWindow.postMessage({ type: 'quizjagten-graphic-mode', enabled: false }, location.origin);
    };
    const exitGraphicMode = event => {
      if (event.source === board.contentWindow && event.origin === location.origin && event.data?.type === 'quizjagten-exit-fullscreen') document.exitFullscreen?.();
    };
    document.addEventListener('fullscreenchange', syncGraphicMode);
    window.addEventListener('message', exitGraphicMode);
    removeGraphicListeners = () => { document.removeEventListener('fullscreenchange', syncGraphicMode); window.removeEventListener('message', exitGraphicMode); };
    const advance = () => { clearTimeout(autoTimer); autoTimer = null; removeGraphicListeners(); removeGraphicListeners = () => {}; last ? finish() : nextQ(st.qi + 1); };
    $('#next').onclick = advance;
    if (s.autoNext) {
      let left = 7;
      autoTimer = setInterval(() => {
        left--;
        const counter = $('#auto-countdown');
        if (counter) counter.innerHTML = `Næste spørgsmål om <b>${left}</b> sek.`;
        if (left <= 0) advance();
      }, 1000);
    }
  }
  function finish() {
    st = { phase: 'end', ranking: ranking(players) };
    send(st);
    releaseWake();
    const r = st.ranking;
    render(`<div class="screen wide">${topbar()}<h1 class="title">${r.length ? esc(r[0].name) + ' vinder' : 'Spillet er slut'}</h1>
      <ol class="board">${r.map(x => `<li>${esc(x.name)}<span class="p">${x.score}</span></li>`).join('')}</ol>
      <button class="btn primary" id="again">Nyt spil</button><button class="btn" data-home>Til forsiden</button></div>`);
    $('#again').onclick = () => { goHome(); liveHostSetup(); };
  }
  lobby();
}
function stripPrivate(o) { const { _correct, deadline, ...rest } = o; return rest; }

function liveJoin(code = '') {
  if (!CFG.SUPABASE_URL) return liveMissing();
  render(`<div class="screen">${topbar()}<h1 class="title">Deltag i live-spil</h1>
    <div class="field"><label for="code">Kode</label><input type="text" id="code" class="code" maxlength="4" autocomplete="off" value="${esc(code)}"></div>
    <div class="field"><label for="nm">Dit navn</label><input type="text" id="nm" maxlength="16" value="${esc(store.get('navn', ''))}"></div>
    <button class="btn primary" id="go">Deltag</button></div>`);
  (code ? $('#nm') : $('#code')).focus();
  $('#go').onclick = () => {
    const c = $('#code').value.trim().toUpperCase(), n = $('#nm').value.trim();
    if (c.length !== 4) return toast('Koden har 4 bogstaver');
    if (!n) return toast('Skriv dit navn');
    store.set('navn', n);
    livePlayer(c, n).catch(e => { toast(e.message); goHome(); });
  };
}

async function livePlayer(code, name) {
  render(`<div class="screen"><p class="loading">Forbinder …</p></div>`);
  const sb = await sbClient();
  let id = sessionStorage.getItem('pid');
  if (!id) { id = Math.random().toString(36).slice(2, 10); sessionStorage.setItem('pid', id); }
  const ch = sb.channel('quiz-' + code, { config: { broadcast: { self: false }, presence: { key: id } } });
  let myChoice = {}, tick = null, gotState = false;
  keepAwake();
  cleanup = () => { clearInterval(tick); sb.removeChannel(ch); };

  const wait = (h, p) => render(`<div class="screen">${topbar(esc(name), code)}<div class="wait"><h1>${h}</h1><p>${p}</p></div></div>`);

  ch.on('broadcast', { event: 'state' }, ({ payload: s }) => { gotState = true; show(s); });
  await new Promise((res, rej) => ch.subscribe(async status => {
    if (status === 'SUBSCRIBED') {
      await ch.track({ role: 'player', name });
      ch.send({ type: 'broadcast', event: 'hello', payload: {} });
      res();
    } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') rej(new Error('Kunne ikke forbinde'));
  }));
  wait('Du er med', 'Venter på at værten starter quizzen.');
  setTimeout(() => { if (!gotState) wait('Ingen vært endnu', `Tjek at koden ${code} er rigtig. Du kommer automatisk med, når værten åbner rummet.`); }, 5000);

  function show(s) {
    clearInterval(tick);
    if (s.phase === 'lobby') return wait('Du er med', 'Venter på at værten starter quizzen.');
    if (s.phase === 'q') {
      if (myChoice[s.qi] !== undefined) return wait('Svar sendt', 'Venter på de andre …');
      const deadline = Date.now() + (s.remaining ?? s.sek * 1000);
      render(`<div class="screen">${topbar(`${s.qi + 1} af ${s.total}`, '<span class="timer" id="t"></span>')}
        <h2 class="question" style="font-size:1.25rem">${esc(s.text)}</h2>${tilesHtml(s.opts, 'big')}</div>`);
      const upd = () => { const left = Math.max(0, Math.ceil((deadline - Date.now()) / 1000)); if ($('#t')) $('#t').textContent = left; if (!left) { clearInterval(tick); $$('.tile').forEach(t => t.disabled = true); } };
      upd(); tick = setInterval(upd, 250);
      $$('.tile').forEach(b => b.onclick = () => {
        myChoice[s.qi] = +b.dataset.i;
        ch.send({ type: 'broadcast', event: 'answer', payload: { id, name, qi: s.qi, choice: +b.dataset.i } });
        navigator.vibrate?.(30);
        wait('Svar sendt', 'Venter på de andre …');
      });
      return;
    }
    if (s.phase === 'reveal') {
      const mine = myChoice[s.qi], ok = mine === s.correct, pts = s.gained?.[id] || 0;
      const pos = s.ranking.findIndex(r => r.id === id) + 1;
      const me = s.ranking.find(r => r.id === id);
      navigator.vibrate?.(ok ? 40 : [60, 40, 60]);
      render(`<div class="screen">${topbar(esc(name), me ? `${me.score} p` : '')}<div class="wait">
        <h1 class="verdict ${ok ? 'ok' : 'no'}">${mine === undefined ? 'Intet svar' : ok ? `Rigtigt +${pts}` : 'Forkert'}</h1>
        <p>Svaret var: <strong>${esc(s.opts[s.correct])}</strong></p>
        ${pos ? `<p>Du ligger nummer ${pos} af ${s.ranking.length}</p>` : ''}</div></div>`);
      return;
    }
    if (s.phase === 'end') {
      releaseWake();
      const pos = s.ranking.findIndex(r => r.id === id) + 1;
      render(`<div class="screen">${topbar()}<h1 class="title">${pos === 1 ? 'Du vandt!' : pos ? `Du blev nummer ${pos}` : 'Spillet er slut'}</h1>
        <ol class="board">${s.ranking.map(r => `<li class="${r.id === id ? 'me' : ''}">${esc(r.name)}<span class="p">${r.score}</span></li>`).join('')}</ol>
        <button class="btn" data-home>Til forsiden</button></div>`);
    }
  }
}

/* ---------- Opstart ---------- */
window.addEventListener('beforeinstallprompt', e => {
  e.preventDefault();
  installPrompt = e;
  const btn = $('#install');
  if (btn) btn.hidden = false;
  if ($('#quiz-install-backdrop')) { closeInstallPopup(false); showInstallPopup(); }
});
window.addEventListener('appinstalled', () => {
  installPrompt = null;
  store.set('quizjagten-installed', true);
  const btn = $('#install');
  if (btn) btn.hidden = true;
  closeInstallPopup(false);
});

async function init() {
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => { });
  try {
    const res = await fetch('questions.json', { cache: 'no-cache' });
    ALL = await res.json();
  } catch {
    render(`<div class="screen"><h1 class="title">Spørgsmålene kunne ikke hentes</h1><p class="lead">Tjek forbindelsen og genindlæs siden.</p></div>`);
    return;
  }
  BANK = ALL.filter(q => q.status === 'godkendt' || (CFG.VIS_KLADDER && q.status === 'kladde'));
  BANK_MC = BANK.filter(q => q.type !== 'fri');
  document.title = CFG.APP_NAVN;
  const p = new URLSearchParams(location.search);
  if (p.has('duel')) return receiveChallenge(p);
  if (p.has('rum')) return liveJoin(p.get('rum').toUpperCase().slice(0, 4));
  home();
}
init();
