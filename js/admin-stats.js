// =====================================================================
// admin-stats.js – fælles nøgletals-stribe øverst på alle admin-sider.
// Kaldes med initAdminStats('<aktiv side>') efter login. Henter quiz.admin_stats.
// Tallene caches kortvarigt, så de ikke hentes igen ved hvert sideskift.
// =====================================================================
const ADMIN_STATS_CACHE_MS = 60000
const ADMIN_FREE_STORAGE = 1024 * 1024 * 1024        // Supabase Free: 1 GB filer

function adminStatsCss() {
  if (document.getElementById('admin-stats-css')) return
  const el = document.createElement('style'); el.id = 'admin-stats-css'
  el.textContent = `
    #admin-stats { display:flex; gap:8px; overflow-x:auto; padding:10px 0 2px; margin-bottom:16px; }
    #admin-stats .s { flex:1 0 auto; min-width:118px; background:#16213e; color:#eaeaea; border-radius:12px; padding:9px 13px; border-top:3px solid #0f3460; text-decoration:none; display:block; }
    #admin-stats a.s:hover { outline:2px solid rgba(255,255,255,.25); }
    #admin-stats .s.hot { border-top-color:#e94560; } #admin-stats .s.warn b { color:#fbbf24; }
    #admin-stats b { display:block; font-family:'Syne','Inter',sans-serif; font-size:1.45rem; font-weight:800; line-height:1.05; }
    #admin-stats span { display:block; font-size:.72rem; color:#8892a4; margin-top:3px; white-space:nowrap; }
    @media (max-width:760px) { #admin-stats .s { min-width:104px; padding:8px 11px; } #admin-stats b { font-size:1.2rem; } }
    @media print { #admin-stats { display:none; } }`
  document.head.appendChild(el)
}

// page: 'overview' | 'customers' | 'quizzes' – den aktuelle side linkes ikke til sig selv
async function initAdminStats(page) {
  const host = document.getElementById('admin-stats')
  if (!host) return null
  adminStatsCss()
  let d = null
  try {
    const raw = sessionStorage.getItem('admin-stats')
    if (raw) { const c = JSON.parse(raw); if (Date.now() - c.t < ADMIN_STATS_CACHE_MS) d = c.d }
  } catch (_) {}
  if (!d) {
    const { data, error } = await sb.schema('quiz').rpc('admin_stats')
    if (error || !data) { host.style.display = 'none'; return null }
    d = data
    try { sessionStorage.setItem('admin-stats', JSON.stringify({ t: Date.now(), d })) } catch (_) {}
  }
  const mb = d.storage_bytes == null ? null : d.storage_bytes / 1048576
  const pct = d.storage_bytes == null ? 0 : d.storage_bytes / ADMIN_FREE_STORAGE * 100
  const cells = [
    { n: d.quizzes_live, l: 'Aktive løb', cls: 'hot', href: page === 'quizzes' ? null : 'dashboard.html' },
    { n: d.orders_new, l: 'Nye bestillinger', cls: d.orders_new > 0 ? 'warn' : '', href: page === 'overview' ? null : 'overview.html' },
    { n: d.customers, l: 'Kunder', href: page === 'customers' ? null : 'customers.html' },
    { n: d.quizzes, l: 'Løb i alt', href: page === 'quizzes' ? null : 'dashboard.html' },
    { n: d.teams, l: 'Hold i alt' },
    { n: d.answers_30d, l: 'Svar (30 dage)' },
    { n: mb == null ? '–' : (mb < 10 ? mb.toFixed(1) : Math.round(mb)) + ' MB', l: 'Fotolager' + (d.storage_bytes == null ? '' : ' (' + Math.round(pct) + ' %)'), cls: pct >= 70 ? 'warn' : '' },
    { n: d.errors_24h, l: 'Fejl (24 t)', cls: d.errors_24h > 0 ? 'warn' : '', href: page === 'overview' ? null : 'overview.html' }
  ]
  host.innerHTML = cells.map(c => {
    const inner = `<b>${c.n ?? '–'}</b><span>${c.l}</span>`
    const cls = 's' + (c.cls ? ' ' + c.cls : '')
    return c.href ? `<a class="${cls}" href="${c.href}">${inner}</a>` : `<div class="${cls}">${inner}</div>`
  }).join('')
  return d
}

// Kaldes efter en handling der ændrer tallene (ny kunde, slettet løb, bestilling behandlet)
function refreshAdminStats(page) {
  try { sessionStorage.removeItem('admin-stats') } catch (_) {}
  return initAdminStats(page)
}
