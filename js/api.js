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
    return s   // { session_id, is_admin, quiz_id, expires_at }
  } catch { return null }
}
 
// Returnerer en Supabase-klient med x-session header sat
function createPinClient(sessionId) {
  return createClient(SUPABASE_URL, SUPABASE_ANON, {
    global: { headers: { 'x-session': sessionId } }
  })
}
 
// Aktiver PIN-klienten globalt (kald fra dashboard/editor efter login-tjek)
function activatePinClient() {
  const s = getPinSession()
  if (!s) return false
  sb = createPinClient(s.session_id)
  return true
}
 
// ── Auth ──────────────────────────────────────────────────────
 
// Returnerer enten { type:'pin', ...session } eller Supabase-session eller null
async function getSession() {
  const pinSession = getPinSession()
  if (pinSession) return { type: 'pin', ...pinSession }
  const { data: { session } } = await sb.auth.getSession()
  return session   // null hvis ikke logget ind
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
  // PIN-session
  if (getPinSession()) {
    localStorage.removeItem('pin_session')
    location.href = 'login.html'
    return
  }
  // Supabase-session
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