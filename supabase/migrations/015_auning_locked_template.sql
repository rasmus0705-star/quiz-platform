-- 015_auning_template.sql
-- Fast, låst Auning-skabelon.
-- Kør efter 004, 013 og 014. Skabelonen kopieres til kundens eget løb via copy_template.

ALTER TABLE quiz.quizzes
  ADD COLUMN IF NOT EXISTS template_locked boolean NOT NULL DEFAULT false;

ALTER TABLE quiz.teams
  ADD COLUMN IF NOT EXISTS route_order jsonb;

-- Låste masterskabeloner kan ikke ændres fra admin-/kunde-UI.
CREATE OR REPLACE FUNCTION quiz.guard_quiz_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF current_setting('quiz.bypass_guard', true) = '1' THEN RETURN NEW; END IF;
  IF session_user IN ('postgres', 'supabase_admin') THEN RETURN NEW; END IF;
  IF OLD.template_locked AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'Denne faste skabelon er låst og kan ikke ændres';
  END IF;
  IF quiz.check_session_is_admin() OR auth.role() IN ('authenticated', 'service_role') THEN
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status
  OR NEW.customer_id IS DISTINCT FROM OLD.customer_id
  OR NEW.owner_id IS DISTINCT FROM OLD.owner_id
  OR NEW.round_no IS DISTINCT FROM OLD.round_no
  OR NEW.paid_at IS DISTINCT FROM OLD.paid_at
  OR NEW.delete_after IS DISTINCT FROM OLD.delete_after THEN
    RAISE EXCEPTION 'Ikke tilladt: status, kunde og betaling kan kun ændres af systemet/admin';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_guard_quiz_update ON quiz.quizzes;
CREATE TRIGGER trg_guard_quiz_update
  BEFORE UPDATE ON quiz.quizzes
  FOR EACH ROW EXECUTE FUNCTION quiz.guard_quiz_update();

CREATE OR REPLACE FUNCTION quiz.block_locked_template_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF OLD.template_locked
     AND COALESCE(current_setting('quiz.bypass_guard', true), '') <> '1'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Denne faste skabelon er låst og kan ikke slettes';
  END IF;
  RETURN OLD;
END $$;

DROP TRIGGER IF EXISTS trg_block_locked_template_delete ON quiz.quizzes;
CREATE TRIGGER trg_block_locked_template_delete
  BEFORE DELETE ON quiz.quizzes
  FOR EACH ROW EXECUTE FUNCTION quiz.block_locked_template_delete();

CREATE OR REPLACE FUNCTION quiz.block_locked_template_child()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_quiz uuid;
BEGIN
  IF COALESCE(current_setting('quiz.bypass_guard', true), '') = '1'
     OR session_user IN ('postgres', 'supabase_admin') THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;
  IF TG_TABLE_NAME = 'stops' THEN
    v_quiz := COALESCE(NEW.quiz_id, OLD.quiz_id);
  ELSIF TG_TABLE_NAME = 'activities' THEN
    SELECT quiz_id INTO v_quiz FROM quiz.stops WHERE id = COALESCE(NEW.stop_id, OLD.stop_id);
  ELSE
    SELECT s.quiz_id INTO v_quiz
      FROM quiz.activities a JOIN quiz.stops s ON s.id = a.stop_id
     WHERE a.id = COALESCE(NEW.activity_id, OLD.activity_id);
  END IF;
  IF EXISTS (SELECT 1 FROM quiz.quizzes WHERE id = v_quiz AND template_locked) THEN
    RAISE EXCEPTION 'Denne faste skabelon er låst og kan ikke ændres';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;

DROP TRIGGER IF EXISTS trg_block_locked_template_stops ON quiz.stops;
CREATE TRIGGER trg_block_locked_template_stops
  BEFORE INSERT OR UPDATE OR DELETE ON quiz.stops
  FOR EACH ROW EXECUTE FUNCTION quiz.block_locked_template_child();
