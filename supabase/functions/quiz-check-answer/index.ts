// quiz-check-answer
// Modtager: { token, activity_id, answer }
// Returnerer: { is_correct, points, message }
// Bruger service-role key – kører KUN server-side.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL      = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { token, activity_id, answer } = await req.json();

    if (!token || !activity_id || answer === undefined) {
      return json({ error: 'Mangler token, activity_id eller answer' }, 400);
    }

    // Service-role klient – kan læse answer_keys
    const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      db: { schema: 'quiz' },
    });

    // 1. Find hold via token
    const { data: team, error: teamErr } = await sb
      .from('teams')
      .select('id, quiz_id')
      .eq('token', token)
      .single();

    if (teamErr || !team) {
      return json({ error: 'Ugyldigt hold-token' }, 403);
    }

    // 2. Tjek om holdet allerede har besvaret denne aktivitet
    const { data: existing } = await sb
      .from('submissions')
      .select('id, is_correct, points')
      .eq('team_id', team.id)
      .eq('activity_id', activity_id)
      .maybeSingle();

    if (existing) {
      return json({
        is_correct: existing.is_correct,
        points:     existing.points,
        message:    'Allerede besvaret',
        duplicate:  true,
      });
    }

    // 3. Hent aktivitet (tjek den tilhører quizzens stops)
    const { data: activity, error: actErr } = await sb
      .from('activities')
      .select('id, points, type, stops!inner(quiz_id)')
      .eq('id', activity_id)
      .eq('stops.quiz_id', team.quiz_id)
      .single();

    if (actErr || !activity) {
      return json({ error: 'Aktivitet ikke fundet i denne quiz' }, 404);
    }

    // 4. Hent fasit fra answer_keys (kun tilgængeligt via service role)
    const { data: key, error: keyErr } = await sb
      .from('answer_keys')
      .select('correct, tolerance')
      .eq('activity_id', activity_id)
      .maybeSingle();

    // Ingen fasit = aktiviteten godkendes automatisk (fx foto-opgaver)
    let is_correct = false;

    if (!key || keyErr) {
      // Ingen fasit defineret – marker som korrekt (manuel bedømmelse)
      is_correct = true;
    } else {
      // correct er jsonb: enten "streng", ["a","b"], eller tal
      const correctVal = key.correct;
      is_correct = checkAnswer(String(answer), correctVal, key.tolerance ?? null);
    }

    const points = is_correct ? (activity.points ?? 0) : 0;

    // 5. Gem submission
    const { error: subErr } = await sb.from('submissions').insert({
      team_id:     team.id,
      activity_id: activity_id,
      answer:      String(answer),
      is_correct,
      points,
    });

    if (subErr) {
      console.error('submissions insert fejl:', subErr);
      return json({ error: 'Kunne ikke gemme besvarelse' }, 500);
    }

    return json({
      is_correct,
      points,
      message: is_correct ? 'Korrekt!' : 'Forkert – prøv igen',
    });

  } catch (err) {
    console.error(err);
    return json({ error: 'Serverfejl' }, 500);
  }
});

// ── Svar-matching ─────────────────────────────────────────────
// correct er jsonb: "streng", ["svar1","svar2"] eller tal
function checkAnswer(
  given:     string,
  correct:   unknown,
  tolerance: number | null,
): boolean {
  const g = given.trim().toLowerCase();

  // Array: accepter hvis svaret matcher ét af elementerne
  if (Array.isArray(correct)) {
    return correct.some(v => g === String(v).trim().toLowerCase());
  }

  // Tal med tolerance
  if (typeof correct === 'number' || (typeof correct === 'string' && !isNaN(Number(correct)))) {
    const gn = parseFloat(g.replace(',', '.'));
    const cn = typeof correct === 'number' ? correct : parseFloat(String(correct));
    const tol = tolerance ?? 0;
    return !isNaN(gn) && !isNaN(cn) && Math.abs(gn - cn) <= tol;
  }

  // Streng: case-insensitiv exact match
  return g === String(correct).trim().toLowerCase();
}

// ── Hjælper ───────────────────────────────────────────────────
function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
