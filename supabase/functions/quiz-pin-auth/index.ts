// quiz-pin-auth – validerer PIN og opretter session
// Env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ADMIN_PIN

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL  = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ADMIN_PIN_ENV = Deno.env.get('ADMIN_PIN') ?? ''

const CORS = {
  'Access-Control-Allow-Origin' : '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    'SHA-256', new TextEncoder().encode(text)
  )
  return Array.from(new Uint8Array(buf))
    .map(b => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS })

  let body: { quiz_id?: string; pin?: string }
  try { body = await req.json() } catch {
    return Response.json({ error: 'Ugyldig request' }, { status: 400, headers: CORS })
  }

  const { quiz_id, pin } = body
  if (!pin) {
    return Response.json({ error: 'PIN mangler' }, { status: 400, headers: CORS })
  }

  const sb       = createClient(SUPABASE_URL, SERVICE_KEY)
  const pinHash  = await sha256(pin.trim())
  const adminHash = await sha256(ADMIN_PIN_ENV.trim())

  let sessionQuizId: string | null = null
  let isAdmin = false
  let expiresAt: Date

  // ── Admin-PIN ──────────────────────────────────────────────
  if (ADMIN_PIN_ENV && pinHash === adminHash) {
    isAdmin       = true
    sessionQuizId = null
    expiresAt     = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) // 7 dage

  // ── Quiz-PIN ───────────────────────────────────────────────
  } else if (quiz_id) {
    const { data: quiz, error } = await sb
      .schema('quiz').from('quizzes')
      .select('id, pin_hash, pin_expires_at')
      .eq('id', quiz_id)
      .single()

    if (error || !quiz) {
      return Response.json({ error: 'Quiz ikke fundet' }, { status: 404, headers: CORS })
    }
    if (!quiz.pin_hash || quiz.pin_hash !== pinHash) {
      return Response.json({ error: 'Forkert PIN' }, { status: 401, headers: CORS })
    }
    if (quiz.pin_expires_at && new Date(quiz.pin_expires_at) < new Date()) {
      return Response.json({ error: 'PIN er udløbet' }, { status: 401, headers: CORS })
    }

    sessionQuizId = quiz_id
    expiresAt     = quiz.pin_expires_at
      ? new Date(quiz.pin_expires_at)
      : new Date(Date.now() + 24 * 60 * 60 * 1000) // 24 timer fallback

  } else {
    return Response.json({ error: 'Forkert PIN' }, { status: 401, headers: CORS })
  }

  // ── Opret session ─────────────────────────────────────────
  const { data: session, error: sessionErr } = await sb
    .schema('quiz').from('sessions')
    .insert({
      quiz_id   : sessionQuizId,
      is_admin  : isAdmin,
      expires_at: expiresAt.toISOString()
    })
    .select('id')
    .single()

  if (sessionErr || !session) {
    console.error('Session insert fejl:', sessionErr)
    return Response.json({ error: 'Sessionsoprettelse fejlede' }, { status: 500, headers: CORS })
  }

  return Response.json({
    session_id : session.id,
    is_admin   : isAdmin,
    quiz_id    : sessionQuizId,
    expires_at : expiresAt.toISOString()
  }, { headers: CORS })
})
