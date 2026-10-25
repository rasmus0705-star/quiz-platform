// quiz-check-answer   (supabase/functions/quiz-check-answer/index.ts)
// Modtager: { token, activity_id, answer }
// Returnerer: { is_correct, points, status, message }
//   status: 'ok' | 'pending' (foto der afventer godkendelse)
// Kører med service role - fasit (answer_keys) forlader aldrig serveren.
//
// Regler der håndhæves HER (ikke i browseren):
//   - løbet skal være aktivt (eller holdet er et testhold)
//   - ét svar pr. opgave pr. runde
//   - i LÅST rækkefølge skal tidligere stop være besvaret
//   - foto skal være uploadet til holdets egen mappe i vores bucket
//   - foto-opgaver følger 'approval' (auto / manuel / vis_kun)
//   - info-opgaver giver aldrig point

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TEST_TEAM        = '🧪 Testhold';

const corsHeaders = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { token, activity_id, answer } = await req.json();
    if (!token || !activity_id || answer === undefined || answer === null) {
      return json({ error: 'Mangler token, activity_id eller answer' }, 400);
    }
    const given = String(answer);
    if (given.length > 2000) return json({ error: 'Svaret er for langt' }, 400);

    const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      db: { schema: 'quiz' },
      auth: { persistSession: false },
    });

    // 1. Hold + quiz
    const { data: team } = await sb.from('teams')
      .select('id, name, quiz_id').eq('token', token).maybeSingle();
    if (!team) return json({ error: 'Ugyldigt hold-token' }, 403);

    const { data: quiz } = await sb.from('quizzes')
      .select('status, round_no, stop_order').eq('id', team.quiz_id).single();
    const isTest = team.name === TEST_TEAM;
    if (!quiz || !(quiz.status === 'aktiv' || quiz.status === 'testing' || isTest)) {
      return json({ error: 'Løbet er ikke aktivt' }, 403);
    }
    const round = quiz.round_no ?? 1;

    // 2. Aktiviteten skal høre til holdets quiz
    const { data: activity } = await sb.from('activities')
      .select('id, points, type, approval, stop_id, stops!inner(quiz_id)')
      .eq('id', activity_id).eq('stops.quiz_id', team.quiz_id).maybeSingle();
    if (!activity) return json({ error: 'Opgaven findes ikke i dette løb' }, 404);

    // 3. Allerede besvaret i denne runde?
    const existing = await findExisting(sb, team.id, activity_id, round);
    if (existing) return json({ ...existing, message: 'Allerede besvaret', duplicate: true });

    // 4. Låst rækkefølge: alle tidligere stop skal være færdige
    if (quiz.stop_order === 'laast') {
      const { data: stopRows } = await sb.from('stops')
        .select('id').eq('quiz_id', team.quiz_id)
        .order('sort').order('created_at').order('id');
      const ids = (stopRows ?? []).map((s: { id: string }) => s.id);
      const idx = ids.indexOf(activity.stop_id);
      if (idx > 0) {
        const { data: acts } = await sb.from('activities')
          .select('id').in('stop_id', ids.slice(0, idx));
        const actIds = (acts ?? []).map((a: { id: string }) => a.id);
        if (actIds.length) {
          const { data: done } = await sb.from('submissions')
            .select('activity_id').eq('team_id', team.id).eq('round_no', round)
            .in('activity_id', actIds);
          if ((done?.length ?? 0) < actIds.length) {
            return json({ error: 'Dette stop er endnu ikke låst op' }, 403);
          }
        }
      }
    }

    // 5. Bedøm svaret
    const base = activity.points ?? 0;
    let isCorrect = false;
    let points = 0;
    let status: 'ok' | 'pending' = 'ok';

    if (activity.type === 'info') {
      isCorrect = true;                      // blot "læst"
      points = 0;
    } else if (activity.type === 'foto') {
      const prefix = `${SUPABASE_URL}/storage/v1/object/public/quiz-uploads/answers/${team.id}/`;
      if (!given.startsWith(prefix)) {
        return json({ error: 'Billedet blev ikke uploadet korrekt - prøv igen' }, 400);
      }
      const approval = activity.approval ?? 'auto';
      if (approval === 'manuel')       { status = 'pending'; isCorrect = false; points = 0; }
      else if (approval === 'vis_kun') { isCorrect = true;   points = 0; }
      else                             { isCorrect = true;   points = base; }
    } else {
      const { data: key } = await sb.from('answer_keys')
        .select('correct, tolerance').eq('activity_id', activity_id).maybeSingle();
      if (!key) {
        console.error('Opgave uden fasit:', activity_id);   // set_quiz_status forhindrer det ved aktivering
        isCorrect = false;
      } else {
        isCorrect = checkAnswer(given, key.correct, key.tolerance ?? null);
      }
      points = isCorrect ? base : 0;
    }

    // 6. Gem (unik pr. hold/opgave/runde - dobbeltklik giver dublet-svar)
    const { error: subErr } = await sb.from('submissions').insert({
      team_id: team.id, activity_id, answer: given,
      is_correct: isCorrect, points, status, round_no: round,
    });
    if (subErr) {
      if (subErr.code === '23505') {
        const dup = await findExisting(sb, team.id, activity_id, round);
        if (dup) return json({ ...dup, message: 'Allerede besvaret', duplicate: true });
      }
      console.error('submissions insert fejl:', subErr);
      return json({ error: 'Kunne ikke gemme besvarelse' }, 500);
    }

    return json({
      is_correct: isCorrect, points, status,
      message: status === 'pending' ? 'Afventer godkendelse'
             : isCorrect ? 'Korrekt!' : 'Forkert svar',
    });

  } catch (err) {
    console.error(err);
    return json({ error: 'Serverfejl' }, 500);
  }
});

// deno-lint-ignore no-explicit-any
async function findExisting(sb: any, teamId: string, activityId: string, round: number) {
  const { data } = await sb.from('submissions')
    .select('is_correct, points, status')
    .eq('team_id', teamId).eq('activity_id', activityId).eq('round_no', round)
    .maybeSingle();
  return data ?? null;
}

// correct er jsonb: "streng", ["svar1","svar2"] eller tal
function checkAnswer(given: string, correct: unknown, tolerance: number | null): boolean {
  const g = given.trim().toLowerCase();

  if (Array.isArray(correct)) {
    return correct.some(v => g === String(v).trim().toLowerCase());
  }

  const isNumeric = typeof correct === 'number' ||
    (typeof correct === 'string' && correct.trim() !== '' && !isNaN(Number(correct.replace(',', '.'))));
  if (isNumeric) {
    const gn  = parseFloat(g.replace(',', '.'));
    const cn  = typeof correct === 'number' ? correct : parseFloat(String(correct).replace(',', '.'));
    const tol = tolerance ?? 0;
    return !isNaN(gn) && !isNaN(cn) && Math.abs(gn - cn) <= tol;
  }

  return g === String(correct).trim().toLowerCase();
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
