// =============================================================
// api.js – Supabase-klient og hjælpefunktioner
// Kræver: config.js indlæst først, supabase-js fra CDN
// =============================================================

const { createClient } = supabase

// Basis-klient (ingen session-header)
let sb = createClient(SUPABASE_URL, SUPABASE_ANON)

// ── PIN session ───────────────────────────────────────────────

function getPinSession() {
  try {
    const raw = localStorage.getItem('pin_session')
    if (!raw) return null
    const s = JSON.parse(raw)
    if (!s.expires_at || new Date(s.expires_at) < new Date()) {
      localStorage.removeItem('pin_session')
      return null
    }
    return s   // { session_id, is_admin, customer_id, expires_at }
  } catch { return null }
}

function createPinClient(sessionId) {
  return createClient(SUPABASE_URL, SUPABASE_ANON, {
    global: { headers: { 'x-session': sessionId } }
  })
}

function activatePinClient() {
  const s = getPinSession()
  if (!s) return false
  sb = createPinClient(s.session_id)
  return true
}

// ── Auth ──────────────────────────────────────────────────────

async function getSession() {
  const pinSession = getPinSession()
  if (pinSession) return { type: 'pin', ...pinSession }
  const { data: { session } } = await sb.auth.getSession()
  return session
}

async function signInWithMagicLink(email) {
  const root = location.href.substring(0, location.href.lastIndexOf('/') + 1)
  const { error } = await sb.auth.signInWithOtp({
    email,
    options: { emailRedirectTo: root + 'app/dashboard.html' }
  })
  return error
}

async function signOut() {
  if (getPinSession()) {
    // slet sessionen på serveren (ellers lever den videre til den udløber)
    try { await sb.schema('quiz').rpc('end_session') } catch (_) {}
    localStorage.removeItem('pin_session')
    location.href = 'login.html'
    return
  }
  await sb.auth.signOut()
  const depth = location.pathname.split('/').length - 2
  location.href = '../'.repeat(Math.max(0, depth)) + 'index.html'
}

// ── Hold-token adgang (ingen login) ──────────────────────────

function getTeamToken() {
  return new URLSearchParams(location.search).get('t')
}

async function getTeamByToken(token) {
  const { data, error } = await sb
    .schema('quiz')
    .rpc('get_team_by_token', { p_token: token })
  return { data, error }
}

// ── Fejllogging ───────────────────────────────────────────────

async function logError(page, message) {
  await sb.schema('quiz').from('errors').insert({ page, message })
}

window.addEventListener('error', e => {
  logError(location.pathname, e.message)
})

// Sletter et løbs deltagerdata (hold, svar, positioner og FOTOS i Storage) via Edge Function 'purge-data'.
// Kun quizmaster/admin må (serveren tjekker sessionen), og løbet må ikke køre.
async function purgeQuizData(quizId, includeTaskImages = false) {
  const s = getPinSession()
  const { data, error } = await sb.functions.invoke('purge-data', {
    body: { quiz_id: quizId, session_id: s?.session_id, include_task_images: includeTaskImages }
  })
  if (error) {
    let msg = 'Sletningen fejlede – prøv igen.'
    try { const b = await error.context.json(); msg = b.error || msg } catch (_) {}
    throw new Error(msg)
  }
  return data
}
