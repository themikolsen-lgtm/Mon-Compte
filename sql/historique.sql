create table if not exists mon_compte.user_history(
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  u bigint not null, data jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
create index if not exists user_history_user on mon_compte.user_history(user_id, id desc);
alter table mon_compte.user_history enable row level security;

drop function if exists public.mc_put2(bigint,jsonb);
create or replace function public.mc_put2(u bigint, data jsonb, force boolean default false) returns jsonb
language plpgsql security definer set search_path = pg_catalog, mon_compte as $$
declare lid bigint; lt timestamptz;
begin
  if auth.uid() is null then raise exception 'Non connecté'; end if;
  insert into mon_compte.user_backup(user_id,u,data) values (auth.uid(),u,data)
  on conflict (user_id) do update
    set prev_u = mon_compte.user_backup.u, prev = mon_compte.user_backup.data,
        u = excluded.u, data = excluded.data, updated_at = now();
  select h.id, h.created_at into lid, lt from mon_compte.user_history h where h.user_id = auth.uid() order by h.id desc limit 1;
  if force or lid is null or lt < now() - interval '30 minutes' then
    insert into mon_compte.user_history(user_id,u,data) values (auth.uid(),u,data);
  else
    update mon_compte.user_history h set u = mc_put2.u, data = mc_put2.data, updated_at = now() where h.id = lid;
  end if;
  delete from mon_compte.user_history h where h.user_id = auth.uid()
    and h.id not in (select x.id from mon_compte.user_history x where x.user_id = auth.uid() order by x.id desc limit 60);
  return jsonb_build_object('ok', true, 'u', u);
end $$;

create or replace function public.mc_hist() returns jsonb
language plpgsql security definer set search_path = pg_catalog, mon_compte as $$
begin
  if auth.uid() is null then raise exception 'Non connecté'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'u',h.u,'t',(extract(epoch from h.updated_at)*1000)::bigint,'n',coalesce(jsonb_array_length(h.data->'dep'),0)) order by h.id desc)
    from mon_compte.user_history h where h.user_id = auth.uid()), '[]'::jsonb);
end $$;

create or replace function public.mc_hist_get(hid bigint) returns jsonb
language plpgsql security definer set search_path = pg_catalog, mon_compte as $$
declare r mon_compte.user_history;
begin
  if auth.uid() is null then raise exception 'Non connecté'; end if;
  select * into r from mon_compte.user_history where id = hid and user_id = auth.uid();
  if not found then raise exception 'Sauvegarde introuvable'; end if;
  return jsonb_build_object('u', r.u, 'data', r.data);
end $$;

revoke all on function public.mc_put2(bigint,jsonb,boolean) from public, anon;
revoke all on function public.mc_hist() from public, anon;
revoke all on function public.mc_hist_get(bigint) from public, anon;
grant execute on function public.mc_put2(bigint,jsonb,boolean) to authenticated;
grant execute on function public.mc_hist() to authenticated;
grant execute on function public.mc_hist_get(bigint) to authenticated;
