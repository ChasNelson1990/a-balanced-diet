-- food_unit and food_group_share sync row by row like every other table: a
-- server-set updated_at to pull by, and deleted_at as the deletion tombstone.
-- (Supersedes the owner DELETE grant and policies from the food library migration.)

alter table public.food_unit
  add column updated_at timestamptz not null default now(),
  add column deleted_at timestamptz;
alter table public.food_group_share
  add column updated_at timestamptz not null default now(),
  add column deleted_at timestamptz;

-- Insert as well as update: a row created offline must take the time it reached
-- the server, or a device that pulled in the meantime would never fetch it.
create trigger food_unit_set_updated_at before insert or update on public.food_unit
  for each row execute function public.set_updated_at();
create trigger food_group_share_set_updated_at before insert or update on public.food_group_share
  for each row execute function public.set_updated_at();

-- Pulls are "changed since <last sync>", filtered by RLS.
create index food_unit_updated_at_idx on public.food_unit (updated_at);
create index food_group_share_updated_at_idx on public.food_group_share (updated_at);

-- A deleted label can be added again as a new unit. A deleted share is re-added
-- by upserting on its key with deleted_at = null, so its primary key stays as is.
alter table public.food_unit drop constraint food_unit_food_id_label_key;
create unique index food_unit_live_label_key on public.food_unit (food_id, label)
  where deleted_at is null;

-- Soft delete only: a hard delete leaves nothing for other devices to pull.
drop policy food_unit_delete on public.food_unit;
drop policy food_group_share_delete on public.food_group_share;
revoke delete on public.food_unit, public.food_group_share from authenticated;

-- Changing a key is a hard delete in disguise: other devices keep the old row.
-- To move a share to another group, soft-delete it and upsert the new one.
-- (A trigger, as column grants would break upserts that send the key columns.)
create function public.reject_key_change() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'the key of a % row cannot change: soft-delete it and add a new one', tg_table_name
    using errcode = 'check_violation';
end $$;
revoke all on function public.reject_key_change() from public, anon, authenticated;

create trigger food_unit_key_immutable before update on public.food_unit
  for each row when (old.id is distinct from new.id)
  execute function public.reject_key_change();
create trigger food_group_share_key_immutable before update on public.food_group_share
  for each row when ((old.food_id, old.group_code) is distinct from (new.food_id, new.group_code))
  execute function public.reject_key_change();
