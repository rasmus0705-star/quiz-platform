-- 013_private_orders_and_admin_error_fix.sql
-- Gør bestillinger mulige for privatpersoner og gentager sikkerhedsrettelsen
-- fra 012 som en ny migration, så den også rammer en allerede oprettet database.

ALTER TABLE quiz.orders
  ALTER COLUMN org_name DROP NOT NULL;

CREATE OR REPLACE FUNCTION quiz.submit_order(
  p_org text, p_name text, p_email text, p_phone text, p_event_type text,
  p_expected date, p_message text, p_consent boolean, p_website text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_mail text := lower(btrim(coalesce(p_email, '')));
BEGIN
  IF coalesce(btrim(p_website), '') <> '' THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  IF p_consent IS NOT TRUE THEN
    RAISE EXCEPTION 'Du skal acceptere behandlingen af dine oplysninger';
  END IF;
  IF length(btrim(coalesce(p_org, ''))) > 120 THEN
    RAISE EXCEPTION 'Navnet på virksomheden eller foreningen er for langt';
  END IF;
  IF length(btrim(coalesce(p_name, ''))) < 2 OR length(p_name) > 120 THEN
    RAISE EXCEPTION 'Skriv dit navn';
  END IF;
  IF v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' OR length(v_mail) > 200 THEN
    RAISE EXCEPTION 'Skriv en gyldig e-mailadresse';
  END IF;
  IF length(coalesce(p_message, '')) > 2000 OR length(coalesce(p_phone, '')) > 40
     OR length(coalesce(p_event_type, '')) > 80 THEN
    RAISE EXCEPTION 'En af teksterne er for lang';
  END IF;
  IF (SELECT count(*) FROM quiz.orders WHERE lower(email) = v_mail
      AND created_at > now() - interval '24 hours') >= 3 THEN
    RAISE EXCEPTION 'Du har allerede sendt flere bestillinger i dag – vi vender tilbage hurtigst muligt';
  END IF;
  IF (SELECT count(*) FROM quiz.orders WHERE created_at > now() - interval '1 hour') >= 30 THEN
    RAISE EXCEPTION 'Der er travlt lige nu – prøv igen om lidt';
  END IF;
  INSERT INTO quiz.orders (org_name, contact_name, email, phone, event_type, expected_date, message, consent_at)
  VALUES (nullif(btrim(p_org), ''), btrim(p_name), v_mail,
          nullif(btrim(p_phone), ''), nullif(btrim(p_event_type), ''), p_expected,
          nullif(btrim(p_message), ''), now());
  RETURN jsonb_build_object('ok', true);
END $$;

-- Samme regel som i 012: authenticated alene giver ikke admin-adgang.
CREATE OR REPLACE FUNCTION quiz.admin_clear_errors()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = quiz, public AS $$
DECLARE v_deleted integer := 0;
BEGIN
  IF NOT quiz.check_session_is_admin() THEN
    RAISE EXCEPTION 'Adgang nægtet';
  END IF;
  DELETE FROM quiz.errors WHERE true;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END $$;

REVOKE ALL ON FUNCTION quiz.admin_clear_errors() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION quiz.admin_clear_errors() TO anon, authenticated;
