-- À exécuter dans Supabase > SQL Editor (une seule fois)
create schema if not exists mon_compte;
revoke all on schema mon_compte from public, anon, authenticated;

create table if not exists mon_compte.user_backup(
  user_id uuid primary key references auth.users(id) on delete cascade,
  u bigint not null, data jsonb not null,
  prev_u bigint, prev jsonb,
  updated_at timestamptz not null default now());
alter table mon_compte.user_backup enable row level security;

create or replace function public.mc_get2() returns jsonb
language plpgsql security definer set search_path = pg_catalog, mon_compte as $$
declare r mon_compte.user_backup;
begin
  if auth.uid() is null then raise exception 'Non connecté'; end if;
  select * into r from mon_compte.user_backup where user_id = auth.uid();
  if not found then return jsonb_build_object('empty', true); end if;
  return jsonb_build_object('u', r.u, 'data', r.data);
end $$;

create or replace function public.mc_put2(u bigint, data jsonb) returns jsonb
language plpgsql security definer set search_path = pg_catalog, mon_compte as $$
begin
  if auth.uid() is null then raise exception 'Non connecté'; end if;
  insert into mon_compte.user_backup(user_id,u,data) values (auth.uid(),u,data)
  on conflict (user_id) do update
    set prev_u = mon_compte.user_backup.u, prev = mon_compte.user_backup.data,
        u = excluded.u, data = excluded.data, updated_at = now();
  return jsonb_build_object('ok', true, 'u', u);
end $$;

create or replace function public.mc_ping() returns int
language sql security definer set search_path = pg_catalog as $$ select 1 $$;

revoke all on function public.mc_get2() from public, anon;
revoke all on function public.mc_put2(bigint,jsonb) from public, anon;
grant execute on function public.mc_get2() to authenticated;
grant execute on function public.mc_put2(bigint,jsonb) to authenticated;
grant execute on function public.mc_ping() to anon, authenticated;

-- Ancienne version avec mot de passe unique (si tu l'avais créée) :
drop function if exists public.mc_get(text);
drop function if exists public.mc_put(text,bigint,jsonb);
