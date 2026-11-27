-- تهيئة حد الاستخدام اليومي للمساعد الدراسي
create table if not exists public.ai_usage_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null default current_date,
  request_count integer not null default 0 check (request_count >= 0),
  primary key (user_id, usage_date)
);

alter table public.ai_usage_daily enable row level security;
revoke all on table public.ai_usage_daily from anon, authenticated;

create or replace function public.consume_ai_daily_limit()
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_count integer;
begin
  if v_user is null then
    return false;
  end if;

  insert into public.ai_usage_daily (user_id, usage_date, request_count)
  values (v_user, current_date, 1)
  on conflict (user_id, usage_date)
  do update
    set request_count = public.ai_usage_daily.request_count + 1
    where public.ai_usage_daily.request_count < 25
  returning request_count into v_count;

  return v_count is not null;
end;
$function$;

revoke all on function public.consume_ai_daily_limit() from public, anon;
grant execute on function public.consume_ai_daily_limit() to authenticated;
