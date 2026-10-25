// quiz-pin-auth   (supabase/functions/quiz-pin-auth/index.ts)
// Admin:  body { pin }                       → admin-session (7 dage)
// Kunde:  body { customer_id, pin }          → kunde-session (max 7 dage / PIN-udløb)
// Env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ADMIN_PIN
//
// Kunde-PIN verificeres i databasen (verify_customer_pin, bcrypt) - ikke her.
// Fejlbeskeder er ens uanset om kunden findes (ingen konto-gætteri).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL  = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ADMIN_PIN_ENV = Deno.env.get('ADMIN_PIN') ?? '';

const CORS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });

  let body: { customer_id?: string; pin?: string };
  try { body = await req.json(); } catch { return json({ error: 'Ugyldig request' }, 400); }

  const { customer_id, pin } = body;
  if (!pin || typeof pin !== 'string' || pin.length > 32) return json({ error: 'PIN mangler' }, 400);
  if (customer_id && !UUID_RE.test(customer_id)) return json({ error: 'Ugyldigt login-link' }, 400);

  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const q  = sb.schema('quiz');
  const target = customer_id ?? 'admin';

  // ── Rate-limit: max 5 forkerte forsøg pr. 10 min pr. target ──
  const windowStart = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { count: recentFails } = await q.from('login_attempts')
    .select('id', { count: 'exact', head: true })
    .eq('target', target).eq('success', false).gte('created_at', windowStart);
  if ((recentFails ?? 0) >= 5) {
    return json({ error: 'For mange forkerte forsøg. Prøv igen om 10 minutter.' }, 429);
  }

  const logAttempt = async (success: boolean) => {
    try { await q.from('login_attempts').insert({ target, success }); }
    catch (e) { console.error('Kunne ikke logge login-forsøg:', e); }
  };

  let customerId: string | null = null;
  let isAdmin = false;
  let expiresAt: Date;

  if (customer_id) {
    // ── Kunde ──
    const { data: ok } = await q.rpc('verify_customer_pin', {
      p_customer_id: customer_id, p_pin: pin.trim(),
    });
    if (ok !== true) { await logAttempt(false); return json({ error: 'Forkert PIN' }, 401); }

    const { data: cust } = await q.from('customers')
      .select('pin_expires_at').eq('id', customer_id).maybeSingle();
    if (cust?.pin_expires_at && new Date(cust.pin_expires_at) < new Date()) {
      await logAttempt(false);
      return json({ error: 'PIN er udløbet' }, 401);
    }

    customerId = customer_id;
    const cap = Date.now() + WEEK_MS;
    expiresAt = new Date(cust?.pin_expires_at
      ? Math.min(cap, new Date(cust.pin_expires_at).getTime()) : cap);

  } else if (ADMIN_PIN_ENV && (await sha256(pin.trim())) === (await sha256(ADMIN_PIN_ENV.trim()))) {
    // ── Admin ──
    isAdmin = true;
    expiresAt = new Date(Date.now() + WEEK_MS);

  } else {
    await logAttempt(false);
    return json({ error: 'Forkert PIN' }, 401);
  }

  // ── Opret session ──
  const { data: session, error: sessionErr } = await q.from('sessions')
    .insert({ customer_id: customerId, is_admin: isAdmin, expires_at: expiresAt.toISOString() })
    .select('id').single();
  if (sessionErr || !session) {
    console.error('Session insert fejl:', sessionErr);
    return json({ error: 'Sessionsoprettelse fejlede' }, 500);
  }

  await logAttempt(true);

  // Oprydning af udløbne sessioner (billig, og holder tabellen lille)
  try { await q.from('sessions').delete().lt('expires_at', new Date().toISOString()); } catch (_) { /* ignorer */ }

  return json({
    session_id: session.id, is_admin: isAdmin,
    customer_id: customerId, expires_at: expiresAt.toISOString(),
  });
});
