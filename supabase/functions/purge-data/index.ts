// purge-data   (supabase/functions/purge-data/index.ts)
// Sletter deltagerdata (hold, svar, positioner, oplåsninger OG fotos i Storage) – det database-delen alene ikke kan.
//
// To måder at kalde den på:
//  1) Dagligt job (GitHub Action / pg_cron):  header  x-purge-secret: <PURGE_SECRET>   body {}
//     → sletter alle løb hvis opbevaringstid er udløbet + rydder op i gamle logs/sessioner.
//  2) Manuelt fra en quizmaster/admin:         body { quiz_id, session_id, include_task_images? }
//     → sletter ét løbs deltagerdata med det samme (kræver at sessionen må styre løbet, og at løbet ikke kører).
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PURGE_SECRET

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PURGE_SECRET = Deno.env.get('PURGE_SECRET') ?? '';
const BUCKET       = 'quiz-uploads';
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CORS = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-purge-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

async function sha256(t: string) {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(t));
  return Array.from(new Uint8Array(b)).map(x => x.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });

  let body: { quiz_id?: string; session_id?: string; include_task_images?: boolean } = {};
  try { body = await req.json(); } catch (_) { /* tom body er ok til cron */ }

  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });
  const q = sb.schema('quiz');

  // Billede-filer i en mappe (flere sider), og fjern dem
  async function removeFolder(folder: string): Promise<number> {
    let removed = 0;
    for (;;) {
      const { data, error } = await sb.storage.from(BUCKET).list(folder, { limit: 100, offset: 0 });
      if (error) throw new Error('Kunne ikke liste ' + folder + ': ' + error.message);
      const files = (data ?? []).filter((o: { id: string | null }) => o.id !== null).map((o: { name: string }) => `${folder}/${o.name}`);
      if (!files.length) return removed;
      const { error: rmErr } = await sb.storage.from(BUCKET).remove(files);
      if (rmErr) throw new Error('Kunne ikke slette filer i ' + folder + ': ' + rmErr.message);
      removed += files.length;
    }
  }

  // Først filer, så rækker: fejler filsletningen, bliver rækkerne stående, og vi prøver igen næste gang
  async function purgeQuiz(quizId: string, includeTaskImages: boolean) {
    const { data: teams, error: tErr } = await q.rpc('get_quiz_team_ids', { p_quiz_id: quizId });
    if (tErr) throw new Error(tErr.message);
    let files = 0;
    for (const t of (teams ?? []) as { team_id: string }[]) files += await removeFolder(`answers/${t.team_id}`);
    if (includeTaskImages) files += await removeFolder(`task-images/${quizId}`);
    const { data, error } = await q.rpc('purge_quiz_participant_data', { p_quiz_id: quizId });
    if (error) throw new Error(error.message);
    return { quiz_id: quizId, files, ...(data as object) };
  }

  // ── 1) Dagligt job ──
  const given = req.headers.get('x-purge-secret') ?? '';
  if (PURGE_SECRET && given && (await sha256(given)) === (await sha256(PURGE_SECRET))) {
    const { data: due, error } = await q.rpc('get_purgeable_quizzes');
    if (error) return json({ error: error.message }, 500);
    const purged: unknown[] = [], failed: unknown[] = [];
    for (const row of (due ?? []) as { quiz_id: string }[]) {
      try { purged.push(await purgeQuiz(row.quiz_id, false)); }
      catch (e) { failed.push({ quiz_id: row.quiz_id, error: String((e as Error).message ?? e) }); }
    }
    const { data: house } = await q.rpc('cleanup_housekeeping');
    return json({ mode: 'cron', purged, failed, housekeeping: house ?? null }, failed.length ? 207 : 200);
  }

  // ── 2) Manuelt (quizmaster/admin) ──
  const { quiz_id, session_id, include_task_images } = body;
  if (!quiz_id || !session_id || !UUID_RE.test(quiz_id) || !UUID_RE.test(session_id)) {
    return json({ error: 'Mangler eller ugyldigt quiz_id/session_id' }, 400);
  }
  const { data: can } = await q.rpc('session_can_manage', { p_session_id: session_id, p_quiz_id: quiz_id });
  if (can !== true) return json({ error: 'Adgang nægtet' }, 403);

  const { data: quiz } = await q.from('quizzes').select('status').eq('id', quiz_id).maybeSingle();
  if (!quiz) return json({ error: 'Løb ikke fundet' }, 404);
  if (quiz.status === 'aktiv') return json({ error: 'Afslut løbet, før deltagerdata slettes' }, 409);

  try {
    return json({ mode: 'manual', ...(await purgeQuiz(quiz_id, include_task_images === true)) });
  } catch (e) {
    console.error(e);
    return json({ error: 'Sletningen fejlede: ' + String((e as Error).message ?? e) }, 500);
  }
});
