// =====================================================================
// themes.js – temaer til løbene. Et tema = farver + skrifttype + ord + kortstil + emojis.
// Kunden vælger tema pr. løb (quizzes.theme); spiller, scoreboard og diplomer følger med.
// Tilføj et nyt tema ved at kopiere et af dem herunder og give det et nyt id (kun a-z, 0-9, _ og -).
// =====================================================================

const JAGTEN_BASE_WORDS = {
  welcomeKicker: 'Velkommen til',
  startBtn: 'Start jagten',
  resumeBtn: 'Fortsæt jagten',
  nextLabel: 'NÆSTE STOP',
  allLabel: 'Alle stop',
  stopsDef: 'stopene',
  taskWord: 'Opgave',
  arrive: 'Fremme!',
  arriveSub: 'I er ved stoppet',
  correct: 'Korrekt!',
  wrong: 'Forkert svar',
  photoOk: 'Billede modtaget',
  photoThanks: 'Tak for billedet!',
  finishTitle: 'Tillykke!',
  finishText: 'I har gennemført alle stop på jagten.',
  heat: ['Iskoldt', 'Koldt', 'Lunkent', 'Varmt', 'Brændende varmt', 'Fremme!']   // fra langt væk → fremme
}

const JAGTEN_THEMES = {
  standard: {
    name: 'Klassisk', emoji: '🗺️', trophy: '🏆', pinDone: '✓', dark: true,
    blurb: 'Mørkt og stilfuldt – passer til de fleste løb',
    vars: { '--night': '#0d0f14', '--deep': '#13161e', '--panel': '#1a1e28', '--border': 'rgba(255,255,255,.1)', '--tint': 'rgba(255,255,255,.07)',
            '--glass': 'rgba(13,15,20,.88)', '--fade': 'rgba(13,15,20,.95)', '--accent': '#e8c84a', '--accent-ink': '#0d0f14',
            '--bad': '#e94560', '--good': '#22c55e', '--muted': 'rgba(255,255,255,.5)', '--text': '#f0eeea', '--radius': '16px', '--pin-radius': '50%' },
    fonts: { display: "'Syne', system-ui, sans-serif", body: "'Inter', system-ui, sans-serif" },
    map: { style: 'dark', tint: '' },
    confetti: ['#e8c84a', '#22c55e', '#e94560', '#a78bfa', '#60a5fa'],
    words: {}
  },

  skattejagt: {
    name: 'Skattejagt (børn)', emoji: '🏴‍☠️', trophy: '💰', pinDone: '💰', dark: false,
    blurb: 'Lyst, farverigt og sjovt – til børn og børnefamilier',
    vars: { '--night': '#fff4d9', '--deep': '#ffe7a8', '--panel': '#ffffff', '--border': 'rgba(80,50,10,.16)', '--tint': 'rgba(80,50,10,.07)',
            '--glass': 'rgba(255,250,235,.94)', '--fade': 'rgba(255,244,217,.97)', '--accent': '#f59e0b', '--accent-ink': '#3b2a14',
            '--bad': '#dc2626', '--good': '#16a34a', '--muted': 'rgba(59,42,20,.62)', '--text': '#3b2a14', '--radius': '22px', '--pin-radius': '50%' },
    fonts: { display: "'Fredoka', system-ui, sans-serif", body: "'Fredoka', system-ui, sans-serif" },
    map: { style: 'watercolor', tint: '' },
    confetti: ['#f59e0b', '#16a34a', '#dc2626', '#2563eb', '#db2777'],
    words: {
      welcomeKicker: 'Ahoj! Velkommen til', startBtn: 'Sæt sejl! ⛵', resumeBtn: 'Sejl videre',
      nextLabel: 'NÆSTE SKAT', allLabel: 'Alle skatte', stopsDef: 'skattene', arrive: 'Her gemmer skatten sig!', arriveSub: 'X markerer stedet',
      correct: 'Skat i sækken!', wrong: 'Øv – forkert kurs!', photoThanks: 'Hvor flot et billede!',
      finishTitle: 'Skatten er jeres!', finishText: 'I har fundet alle skattene – flot sejlet, kaptajner!',
      heat: ['Iskoldt', 'Koldt', 'Lunkent', 'Varmt', 'Glødende varmt', 'X markerer stedet!']
    }
  },

  jul: {
    name: 'Julemarch', emoji: '🎄', trophy: '🎁', pinDone: '🎁', dark: true,
    blurb: 'Rød, grøn og guld – til julemarcher og juleløb',
    vars: { '--night': '#0c241b', '--deep': '#12362a', '--panel': '#164032', '--border': 'rgba(255,255,255,.14)', '--tint': 'rgba(255,255,255,.08)',
            '--glass': 'rgba(12,36,27,.9)', '--fade': 'rgba(12,36,27,.95)', '--accent': '#f6d365', '--accent-ink': '#1b2a10',
            '--bad': '#e0384f', '--good': '#4ade80', '--muted': 'rgba(255,255,255,.6)', '--text': '#f7f3e8', '--radius': '18px', '--pin-radius': '50%' },
    fonts: { display: "'Syne', system-ui, sans-serif", body: "'Inter', system-ui, sans-serif" },
    map: { style: 'winter', tint: '' },
    confetti: ['#f6d365', '#e0384f', '#4ade80', '#ffffff', '#93c5fd'],
    words: {
      startBtn: 'Start julemarchen', resumeBtn: 'Fortsæt julemarchen', arrive: 'Julestemning!', arriveSub: 'I er fremme',
      correct: 'Ho ho – rigtigt!', wrong: 'Næsten – men forkert',
      finishTitle: 'Glædelig jul!', finishText: 'I har gennemført hele julemarchen – godt gået!'
    }
  },

  krimi: {
    name: 'Krimi / mysterium', emoji: '🕵️', trophy: '🔍', pinDone: '🔍', dark: true,
    blurb: 'Mørkt og gådefuldt – til mordgåder og detektivløb',
    vars: { '--night': '#14110d', '--deep': '#1b1712', '--panel': '#241f18', '--border': 'rgba(216,179,106,.2)', '--tint': 'rgba(216,179,106,.08)',
            '--glass': 'rgba(20,17,13,.9)', '--fade': 'rgba(20,17,13,.95)', '--accent': '#d8b36a', '--accent-ink': '#1a140a',
            '--bad': '#c2453a', '--good': '#7aa862', '--muted': 'rgba(240,226,200,.58)', '--text': '#f0e2c8', '--radius': '6px', '--pin-radius': '28%' },
    fonts: { display: "'Special Elite', 'Courier New', monospace", body: "'Inter', system-ui, sans-serif" },
    map: { style: 'dark', tint: 'sepia(.45) saturate(.85) contrast(1.05)' },
    confetti: ['#d8b36a', '#c2453a', '#7aa862', '#f0e2c8'],
    words: {
      welcomeKicker: 'Ny sag:', startBtn: 'Åbn sagen', resumeBtn: 'Genoptag efterforskningen',
      nextLabel: 'NÆSTE SPOR', allLabel: 'Alle spor', stopsDef: 'sporene', arrive: 'Nyt spor!', arriveSub: 'Se jer omkring…',
      correct: 'Et gennembrud!', wrong: 'En blindgyde…', photoOk: 'Bevis modtaget', photoThanks: 'Bevis sikret',
      finishTitle: 'Sagen er opklaret!', finishText: 'I har fulgt alle sporene – flot detektivarbejde.',
      heat: ['Koldt spor', 'Svagt spor', 'Sporet er friskt', 'Tæt på', 'Lige i hælene', 'Her er det!']
    }
  },

  historie: {
    name: 'Byvandring / historie', emoji: '🏛️', trophy: '📜', pinDone: '✓', dark: false,
    blurb: 'Pergament og blæk – til historiske byvandringer',
    vars: { '--night': '#f1e7d0', '--deep': '#e8dbbd', '--panel': '#fbf5e6', '--border': 'rgba(70,45,15,.2)', '--tint': 'rgba(70,45,15,.07)',
            '--glass': 'rgba(251,245,230,.95)', '--fade': 'rgba(241,231,208,.97)', '--accent': '#8c2f1b', '--accent-ink': '#fbf5e6',
            '--bad': '#a32a1e', '--good': '#3f6b34', '--muted': 'rgba(58,46,28,.65)', '--text': '#3a2e1c', '--radius': '10px', '--pin-radius': '50%' },
    fonts: { display: "'Playfair Display', Georgia, serif", body: "'Inter', system-ui, sans-serif" },
    map: { style: 'light', tint: 'sepia(.55) saturate(1.1) contrast(.95)' },
    confetti: ['#8c2f1b', '#b8962e', '#3f6b34', '#3a2e1c'],
    words: {
      welcomeKicker: 'Byvandring:', startBtn: 'Start vandringen', resumeBtn: 'Fortsæt vandringen',
      nextLabel: 'NÆSTE POST', allLabel: 'Alle poster', stopsDef: 'posterne', arrive: 'I er fremme', arriveSub: 'Se jer omkring',
      correct: 'Rigtigt!', wrong: 'Desværre ikke rigtigt',
      finishTitle: 'Vandringen er gennemført', finishText: 'I har besøgt alle poster – tak for en god tur.'
    }
  },

  natur: {
    name: 'Natur / friluft', emoji: '🌲', trophy: '🏅', pinDone: '✓', dark: true,
    blurb: 'Grønt og jordnært – til skov, strand og naturløb',
    vars: { '--night': '#0f1f14', '--deep': '#15291a', '--panel': '#1b3523', '--border': 'rgba(255,255,255,.12)', '--tint': 'rgba(255,255,255,.07)',
            '--glass': 'rgba(15,31,20,.9)', '--fade': 'rgba(15,31,20,.95)', '--accent': '#a3e635', '--accent-ink': '#10200a',
            '--bad': '#f0654f', '--good': '#4ade80', '--muted': 'rgba(255,255,255,.56)', '--text': '#eef5e6', '--radius': '16px', '--pin-radius': '50%' },
    fonts: { display: "'Syne', system-ui, sans-serif", body: "'Inter', system-ui, sans-serif" },
    map: { style: 'outdoor', tint: '' },
    confetti: ['#a3e635', '#4ade80', '#f0654f', '#fde047'],
    words: {
      startBtn: 'Af sted!', resumeBtn: 'Fortsæt turen', nextLabel: 'NÆSTE POST', allLabel: 'Alle poster', stopsDef: 'posterne',
      correct: 'Godt set!', finishTitle: 'Flot tur!', finishText: 'I har klaret alle posterne.'
    }
  },

  firma: {
    name: 'Teambuilding / firma', emoji: '🤝', trophy: '🏆', pinDone: '✓', dark: true,
    blurb: 'Ren og professionel – til firmaarrangementer',
    vars: { '--night': '#0b1220', '--deep': '#101a2e', '--panel': '#16223a', '--border': 'rgba(255,255,255,.1)', '--tint': 'rgba(255,255,255,.07)',
            '--glass': 'rgba(11,18,32,.9)', '--fade': 'rgba(11,18,32,.95)', '--accent': '#38bdf8', '--accent-ink': '#06121f',
            '--bad': '#f87171', '--good': '#34d399', '--muted': 'rgba(255,255,255,.55)', '--text': '#eaf1ff', '--radius': '12px', '--pin-radius': '50%' },
    fonts: { display: "'Syne', system-ui, sans-serif", body: "'Inter', system-ui, sans-serif" },
    map: { style: 'dark', tint: '' },
    confetti: ['#38bdf8', '#34d399', '#f87171', '#fbbf24', '#a78bfa'],
    words: {
      welcomeKicker: 'Teambuilding:', startBtn: 'Start udfordringen', resumeBtn: 'Fortsæt udfordringen',
      nextLabel: 'NÆSTE POST', allLabel: 'Alle poster', stopsDef: 'posterne',
      correct: 'Flot teamwork!', wrong: 'Ikke helt', finishTitle: 'Flot gennemført!', finishText: 'I har løst alle opgaverne – godt samarbejde.'
    }
  }
}