DROP TRIGGER IF EXISTS trg_block_locked_template_activities ON quiz.activities;
CREATE TRIGGER trg_block_locked_template_activities
  BEFORE INSERT OR UPDATE OR DELETE ON quiz.activities
  FOR EACH ROW EXECUTE FUNCTION quiz.block_locked_template_child();
DROP TRIGGER IF EXISTS trg_block_locked_template_answer_keys ON quiz.answer_keys;
CREATE TRIGGER trg_block_locked_template_answer_keys
  BEFORE INSERT OR UPDATE OR DELETE ON quiz.answer_keys
  FOR EACH ROW EXECUTE FUNCTION quiz.block_locked_template_child();

-- Hold kan senere få en særskilt rækkefølge i route_order. Tom/null betyder quizzens normale rækkefølge.
DROP FUNCTION IF EXISTS quiz.get_quiz_stops(text);
CREATE FUNCTION quiz.get_quiz_stops(p_token text)
RETURNS TABLE(stop_id uuid, stop_name text, sort int, lat double precision, lng double precision,
              radius_m int, activity_id uuid, activity_type text, activity_question text,
              activity_media_url text, activity_options jsonb, activity_points int,
              activity_approval text, quiz_mode text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = quiz, public AS $$
  WITH me AS (
    SELECT t.id AS team_id, t.quiz_id, q.stop_order, q.round_no, t.route_order
      FROM quiz.teams t JOIN quiz.quizzes q ON q.id = t.quiz_id
     WHERE t.token = p_token
       AND (q.status IN ('testing','aktiv') OR t.name = '🧪 Testhold')
  ),
  base AS (
    SELECT s.id, s.name, s.lat, s.lng, s.radius_m, s.sort, s.created_at,
           me.team_id, me.stop_order, me.round_no,
           COALESCE(me.route_order, '[]'::jsonb) AS route_order
      FROM quiz.stops s CROSS JOIN me
     WHERE s.quiz_id = me.quiz_id
  ),
  ordered AS (
    SELECT b.*,
           (ROW_NUMBER() OVER (
             ORDER BY
               CASE WHEN jsonb_array_length(b.route_order) > 0
                    THEN COALESCE((SELECT (r.ordinality - 1)::int
                                     FROM jsonb_array_elements_text(b.route_order) WITH ORDINALITY r(value, ordinality)
                                    WHERE r.value = b.id::text), 100000 + b.sort)
                    ELSE b.sort
               END,
               b.created_at, b.id
           ) - 1)::int AS ord
      FROM base b
  ),
  state AS (
    SELECT o.ord,
           NOT EXISTS (
             SELECT 1 FROM quiz.activities a
              WHERE a.stop_id = o.id
                AND NOT EXISTS (SELECT 1 FROM quiz.submissions sub
                                 WHERE sub.activity_id = a.id
                                   AND sub.team_id = o.team_id
                                   AND sub.round_no = o.round_no)
           ) AS done
      FROM ordered o
  ),
  cutoff AS (
    SELECT COALESCE(MIN(ord) FILTER (WHERE NOT done), 2147483647) AS first_open FROM state
  )
  SELECT o.id, o.name, o.ord, o.lat, o.lng, o.radius_m,
         a.id, a.type, a.question, a.media_url, a.options, a.points, a.approval,
         o.stop_order
    FROM ordered o
    LEFT JOIN quiz.activities a ON a.stop_id = o.id
   WHERE o.stop_order <> 'laast' OR o.ord <= (SELECT first_open FROM cutoff)
   ORDER BY o.ord, a.sort NULLS LAST, a.id;
$$;

GRANT EXECUTE ON FUNCTION quiz.get_quiz_stops(text) TO anon, authenticated;

-- Importér indholdet fra Rom-sniffer/auning som én låst master.
DO $$
DECLARE
  v_quiz uuid := '7d0f1d4a-6f7b-4b95-9d7f-8f0a00000001';
  v_locations jsonb := $auning$[{"id":1,"type":"quiz","name":"Skydebanen i Auning","desc":"Skydebanen lå i Porsbakkerne, hvor jægere og skytter mødtes i årtier. Det var et af byens sociale samlingspunkter, hvor der blev dyrket mere end bare skydning.","lat":56.43402321419301,"lng":10.387257014578266,"images":[],"year":"1939","headline":"JAGTFORENING STIFTET MED 14 MAND!","newsSub":"Nye tider for byens jægere","questions":[{"q":"Hvornår blev Auning Jagtforening stiftet?","opts":["A) 5. april 1929","B) 5. april 1939","C) 5. april 1949"],"correct":1},{"q":"Sammen med hvem købte jagtforeningen i 1946 et areal til skydebaner?","opts":["A) Auning Idrætsforening","B) Auning Skytteforening","C) Hjemmeværnet"],"correct":1},{"q":"Hvad var jagtforeningens indtægtskilde i 1960'erne og frem til 1976?","opts":["A) Tombola på markedsdage","B) Kroballer på Auning Kro","C) Loppemarkeder i idrætshallen"],"correct":1}]},{"id":9,"type":"quiz","name":"Pølsevognskrigen i Auning","desc":"I 1992 blussede en bitter strid op om Aunings populære pølsevogn. Familien bag vognen — herunder sønnen Mogens — var velkendt i byen. Historien endte langt fra Auning.","lat":56.43330381777415,"lng":10.382110632311788,"images":[{"src":"img/poelse.jpg","caption":"Aunings pølsevogn er tilbage igen"}],"year":"1992","headline":"PØLSEKRIG I AUNING!","newsSub":"Strid om byens pølsevogn trækker overskrifter","questions":[{"q":"Hvorfor opstod der i 1992 konflikt omkring pølsevognen i Auning?","opts":["A) Bente Hansen nægtede at sælge pølser","B) Kommunen forbød salg af Cocio","C) Handelsudvalget ville drive pølsevognen uden at betale leje","D) Auning Cafeteria ville købe pølsevognen"],"correct":2},{"q":"Mogens voksede op i pølsevognsfamilien og fik et kaldenavn i ungdomskredse. Hvad blev han kaldt?","opts":["A) Mogens Remoulade","B) Mogens Pølsekonge","C) Mogens Grillkongen","D) Mogens Pølsemester"],"correct":1},{"q":"Hvorfor måtte pølsevognen, efter den var flyttet til Assentoft, til sidst lukke?","opts":["A) Der var ikke længere kunder nok","B) Kommunen krævede den flyttet igen","C) Ejeren solgte den til en anden pølsemand","D) En tandlæge fik friturerøg ind gennem sin udluftning"],"correct":3}]},{"id":2,"type":"quiz","name":"Det gamle Hospital (Kirkeladen)","desc":"Den gamle bygning ved kirken har haft mange funktioner gennem historien. Den har tjent både kirke og byens borgere, og rummer flere overraskelser end man tror.","lat":56.43337348622735,"lng":10.377203982134889,"images":[{"src":"img/hospital.jpg","caption":"Kirkeladen — det gamle hospital"}],"year":"Ca. 1700","headline":"FATTIGE FÅR NØGLEN TIL KIRKELADEN","newsSub":"Godshospitalet åbner sine døre","questions":[{"q":"Hvad var bygningen oprindeligt, før den blev hospital?","opts":["A) Et bryggeri","B) En kirkelade til tiendekorn","C) Et vagthus"],"correct":1},{"q":"Hvem lod huset indrette som \"godshospital\" for fattige?","opts":["A) Jørgen Skeel","B) Christen Scheel","C) Frederik VII"],"correct":0},{"q":"Hvor mange år fungerede huset som hjem for \"ærlige fattige\"?","opts":["A) Ca. 100 år","B) Ca. 200 år","C) Ca. 300 år"],"correct":2}]},{"id":3,"type":"quiz","name":"Den grafiske industri","desc":"Her lå bl.a. Auning Bogtrykkeri. Auning var hjemsted for flere grafiske virksomheder, der satte deres præg på byen. Tryksværten flød rigeligt, og branchen tiltrak sig opmærksomhed udefra.","lat":56.42982255964975,"lng":10.374707009106126,"images":[{"src":"img/bogbinder.jpg","caption":"Den grafiske industri i Auning"}],"year":"1986","headline":"NY GRAFISK GIGANT SER DAGENS LYS!","newsSub":"Datagraf slår dørene op i Auning","questions":[{"q":"Hvilket år blev Datagraf grundlagt?","opts":["A) 1976","B) 1986","C) 1996"],"correct":1},{"q":"Hvem besøgte Datagraf ved kongeparrets besøg i 2011?","opts":["A) Dronning Margrethe","B) Kronprins Frederik","C) Prins Henrik"],"correct":0},{"q":"Hvilken af disse var IKKE en grafisk virksomhed i Auning?","opts":["A) Djurs Tryk","B) Grafisk ID","C) Auning Finérværk"],"correct":2}]},{"id":4,"type":"quiz","name":"Kartoffelmelsfabrikken","desc":"Kartoffelmelsfabrikken var en af byens store arbejdspladser og et vigtigt samlingspunkt. Fabrikken satte bogstaveligt talt rytmen for hverdagen i Auning.","lat":56.42735629518248,"lng":10.376317870053443,"images":[{"src":"img/kartoffelmel.jpg","caption":"Kartoffelmelsfabrikken"}],"year":"1916","headline":"DAMPFLØJTEN KALDER TIL FROKOST!","newsSub":"Hele byen retter sig efter fabrikken","questions":[{"q":"Hvilket år stammer fabriksbygningen fra?","opts":["A) 1901","B) 1916","C) 1930"],"correct":1},{"q":"Hvad bruges den tidligere kartoffelmelsfabrik til i dag?","opts":["A) Byggemarked","B) Magasiner for Landbrugsmuseet","C) Boliger"],"correct":1},{"q":"Sammen med hvilke to andre fabrikker markerede dampfløjten frokostpausen kl. 12?","opts":["A) Savværket og Madratsfabrikken","B) Mejeriet og Skaftefabrikken","C) Trædrejeriet og Finérværket"],"correct":0}]},{"id":5,"type":"quiz","name":"Auning Savværk","desc":"Savværket var en central virksomhed i Auning, der forarbejdede tømmer fra de omkringliggende skove. Det var tæt forbundet med godset og egnen.","lat":56.427439813850306,"lng":10.378394535114554,"images":[{"src":"img/savvaerk1.jpg","caption":"A/S Auning Savværk"},{"src":"img/Savvaerk.jpg","caption":"Savværket"}],"year":"1901","headline":"GREVENS SAVVÆRK ÅBNER!","newsSub":"Tømmer fra Løvenholmskovene forarbejdes i Auning","questions":[{"q":"Hvem etablerede savværket i 1901?","opts":["A) Greve Jørgen Carl Scheel","B) Købmand F.C. Gerstrøm","C) Niels Chr. Jensen"],"correct":0},{"q":"Hvor mange medarbejdere havde savværket ved 50-års jubilæet i 1980?","opts":["A) 18","B) 30","C) 44"],"correct":2},{"q":"Hvornår lukkede savværket endeligt?","opts":["A) 1980","B) 1990","C) 2000"],"correct":1}]},{"id":6,"type":"quiz","name":"Auning Station","desc":"Stationen forvandlede Auning fra landsby til stationsby. Området omkring perronerne blev kaldt \"Ny Auning\", og handelslivet blomstrede.","lat":56.42925284166479,"lng":10.37794075687635,"images":[{"src":"img/Station.jpg","caption":"Auning Station"}],"year":"1876","headline":"TOGET ER ANKOMMET TIL AUNING!","newsSub":"Banen mellem Randers og Grenaa indvies","questions":[{"q":"Hvilket år fik Auning en station på banen mellem Randers og Grenaa?","opts":["A) 1864","B) 1876","C) 1901"],"correct":1},{"q":"Hvilken arkitekt tegnede stationsbygningen?","opts":["A) Heinrich Wenck","B) Kaare Klint","C) Ivar Bentsen"],"correct":0},{"q":"Hvornår lukkede banen for godstransport?","opts":["A) 1971","B) 1985","C) 1992"],"correct":2}]},{"id":10,"type":"quiz","name":"Auning Andelsmejeri","desc":"Auning Andelsmejeri var mere end bare mælk — borgerne nød godt af mange af stedets tilbud, og det var et vigtigt omdrejningspunkt i byens liv.","lat":56.42992486084601,"lng":10.379351232858621,"images":[{"src":"img/mejeri.jpg","caption":"Auning Andelsmejeri har sidste arbejdsdag"},{"src":"img/mejeri1.jpg","caption":"Mejeribygningen"}],"year":"1904","headline":"BADEANSTALT ÅBNER PÅ MEJERIET!","newsSub":"Aunings borgere kan nu bade varmt","questions":[{"q":"Hvad blev der oprettet på Auning Mejeri i 1904 efter ønske fra byens beboere?","opts":["A) En biograf","B) En badeanstalt","C) Et bibliotek","D) En frisørsalon"],"correct":1},{"q":"Hvad producerede Auning Mejeri IKKE?","opts":["A) Smør","B) Kærnemælk","C) Flødeis","D) Ost"],"correct":3},{"q":"Hvad kostede en almindelig vaniljeispind fra Auning Mejeri?","opts":["A) 5 øre","B) 10 øre","C) 15 øre","D) 25 øre"],"correct":1}]},{"id":11,"type":"quiz","name":"Det gamle Cementstøberi","desc":"Her lå tidligere et cementstøberi, som var en del af Aunings industri. Stedet har en bevæget historie, ikke mindst under besættelsen. I dag ser området helt anderledes ud.","lat":56.43133477664162,"lng":10.380115573164742,"images":[{"src":"img/cement.jpg","caption":"Det gamle cementstøberi i Auning"}],"year":"1944","headline":"SABOTAGE PÅ CEMENTSTØBERIET!","newsSub":"Dramatiske begivenheder under besættelsen","questions":[{"q":"Hvilket år blev det gamle cementstøberi revet ned?","opts":["A) 1984","B) 1994","C) 2004","D) 2014"],"correct":2},{"q":"Hvad skete der på cementstøberiet under besættelsen?","opts":["A) Tyskerne overtog fabrikken","B) Produktionen blev lukket","C) Der blev gennemført en sabotageaktion","D) Fabrikken blev brugt som våbenlager"],"correct":2},{"q":"Hvor mange boliger blev opført på området efter cementstøberiets tid?","opts":["A) 15","B) 16","C) 17","D) 18"],"correct":2}]},{"id":7,"type":"quiz","name":"Auning Minigolfbane","desc":"For enden af Dyrbyvej lå Aunings minigolfbane, hvor familier mødtes til hyggelige kampe. Det var et populært udflugtsmål på varme sommerdage.","lat":56.43024704048354,"lng":10.387024524821289,"images":[],"year":"1973","headline":"18 HULLER KLAR TIL AUNINGS BORGERE!","newsSub":"Minigolfbanen ved Dyrbyvej slår portene op","questions":[{"q":"Hvilket år åbnede minigolfbanen i Auning?","opts":["A) 1963","B) 1973","C) 1983","D) 1993"],"correct":1},{"q":"Hvor mange baner skulle man igennem for en komplet runde?","opts":["A) 9","B) 12","C) 18","D) 27"],"correct":2},{"q":"Hvor endte bolden på sidste hul?","opts":["A) Den trillede tilbage til første hul","B) Den røg ned i en rist","C) Den landede i en vandbeholder","D) Den endte i en spand inde i kiosken"],"correct":3}]}]$$auning$::jsonb;
  v_loc jsonb;
  v_q jsonb;
  v_stop uuid;
  v_act uuid;
  v_i int;
  v_sort int;
  v_opts text[];
  v_media text;
BEGIN
  PERFORM set_config('quiz.bypass_guard', '1', true);
  INSERT INTO quiz.quizzes
    (id, title, description, status, stop_order, mode, theme, hide_results,
     is_template, template_tag, template_locked)
  VALUES
    (v_quiz,
     'Auning – historisk videnstur',
     'En historisk tur gennem Auning med fortællinger og spørgsmål om byens steder. Kan bruges som ren videnstur eller med point og konkurrence.',
     'kladde', 'laast', 'gps', 'historie', true,
     true, 'Auning', true)
  ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title,
    description = EXCLUDED.description,
    stop_order = EXCLUDED.stop_order,
    mode = EXCLUDED.mode,
    theme = EXCLUDED.theme,
    hide_results = EXCLUDED.hide_results,
    is_template = true,
    template_tag = 'Auning',
    template_locked = true;

  DELETE FROM quiz.stops WHERE quiz_id = v_quiz;

  FOR v_loc, v_i IN
    SELECT value, (ordinality - 1)::int
      FROM jsonb_array_elements(v_locations) WITH ORDINALITY
  LOOP
    v_stop := ('00000000-0000-4000-8000-' || lpad((1000000000 + v_i)::text, 12, '0'))::uuid;
    v_media := NULL;
    IF jsonb_array_length(v_loc->'images') > 0 THEN
      v_media := '../assets/auning/' || regexp_replace(v_loc->'images'->0->>'src', '^.*/', '');
    END IF;

    INSERT INTO quiz.stops (id, quiz_id, name, lat, lng, radius_m, sort)
    VALUES (v_stop, v_quiz, v_loc->>'name',
            (v_loc->>'lat')::double precision, (v_loc->>'lng')::double precision, 15, v_i);

    INSERT INTO quiz.activities (stop_id, sort, type, question, options, points, media_url)
    VALUES (v_stop, 0, 'info',
            (v_loc->>'desc') || E'\n\nHistorisk periode: ' || COALESCE(v_loc->>'year', ''),
            NULL, 0, v_media);

    v_sort := 1;
    FOR v_q IN SELECT value FROM jsonb_array_elements(v_loc->'questions')
    LOOP
      v_act := ('00000000-0000-4000-9000-' || lpad((2000000000 + v_i * 100 + v_sort)::text, 12, '0'))::uuid;
      v_opts := ARRAY(SELECT regexp_replace(value, '^[A-D]\)\s*', '') FROM jsonb_array_elements_text(v_q->'opts'));
      INSERT INTO quiz.activities (id, stop_id, sort, type, question, options, points, approval)
      VALUES (v_act, v_stop, v_sort, 'mc', v_q->>'q', to_jsonb(v_opts), 10, 'auto');
      INSERT INTO quiz.answer_keys (activity_id, correct, tolerance)
      VALUES (v_act, to_jsonb(v_opts[(v_q->>'correct')::int + 1]), NULL);
      v_sort := v_sort + 1;
    END LOOP;
  END LOOP;
  PERFORM set_config('quiz.bypass_guard', '0', true);
END $$;

-- Faste master-skabeloner må ikke kunne kopieres som endnu en master.
CREATE OR REPLACE FUNCTION quiz.set_template(p_quiz_id uuid, p_is boolean, p_tag text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
BEGIN
  IF NOT (quiz.check_session_is_admin() OR auth.role() = 'authenticated') THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  IF EXISTS (SELECT 1 FROM quiz.quizzes WHERE id = p_quiz_id AND template_locked) AND NOT p_is THEN
    RAISE EXCEPTION 'Den faste skabelon kan ikke fjernes fra skabelonlisten';
  END IF;
  IF p_tag IS NOT NULL AND p_tag !~ '^.{0,40}$' THEN
    RAISE EXCEPTION 'Mærkat er for langt';
  END IF;
  PERFORM set_config('quiz.bypass_guard', '1', true);
  UPDATE quiz.quizzes SET is_template = p_is, template_tag = nullif(btrim(coalesce(p_tag, '')), '') WHERE id = p_quiz_id;
  PERFORM set_config('quiz.bypass_guard', '0', true);
END $$;

