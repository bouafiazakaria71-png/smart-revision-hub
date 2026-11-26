-- راجع بذكاء: مخطط Supabase
-- نفّذ هذا الملف في SQL Editor داخل مشروع Supabase.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  stream text not null default '',
  role text not null default 'student' check (role in ('student','admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, stream)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'stream', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- منع المستخدم من ترقية نفسه إلى مسؤول عبر طلبات المتصفح.
create or replace function public.protect_profile_role()
returns trigger language plpgsql
as $$
begin
  if new.role is distinct from old.role and current_user <> 'postgres' then
    raise exception 'Changing profile role is not allowed';
  end if;
  new.updated_at = now();
  return new;
end;
$$;
drop trigger if exists protect_profile_role_trigger on public.profiles;
create trigger protect_profile_role_trigger
before update on public.profiles
for each row execute procedure public.protect_profile_role();

create table if not exists public.study_resources (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 140),
  subject text not null,
  level text not null,
  stream text,
  kind text not null default 'درس' check (kind in ('درس','ملخص','تمرين','حولية')),
  description text not null default '',
  file_url text,
  video_url text,
  questions jsonb not null default '[]'::jsonb check (jsonb_typeof(questions) = 'array'),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.study_resources enable row level security;

drop policy if exists "profiles read own" on public.profiles;
create policy "profiles read own" on public.profiles for select to authenticated using (auth.uid() = id);
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists "resources public read" on public.study_resources;
create policy "resources public read" on public.study_resources for select to anon, authenticated using (true);
drop policy if exists "resources admin insert" on public.study_resources;
create policy "resources admin insert" on public.study_resources for insert to authenticated
with check (created_by = auth.uid() and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
drop policy if exists "resources admin update" on public.study_resources;
create policy "resources admin update" on public.study_resources for update to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
drop policy if exists "resources admin delete" on public.study_resources;
create policy "resources admin delete" on public.study_resources for delete to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

grant select on public.study_resources to anon, authenticated;
grant insert, update, delete on public.study_resources to authenticated;
grant select, update on public.profiles to authenticated;

-- التوسعة الإدارية: عرض قائمة الطلاب مع بقاء البيانات محمية عن بقية المستخدمين.
alter table public.profiles add column if not exists email text not null default '';
update public.profiles p set email = coalesce(u.email,'') from auth.users u where u.id = p.id and (p.email = '' or p.email is null);
alter table public.study_resources add column if not exists video_url text;
alter table public.study_resources add column if not exists questions jsonb not null default '[]'::jsonb;
do $ begin
  alter table public.study_resources add constraint study_resources_questions_array check (jsonb_typeof(questions) = 'array');
exception when duplicate_object then null;
end $;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $
begin
  insert into public.profiles (id, full_name, email, stream)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'stream', '')
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$;

-- دالة صلاحية آمنة تمنع تكرار RLS عند قراءة ملف المسؤول نفسه.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$;
grant execute on function public.is_admin() to authenticated;

drop policy if exists "profiles admin read all" on public.profiles;
create policy "profiles admin read all" on public.profiles
for select to authenticated using (public.is_admin());
drop policy if exists "profiles admin update" on public.profiles;
create policy "profiles admin update" on public.profiles
for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- سياسات الموارد تستخدم الدالة الآمنة نفسها.
drop policy if exists "resources admin insert" on public.study_resources;
create policy "resources admin insert" on public.study_resources for insert to authenticated
with check (created_by = auth.uid() and public.is_admin());
drop policy if exists "resources admin update" on public.study_resources;
create policy "resources admin update" on public.study_resources for update to authenticated
using (public.is_admin()) with check (public.is_admin());
drop policy if exists "resources admin delete" on public.study_resources;
create policy "resources admin delete" on public.study_resources for delete to authenticated
using (public.is_admin());

-- مخزن عام لقراءة ملفات PDF، والرفع والتعديل والحذف للمسؤول فقط.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('study-pdfs', 'study-pdfs', true, 20971520, array['application/pdf'])
on conflict (id) do update set public = true, file_size_limit = 20971520, allowed_mime_types = array['application/pdf'];

drop policy if exists "study pdf public read" on storage.objects;
create policy "study pdf public read" on storage.objects for select to anon, authenticated
using (bucket_id = 'study-pdfs');
drop policy if exists "study pdf admin upload" on storage.objects;
create policy "study pdf admin upload" on storage.objects for insert to authenticated
with check (bucket_id = 'study-pdfs' and public.is_admin());
drop policy if exists "study pdf admin update" on storage.objects;
create policy "study pdf admin update" on storage.objects for update to authenticated
using (bucket_id = 'study-pdfs' and public.is_admin())
with check (bucket_id = 'study-pdfs' and public.is_admin());
drop policy if exists "study pdf admin delete" on storage.objects;
create policy "study pdf admin delete" on storage.objects for delete to authenticated
using (bucket_id = 'study-pdfs' and public.is_admin());

-- بعد إنشاء حسابك وتأكيده، عيّن دور المسؤول يدويًا من SQL Editor:
-- update public.profiles
-- set role = 'admin'
-- where id = (select id from auth.users where email = 'YOUR_ADMIN_EMAIL');
-- لا تستخدم service_role key في الواجهة مطلقًا.
