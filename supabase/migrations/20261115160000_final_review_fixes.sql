-- Plan 1 final-review fixes.

-- 1. Vault data is not part of the CLI dump, so after a restore user_secret rows can
--    point at Vault rows that no longer exist. has_my_secret now requires the Vault row,
--    and set_my_secret recreates a missing Vault secret and repoints user_secret at it.
create or replace function public.set_my_secret(p_kind text, p_value text) returns void
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

create or replace function public.has_my_secret(p_kind text) returns boolean
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

-- Re-assert ACLs: default privileges may re-grant on create or replace.
revoke all on function public.set_my_secret(text, text) from public, anon, authenticated, service_role;
revoke all on function public.has_my_secret(text) from public, anon, authenticated, service_role;
grant execute on function public.set_my_secret(text, text) to authenticated;
grant execute on function public.has_my_secret(text) to authenticated;

-- 6. Hard-deleting a cupboard item must not erase waste history. Account deletion
--    still cascades through owner_id.
alter table public.cupboard_movement
  drop constraint cupboard_movement_cupboard_item_id_fkey,
  add constraint cupboard_movement_cupboard_item_id_fkey
    foreign key (cupboard_item_id) references public.cupboard_item (id) on delete set null;

-- 7. Spec section 6 lists "other". The new value is not used in this migration.
alter type public.movement_reason add value if not exists 'other';
