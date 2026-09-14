-- XTerminal Native sync v1. Only capability-bearing RPCs can access ciphertext.
-- The sync code / encryption key is never sent to the database.
create table if not exists public.xtn_sync_data (
  token_hash text primary key,
  payload text not null,
  updated_at timestamptz not null default now()
);
alter table public.xtn_sync_data enable row level security;
revoke all on public.xtn_sync_data from public, anon, authenticated;

create or replace function public.xtn_sync_ping()
returns integer language sql immutable set search_path = '' as $$ select 1 $$;

create or replace function public.xtn_sync_get(access_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if access_token is null or access_token !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid access token' using errcode = '22023';
  end if;
  select pg_catalog.jsonb_build_object('payload', s.payload, 'updated_at', s.updated_at)
    into result from public.xtn_sync_data s
    where s.token_hash = pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(access_token, 'UTF8')), 'hex');
  return result;
end $$;

create or replace function public.xtn_sync_put(access_token text, encrypted_payload text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if access_token is null or access_token !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid access token' using errcode = '22023';
  end if;
  if encrypted_payload is null or encrypted_payload not like 'v1:%'
      or pg_catalog.octet_length(encrypted_payload) > 16777216 then
    raise exception 'Invalid ciphertext' using errcode = '22023';
  end if;
  insert into public.xtn_sync_data(token_hash, payload, updated_at)
    values(pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(access_token, 'UTF8')), 'hex'), encrypted_payload, pg_catalog.now())
    on conflict(token_hash) do update set payload = excluded.payload, updated_at = excluded.updated_at;
end $$;

create or replace function public.xtn_sync_delete(access_token text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if access_token is null or access_token !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid access token' using errcode = '22023';
  end if;
  delete from public.xtn_sync_data s
    where s.token_hash = pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(access_token, 'UTF8')), 'hex');
end $$;

revoke all on function public.xtn_sync_ping() from public;
revoke all on function public.xtn_sync_get(text) from public;
revoke all on function public.xtn_sync_put(text, text) from public;
revoke all on function public.xtn_sync_delete(text) from public;
grant execute on function public.xtn_sync_ping() to anon, authenticated;
grant execute on function public.xtn_sync_get(text) to anon, authenticated;
grant execute on function public.xtn_sync_put(text, text) to anon, authenticated;
grant execute on function public.xtn_sync_delete(text) to anon, authenticated;