// Find temaet (ukendt/tomt → standard). 'standard' er også navnet på kolonnens gamle default.
function jagtenTheme(id) {
  const t = JAGTEN_THEMES[String(id || '')] || JAGTEN_THEMES.standard
  return t
}

// Ord = temaets ord + evt. kundens egne overskrivninger (quizzes.theme_texts, en JSON-nøgle→tekst)
function jagtenWords(theme, overrides) {
  const w = Object.assign({}, JAGTEN_BASE_WORDS, theme.words || {})
  if (overrides && typeof overrides === 'object') {
    Object.keys(overrides).forEach(k => { if (typeof overrides[k] === 'string' && k in JAGTEN_BASE_WORDS && k !== 'heat') w[k] = overrides[k] })
  }
  return w
}

// Sætter farver/skrifttyper på siden. Returnerer { id, theme, words }.
function applyTheme(id, overrides, root) {
  const theme = jagtenTheme(id)
  const el = root || document.documentElement
  Object.keys(theme.vars).forEach(k => el.style.setProperty(k, theme.vars[k]))
  el.style.setProperty('--font-display', theme.fonts.display)
  el.style.setProperty('--font-body', theme.fonts.body)
  el.setAttribute('data-theme', JAGTEN_THEMES[id] ? id : 'standard')
  el.setAttribute('data-dark', theme.dark ? '1' : '0')
  const meta = document.querySelector('meta[name="theme-color"]')
  if (meta) meta.setAttribute('content', theme.vars['--night'])
  return { id: JAGTEN_THEMES[id] ? id : 'standard', theme, words: jagtenWords(theme, overrides) }
}

// Til vælgere i editorerne: [[id, tema], …]
function jagtenThemeList() { return Object.keys(JAGTEN_THEMES).map(id => [id, JAGTEN_THEMES[id]]) }
