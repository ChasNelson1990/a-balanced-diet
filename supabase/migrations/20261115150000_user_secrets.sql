-- Per-user Anthropic API key storage in Supabase Vault.
-- Users can write and test for a key but never read one back; only service_role
-- (Plan 4 Edge Function) can, via private.get_user_secret.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;

create table public.user_secret (
  owner_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('anthropic_api_key')),
  vault_secret_id uuid not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, kind)
);
alter table public.user_secret enable row level security;
-- No policies: RLS denies every row. SELECT is granted to authenticated only so a
-- direct select returns 0 rows rather than an error; no write privileges at all.
revoke all on public.user_secret from anon, authenticated;
grant select on public.user_secret to authenticated;

-- Deleting a user_secret row (clear_my_secret, or cascade from account deletion)
-- removes the Vault secret so no decryptable key is orphaned.
create function private.user_secret_cleanup() returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  delete from vault.secrets where id = old.vault_secret_id;
  return old;
end $$;
revoke all on function private.user_secret_cleanup() from public, anon, authenticated;

create trigger user_secret_after_delete
  after delete on public.user_secret
  for each row execute function private.user_secret_cleanup();

-- vault.secrets is not in the CLI dump, so after a restore user_secret rows can point at
-- Vault rows that no longer exist. has_my_secret requires the Vault row, and set_my_secret
-- recreates a missing Vault secret and repoints user_secret at it.
create function public.set_my_secret(p_kind text, p_value text) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  sname text;
  sid uuid;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_kind is null or p_kind not in ('anthropic_api_key') then
    raise exception 'unsupported secret kind';
  end if;
  if p_value is null or length(p_value) < 20 then
    raise exception 'secret value too short';
  end if;

  sname := 'user:' || uid::text || ':' || p_kind;
  -- serialise concurrent sets for the same secret
  perform pg_advisory_xact_lock(hashtextextended(sname, 0));

  select vault_secret_id into sid
  from public.user_secret where owner_id = uid and kind = p_kind;

  if sid is not null and exists (select 1 from vault.secrets where id = sid) then
    perform vault.update_secret(sid, p_value);
    update public.user_secret set updated_at = now()
    where owner_id = uid and kind = p_kind;
  else
    -- no row yet, or the Vault row is gone (restore from backup): create a fresh secret.
    -- A leftover Vault row with this name but another id would clash on the unique name.
    delete from vault.secrets where name = sname;
    sid := vault.create_secret(p_value, sname, 'per-user secret');
    insert into public.user_secret (owner_id, kind, vault_secret_id)
    values (uid, p_kind, sid)
    on conflict (owner_id, kind)
    do update set vault_secret_id = excluded.vault_secret_id, updated_at = now();
  end if;
end $$;

create function public.has_my_secret(p_kind text) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_secret us
    join vault.secrets vs on vs.id = us.vault_secret_id
    where us.owner_id = (select auth.uid()) and us.kind = p_kind
  )
$$;

create function public.clear_my_secret(p_kind text) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  -- the AFTER DELETE trigger removes the Vault secret
  delete from public.user_secret where owner_id = uid and kind = p_kind;
end $$;

create function private.get_user_secret(p_owner uuid, p_kind text) returns text
language sql stable security definer
set search_path = ''
as $$
  select ds.decrypted_secret
  from public.user_secret us
  join vault.decrypted_secrets ds on ds.id = us.vault_secret_id
  where us.owner_id = p_owner and us.kind = p_kind
$$;

revoke all on function public.set_my_secret(text, text) from public, anon, authenticated, service_role;
revoke all on function public.has_my_secret(text) from public, anon, authenticated, service_role;
revoke all on function public.clear_my_secret(text) from public, anon, authenticated, service_role;
revoke all on function private.get_user_secret(uuid, text) from public, anon, authenticated;
grant execute on function public.set_my_secret(text, text) to authenticated;
grant execute on function public.has_my_secret(text) to authenticated;
grant execute on function public.clear_my_secret(text) to authenticated;
grant execute on function private.get_user_secret(uuid, text) to service_role;
