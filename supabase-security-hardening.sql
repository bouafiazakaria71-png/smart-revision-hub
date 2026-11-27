-- Supabase security hardening for the existing Ali Bin Abi Talib learning platform.
-- Run after supabase-schema.sql, supabase-lesson-quiz-upgrade.sql,
-- and supabase-student-analytics-upgrade.sql.
-- Admin access is denied by RLS until the signed-in administrator reaches aal2
-- after verifying a TOTP factor in the site admin portal.

BEGIN;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = (SELECT auth.uid())
      AND p.role = 'admin'
  )
  AND COALESCE((SELECT auth.jwt()) ->> 'aal', 'aal1') = 'aal2';
$$;
ALTER FUNCTION private.is_admin() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated;

DROP POLICY IF EXISTS "profiles read own or admin" ON public.profiles;
CREATE POLICY "profiles read own or admin"
  ON public.profiles FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = id OR (SELECT private.is_admin()));

DROP POLICY IF EXISTS "profiles update own or admin" ON public.profiles;
CREATE POLICY "profiles update own or admin"
  ON public.profiles FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = id OR (SELECT private.is_admin()))
  WITH CHECK ((SELECT auth.uid()) = id OR (SELECT private.is_admin()));

DROP POLICY IF EXISTS "resources admin insert" ON public.study_resources;
CREATE POLICY "resources admin insert"
  ON public.study_resources FOR INSERT TO authenticated
  WITH CHECK (created_by = (SELECT auth.uid()) AND (SELECT private.is_admin()));

DROP POLICY IF EXISTS "resources admin update" ON public.study_resources;
CREATE POLICY "resources admin update"
  ON public.study_resources FOR UPDATE TO authenticated
  USING ((SELECT private.is_admin()))
  WITH CHECK ((SELECT private.is_admin()));

DROP POLICY IF EXISTS "resources admin delete" ON public.study_resources;
CREATE POLICY "resources admin delete"
  ON public.study_resources FOR DELETE TO authenticated
  USING ((SELECT private.is_admin()));

DROP POLICY IF EXISTS "study questions admin insert" ON public.study_questions;
CREATE POLICY "study questions admin insert"
  ON public.study_questions FOR INSERT TO authenticated
  WITH CHECK (created_by = (SELECT auth.uid()) AND (SELECT private.is_admin()));

DROP POLICY IF EXISTS "study questions admin update" ON public.study_questions;
CREATE POLICY "study questions admin update"
  ON public.study_questions FOR UPDATE TO authenticated
  USING ((SELECT private.is_admin()))
  WITH CHECK ((SELECT private.is_admin()));

DROP POLICY IF EXISTS "study questions admin delete" ON public.study_questions;
CREATE POLICY "study questions admin delete"
  ON public.study_questions FOR DELETE TO authenticated
  USING ((SELECT private.is_admin()));

DROP POLICY IF EXISTS "lesson progress admin read all" ON public.lesson_progress;
DROP POLICY IF EXISTS "lesson progress read own" ON public.lesson_progress;
CREATE POLICY "lesson progress read own or admin"
  ON public.lesson_progress FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id OR (SELECT private.is_admin()));

DROP POLICY IF EXISTS "study pdf admin upload" ON storage.objects;
CREATE POLICY "study pdf admin upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'study-pdfs' AND (SELECT private.is_admin()));

DROP POLICY IF EXISTS "study pdf admin update" ON storage.objects;
CREATE POLICY "study pdf admin update"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'study-pdfs' AND (SELECT private.is_admin()))
  WITH CHECK (bucket_id = 'study-pdfs' AND (SELECT private.is_admin()));

DROP POLICY IF EXISTS "study pdf admin delete" ON storage.objects;
CREATE POLICY "study pdf admin delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'study-pdfs' AND (SELECT private.is_admin()));

DROP FUNCTION IF EXISTS public.is_admin();

ALTER TABLE public.ai_usage_daily ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ai_usage_daily FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE ON TABLE public.ai_usage_daily TO authenticated;

DROP POLICY IF EXISTS "AI usage read own" ON public.ai_usage_daily;
CREATE POLICY "AI usage read own"
  ON public.ai_usage_daily FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "AI usage insert own" ON public.ai_usage_daily;
CREATE POLICY "AI usage insert own"
  ON public.ai_usage_daily FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND usage_date = CURRENT_DATE
    AND request_count = 1
  );

DROP POLICY IF EXISTS "AI usage update own" ON public.ai_usage_daily;
CREATE POLICY "AI usage update own"
  ON public.ai_usage_daily FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = user_id AND usage_date = CURRENT_DATE)
  WITH CHECK ((SELECT auth.uid()) = user_id AND usage_date = CURRENT_DATE);

CREATE OR REPLACE FUNCTION public.guard_ai_usage_daily()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF current_user = 'postgres' THEN
    RETURN NEW;
  END IF;
  IF (SELECT auth.uid()) IS NULL OR NEW.user_id IS DISTINCT FROM (SELECT auth.uid()) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AI usage rows belong to the signed-in user';
  END IF;
  IF NEW.usage_date IS DISTINCT FROM CURRENT_DATE THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AI usage can only be recorded for the current day';
  END IF;
  IF TG_OP = 'INSERT' AND NEW.request_count <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AI usage counter must start at one';
  END IF;
  IF TG_OP = 'UPDATE' AND (
    NEW.user_id IS DISTINCT FROM OLD.user_id
    OR NEW.usage_date IS DISTINCT FROM OLD.usage_date
    OR NEW.request_count IS DISTINCT FROM OLD.request_count + 1
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'AI usage counter can only increase by one';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_ai_usage_daily() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS guard_ai_usage_daily_trigger ON public.ai_usage_daily;
CREATE TRIGGER guard_ai_usage_daily_trigger
BEFORE INSERT OR UPDATE ON public.ai_usage_daily
FOR EACH ROW EXECUTE FUNCTION public.guard_ai_usage_daily();

CREATE OR REPLACE FUNCTION public.consume_ai_request()
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  consumed integer;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Sign-in required';
  END IF;

  INSERT INTO public.ai_usage_daily (user_id, usage_date, request_count)
  VALUES ((SELECT auth.uid()), CURRENT_DATE, 1)
  ON CONFLICT (user_id, usage_date)
  DO UPDATE SET request_count = public.ai_usage_daily.request_count + 1
  WHERE public.ai_usage_daily.request_count < 25
  RETURNING request_count INTO consumed;

  RETURN COALESCE(consumed, 0);
END;
$$;
REVOKE ALL ON FUNCTION public.consume_ai_request() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_ai_request() TO authenticated;

COMMIT;
