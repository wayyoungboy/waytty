import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum TestConnectionOutcome { connected, tableNotFound, failed }

class SupabaseService {
  static const migrationSql = r'''
-- waytty sync v1. Only capability-bearing RPCs can access ciphertext.
-- The sync code / encryption key is never sent to the database.
create table if not exists public.waytty_sync_data (
  token_hash text primary key,
  payload text not null,
  updated_at timestamptz not null default now()
);
alter table public.waytty_sync_data enable row level security;
revoke all on public.waytty_sync_data from public, anon, authenticated;

create or replace function public.waytty_sync_ping()
returns integer language sql immutable set search_path = '' as $$ select 1 $$;

create or replace function public.waytty_sync_get(access_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  if access_token is null or access_token !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid access token' using errcode = '22023';
  end if;
  select pg_catalog.jsonb_build_object('payload', s.payload, 'updated_at', s.updated_at)
    into result from public.waytty_sync_data s
    where s.token_hash = pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(access_token, 'UTF8')), 'hex');
  return result;
end $$;

create or replace function public.waytty_sync_put(access_token text, encrypted_payload text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if access_token is null or access_token !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid access token' using errcode = '22023';
  end if;
  if encrypted_payload is null or encrypted_payload not like 'v1:%'
      or pg_catalog.octet_length(encrypted_payload) > 16777216 then
    raise exception 'Invalid ciphertext' using errcode = '22023';
  end if;
  insert into public.waytty_sync_data(token_hash, payload, updated_at)
    values(pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(access_token, 'UTF8')), 'hex'), encrypted_payload, pg_catalog.now())
    on conflict(token_hash) do update set payload = excluded.payload, updated_at = excluded.updated_at;
end $$;

create or replace function public.waytty_sync_delete(access_token text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if access_token is null or access_token !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid access token' using errcode = '22023';
  end if;
  delete from public.waytty_sync_data s
    where s.token_hash = pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(access_token, 'UTF8')), 'hex');
end $$;

revoke all on function public.waytty_sync_ping() from public;
revoke all on function public.waytty_sync_get(text) from public;
revoke all on function public.waytty_sync_put(text, text) from public;
revoke all on function public.waytty_sync_delete(text) from public;
grant execute on function public.waytty_sync_ping() to anon, authenticated;
grant execute on function public.waytty_sync_get(text) to anon, authenticated;
grant execute on function public.waytty_sync_put(text, text) to anon, authenticated;
grant execute on function public.waytty_sync_delete(text) to anon, authenticated;
''';

  final String _url;
  final String _anonKey;
  final String _syncCode;
  SupabaseClient? _clientInstance;

  SupabaseService(
    this._url,
    this._anonKey,
    this._syncCode, {
    SupabaseClient? client,
  }) : _clientInstance = client;
  Future<String>? _tokenFuture;
  Future<String> get _accessToken =>
      _tokenFuture ??= deriveAccessToken(_syncCode);

  static Future<String> deriveAccessToken(String code) async {
    final key =
        await Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: 200000,
          bits: 256,
        ).deriveKey(
          secretKey: SecretKey(utf8.encode(code)),
          nonce: utf8.encode('waytty-access-v1'),
        );
    return (await key.extractBytes())
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  SupabaseClient get _client =>
      _clientInstance ??= SupabaseClient(_url, _anonKey);

  String get url => _url;
  String get anonKey => _anonKey;
  String get syncCode => _syncCode;

  /// Returns (TestConnectionOutcome, errorMessage).
  Future<(TestConnectionOutcome, String?)> testConnection() async {
    try {
      await _client.rpc('waytty_sync_ping');
      return (TestConnectionOutcome.connected, null);
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.message.contains('schema cache')) {
        return (TestConnectionOutcome.tableNotFound, null);
      }
      return (TestConnectionOutcome.failed, e.message);
    } catch (e) {
      return (TestConnectionOutcome.failed, e.toString());
    }
  }

  Future<Map<String, dynamic>?> _fetch() async {
    final value = await _client.rpc(
      'waytty_sync_get',
      params: {'access_token': await _accessToken},
    );
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  Future<String?> fetchPayload() async =>
      (await _fetch())?['payload'] as String?;

  Future<DateTime?> fetchUpdatedAt() async {
    final value = (await _fetch())?['updated_at'] as String?;
    return value == null ? null : DateTime.parse(value);
  }

  Future<void> upsertPayload(String payload) async {
    await _client.rpc(
      'waytty_sync_put',
      params: {
        'access_token': await _accessToken,
        'encrypted_payload': payload,
      },
    );
  }

  Future<void> deleteRow() async {
    await _client.rpc(
      'waytty_sync_delete',
      params: {'access_token': await _accessToken},
    );
  }
}
