\set ON_ERROR_STOP on
begin;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
end $$;
\ir ../migrations/20260529000000_sync_data.sql

set local role anon;
do $$
declare a text := repeat('a', 64); b text := repeat('b', 64);
begin
  begin
    perform * from public.xtn_sync_data;
    raise exception 'Anonymous table reads must fail';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.xtn_sync_data values ('bad', 'v1:bad', now());
    raise exception 'Anonymous table writes must fail';
  exception when insufficient_privilege then null;
  end;
  perform public.xtn_sync_put(a, 'v1:ciphertext-A');
  perform public.xtn_sync_put(b, 'v1:ciphertext-B');
  if public.xtn_sync_get(a)->>'payload' <> 'v1:ciphertext-A' then
    raise exception 'Workspace A read failed';
  end if;
  if public.xtn_sync_get(repeat('c', 64)) is not null then
    raise exception 'Unknown capabilities must not discover workspaces';
  end if;
  perform public.xtn_sync_put(a, 'v1:ciphertext-A2');
  if public.xtn_sync_get(a)->>'payload' <> 'v1:ciphertext-A2' then
    raise exception 'Workspace A update failed';
  end if;
  begin
    perform public.xtn_sync_get('raw-sync-code');
    raise exception 'Malformed capabilities must fail';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.xtn_sync_put(a, 'plaintext');
    raise exception 'Unframed ciphertext must fail';
  exception when invalid_parameter_value then null;
  end;
  perform public.xtn_sync_delete(a);
  if public.xtn_sync_get(a) is not null then raise exception 'Delete failed'; end if;
  if public.xtn_sync_get(b)->>'payload' <> 'v1:ciphertext-B' then
    raise exception 'Deleting A must not affect B';
  end if;
end $$;
reset role;
do $$ begin
  if exists(select 1 from public.xtn_sync_data where token_hash = repeat('b', 64)) then
    raise exception 'Database must store a hash, not a bearer capability';
  end if;
end $$;
rollback;
\echo Sync RPC isolation tests passed.
