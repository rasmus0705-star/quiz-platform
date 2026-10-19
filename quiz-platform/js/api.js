// =============================================================
// api.js – Supabase-klient og hjælpefunktioner
// Kræver: config.js indlæst først, supabase-js fra CDN
// =============================================================

const { createClient } = supabase;
const sb = createClient(SUPABASE_URL, SUPABASE_ANON);

// ---- Auth (quizmaster) --------------------------------------
async function signInWithMagicLink(email) {
    const { error } = await sb.auth.signInWithOtp({
        email,
        options: { emailRedirectTo: `${location.origin}/app/dashboard.html` }
    });
    return error;
}

async function getSession() {
    const { data: { session } } = await sb.auth.getSession();
    return session;
}

async function signOut() {
    await sb.auth.signOut();
    location.href = '/index.html';
}

// ---- Hold-token adgang (ingen login) ------------------------
// Hold bruger token fra URL: ?t=<token>
function getTeamToken() {
    return new URLSearchParams(location.search).get('t');
}

// Hent team-data via token (kalder RPC – oprettes i 002_quiz_rpc.sql)
async function getTeamByToken(token) {
    const { data, error } = await sb
        .schema('quiz')
        .rpc('get_team_by_token', { p_token: token });
    return { data, error };
}

// ---- Fejllogging --------------------------------------------
async function logError(page, message) {
    await sb.schema('quiz').from('errors').insert({ page, message });
}

window.addEventListener('error', e => {
    logError(location.pathname, e.message);
});
