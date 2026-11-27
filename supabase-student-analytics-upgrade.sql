-- تحديث بيانات الملف الدراسي ولوحة متابعة الطلاب.
-- نفّذ هذا الملف مرة واحدة في Supabase > SQL Editor.
-- لا يقرأ هذا التحديث كلمات المرور ولا يضيف أعمدة لكلمات المرور.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS level text NOT NULL DEFAULT '';

-- استرجاع المستوى من بيانات التسجيل السابقة إن كان موجوداً.
UPDATE public.profiles AS p
SET level = COALESCE(NULLIF(u.raw_user_meta_data ->> 'level', ''), '')
FROM auth.users AS u
WHERE u.id = p.id
  AND COALESCE(p.level, '') = '';

-- حفظ البريد والمستوى عند إنشاء حساب طالب جديد.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, stream, level)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
    COALESCE(NEW.email, ''),
    COALESCE(NEW.raw_user_meta_data ->> 'stream', ''),
    COALESCE(NEW.raw_user_meta_data ->> 'level', '')
  )
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email;
  RETURN NEW;
END;
$$;

-- إبقاء البريد في الملف متزامناً عند تغييره من مزود المصادقة.
CREATE OR REPLACE FUNCTION public.sync_profile_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.profiles
  SET email = COALESCE(NEW.email, '')
  WHERE id = NEW.id
    AND email IS DISTINCT FROM COALESCE(NEW.email, '');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_email_updated ON auth.users;
CREATE TRIGGER on_auth_user_email_updated
AFTER UPDATE OF email ON auth.users
FOR EACH ROW
WHEN (OLD.email IS DISTINCT FROM NEW.email)
EXECUTE FUNCTION public.sync_profile_email();

-- Trigger-only function: never expose direct RPC execution to clients.
REVOKE ALL ON FUNCTION public.sync_profile_email() FROM PUBLIC, anon, authenticated;

-- يمنع المستخدم من تزوير بريد الحساب أو تغيير دوره من المتصفح.
CREATE OR REPLACE FUNCTION public.protect_profile_role()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = 'pg_catalog'
AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role AND current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Changing profile role is not allowed';
  END IF;
  IF NEW.email IS DISTINCT FROM OLD.email AND current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Changing profile email is not allowed';
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- يسمح للمسؤول وحده بقراءة سجلات تقدم جميع الطلاب.
-- يحتفظ كل طالب بصلاحية قراءة تقدمه الشخصي فقط عبر السياسة الموجودة.
ALTER TABLE public.lesson_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "lesson progress admin read all" ON public.lesson_progress;
CREATE POLICY "lesson progress admin read all"
  ON public.lesson_progress
  FOR SELECT
  TO authenticated
  USING ((SELECT public.is_admin()));

GRANT SELECT ON public.lesson_progress TO authenticated;

-- تفعيل Realtime حتى تتحدث لوحة المسؤول تلقائياً عند تسجيل طالب
-- أو تسجيل مراجعة درس أو نتيجة اختبار.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'profiles'
    ) THEN
      EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'lesson_progress'
    ) THEN
      EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.lesson_progress';
    END IF;
  END IF;
END;
$$;

COMMENT ON COLUMN public.profiles.level IS
  'Student academic level, for example: الأولى ثانوي، الثانية ثانوي، الثالثة ثانوي.';
