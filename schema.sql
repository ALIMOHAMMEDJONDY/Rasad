-- ============================================================
-- Rasad | قاعدة بيانات رَصَد  (Supabase / PostgreSQL)
-- الصق هذا الملف كاملاً في: SQL Editor ثم Run
-- ============================================================

create extension if not exists pgcrypto;

-- المشرفون
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create or replace function public.is_admin()
returns boolean
language sql security definer set search_path = public stable
as $$ select exists (select 1 from public.admins where user_id = auth.uid()); $$;

-- القياسات
create table if not exists public.readings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  city        text not null check (char_length(city) between 1 and 80),
  lon         double precision check (lon is null or lon between 38.5 and 48.9),
  lat         double precision check (lat is null or lat between 28.9 and 37.5),
  ra          numeric not null default 0 check (ra between 0 and 100000),
  th          numeric not null default 0 check (th between 0 and 100000),
  k           numeric not null default 0 check (k  between 0 and 100000),
  rn          numeric not null default 0 check (rn between 0 and 100000),
  raeq        numeric,
  hex         numeric,
  tot         numeric,
  risk        text check (risk in ('ok','cau','hi')),
  status      text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);
create index if not exists readings_status_idx on public.readings(status);
create index if not exists readings_user_idx   on public.readings(user_id);

-- الحساب يتم في الخادم حتى لا يستطيع أحد التلاعب بالنتائج
create or replace function public.rasad_compute()
returns trigger language plpgsql as $$
declare d numeric; gam numeric; rdose numeric; lvl int := 1;
begin
  if (select count(*) from public.readings
       where user_id = new.user_id and status = 'pending') >= 50 then
    raise exception 'too many pending readings';
  end if;
  new.status := 'pending';
  new.raeq := round(new.ra + 1.43*new.th + 0.077*new.k, 1);
  new.hex  := round(new.ra/370 + new.th/259 + new.k/4810, 2);
  d        := 0.462*new.ra + 0.604*new.th + 0.0417*new.k;
  gam      := d*8760*0.7e-6;
  rdose    := new.rn*0.4*7000*9e-6;
  new.tot  := round(gam + rdose, 2);
  if new.raeq > 370 or new.hex > 1 or gam > 1 then lvl := 3; end if;
  if new.rn > 300 or rdose > 3 then lvl := 3;
  elsif (new.rn > 100 or rdose > 1) and lvl < 2 then lvl := 2; end if;
  new.risk := case lvl when 3 then 'hi' when 2 then 'cau' else 'ok' end;
  return new;
end $$;

drop trigger if exists readings_compute on public.readings;
create trigger readings_compute before insert on public.readings
  for each row execute function public.rasad_compute();

-- المشرف يغيّر الحالة فقط، لا القيم
create or replace function public.rasad_guard_update()
returns trigger language plpgsql as $$
begin
  if (new.city,new.lon,new.lat,new.ra,new.th,new.k,new.rn,new.user_id,new.tot,new.risk)
     is distinct from
     (old.city,old.lon,old.lat,old.ra,old.th,old.k,old.rn,old.user_id,old.tot,old.risk) then
    raise exception 'only status can be changed';
  end if;
  return new;
end $$;

drop trigger if exists readings_guard on public.readings;
create trigger readings_guard before update on public.readings
  for each row execute function public.rasad_guard_update();

-- الأمان (Row Level Security)
alter table public.readings enable row level security;
alter table public.admins   enable row level security;

drop policy if exists "public read approved"      on public.readings;
drop policy if exists "read own"                  on public.readings;
drop policy if exists "admin read all"            on public.readings;
drop policy if exists "insert own pending"        on public.readings;
drop policy if exists "admin update"              on public.readings;
drop policy if exists "delete own pending/admin"  on public.readings;
drop policy if exists "read own admin row"        on public.admins;

create policy "public read approved" on public.readings
  for select to anon, authenticated using (status = 'approved');
create policy "read own" on public.readings
  for select to authenticated using (user_id = auth.uid());
create policy "admin read all" on public.readings
  for select to authenticated using (public.is_admin());
create policy "insert own pending" on public.readings
  for insert to authenticated with check (user_id = auth.uid());
create policy "admin update" on public.readings
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "delete own pending/admin" on public.readings
  for delete to authenticated
  using ((user_id = auth.uid() and status = 'pending') or public.is_admin());
create policy "read own admin row" on public.admins
  for select to authenticated using (user_id = auth.uid());

-- ============================================================
-- بعد ما تسجّل حسابك داخل التطبيق، شغّل هذا السطر مرة وحدة
-- (غيّر الإيميل إلى إيميلك) لتصير أنت المشرف:
--
-- insert into public.admins(user_id)
--   select id from auth.users where email = 'YOUR_EMAIL_HERE';
-- ============================================================
