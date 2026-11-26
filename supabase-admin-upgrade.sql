-- ترقية قاعدة "راجع بذكاء" لإضافة لوحة المسؤول.
-- نفّذ هذا الملف مرة واحدة في Supabase > SQL Editor.
alter table public.profiles add column if not exists email text not null default '';
update public.profiles p set email = coalesce(u.email,'') from auth.users u where u.id = p.id and (p.email = '' or p.email is null);
alter table public.study_resources add column if not exists video_url text;
alter table public.study_resources add column if not exists questions jsonb not null default '[]'::jsonb;
do $$ begin
  alter table public.study_resources add constraint study_resources_questions_array check (jsonb_typeof(questions) = 'array');
exception when duplicate_object then null;
end $$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, stream)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name',''), coalesce(new.email,''), coalesce(new.raw_user_meta_data ->> 'stream',''))
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;
grant execute on function public.is_admin() to authenticated;

drop policy if exists "profiles admin read all" on public.profiles;
create policy "profiles admin read all" on public.profiles for select to authenticated using (public.is_admin());
drop policy if exists "profiles admin update" on public.profiles;
create policy "profiles admin update" on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "resources admin insert" on public.study_resources;
create policy "resources admin insert" on public.study_resources for insert to authenticated with check (created_by = auth.uid() and public.is_admin());
drop policy if exists "resources admin update" on public.study_resources;
create policy "resources admin update" on public.study_resources for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "resources admin delete" on public.study_resources;
create policy "resources admin delete" on public.study_resources for delete to authenticated using (public.is_admin());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('study-pdfs','study-pdfs',true,20971520,array['application/pdf'])
on conflict (id) do update set public=true,file_size_limit=20971520,allowed_mime_types=array['application/pdf'];

drop policy if exists "study pdf public read" on storage.objects;
create policy "study pdf public read" on storage.objects for select to anon, authenticated using (bucket_id='study-pdfs');
drop policy if exists "study pdf admin upload" on storage.objects;
create policy "study pdf admin upload" on storage.objects for insert to authenticated with check (bucket_id='study-pdfs' and public.is_admin());
drop policy if exists "study pdf admin update" on storage.objects;
create policy "study pdf admin update" on storage.objects for update to authenticated using (bucket_id='study-pdfs' and public.is_admin()) with check (bucket_id='study-pdfs' and public.is_admin());
drop policy if exists "study pdf admin delete" on storage.objects;
create policy "study pdf admin delete" on storage.objects for delete to authenticated using (bucket_id='study-pdfs' and public.is_admin());

-- لا يمنح هذا الملف دور المسؤول تلقائيًا. استخدم استعلام تعيين المسؤول بعد تسجيل الدخول.
