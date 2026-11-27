-- بنك الأسئلة المستقل وتقدم الطالب لكل درس
-- آمن لإعادة التنفيذ: ينشئ الجداول والفهارس عند غيابها ويعيد ضبط السياسات المسماة فقط.

begin;

create table if not exists public.study_questions (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.study_resources(id) on delete cascade,
  question text not null check (char_length(question) between 1 and 700),
  options jsonb not null,
  correct_answer integer not null,
  explanation text not null default '',
  sort_order integer not null default 0,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint study_questions_options_valid check (
    case
      when jsonb_typeof(options) = 'array' then
        jsonb_array_length(options) between 2 and 4
        and correct_answer >= 0
        and correct_answer < jsonb_array_length(options)
      else false
    end
  )
);

create index if not exists study_questions_resource_order_idx
  on public.study_questions(resource_id, sort_order, created_at);
create index if not exists study_questions_created_by_idx
  on public.study_questions(created_by);

alter table public.study_questions enable row level security;
grant select on table public.study_questions to anon, authenticated;
grant insert, update, delete on table public.study_questions to authenticated;

drop policy if exists "study questions public read" on public.study_questions;
create policy "study questions public read"
  on public.study_questions for select to anon, authenticated
  using (true);

drop policy if exists "study questions admin insert" on public.study_questions;
create policy "study questions admin insert"
  on public.study_questions for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and (select public.is_admin())
  );

drop policy if exists "study questions admin update" on public.study_questions;
create policy "study questions admin update"
  on public.study_questions for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists "study questions admin delete" on public.study_questions;
create policy "study questions admin delete"
  on public.study_questions for delete to authenticated
  using ((select public.is_admin()));

create table if not exists public.lesson_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  resource_id uuid not null references public.study_resources(id) on delete cascade,
  reviewed_at timestamptz not null default now(),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_score integer check (last_score between 0 and 100),
  best_score integer check (best_score between 0 and 100),
  updated_at timestamptz not null default now(),
  primary key (user_id, resource_id)
);

create index if not exists lesson_progress_resource_idx
  on public.lesson_progress(resource_id);

alter table public.lesson_progress enable row level security;
grant select, insert, update on table public.lesson_progress to authenticated;

drop policy if exists "lesson progress read own" on public.lesson_progress;
create policy "lesson progress read own"
  on public.lesson_progress for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "lesson progress insert own" on public.lesson_progress;
create policy "lesson progress insert own"
  on public.lesson_progress for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "lesson progress update own" on public.lesson_progress;
create policy "lesson progress update own"
  on public.lesson_progress for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

commit;
