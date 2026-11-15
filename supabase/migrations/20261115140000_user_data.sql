-- Per-user data: targets, plan, log, cupboard, shopping, weight.
-- Every table is owner-only. No delete grants (soft delete via deleted_at).
-- FK checks bypass RLS, so every policy that writes a reference to a row outside
-- the caller's own data must also prove the caller can see/own the target.

create type public.group_status as enum ('excluded', 'allowed', 'favoured');
create type public.dairy_basis as enum ('energy', 'milk_used');
create type public.base_pattern as enum ('flexitarian', 'pescatarian', 'vegetarian', 'vegan');
create type public.meal_slot as enum ('breakfast', 'lunch', 'dinner', 'snacks');
create type public.movement_reason as enum
  ('bought', 'eaten_logged', 'went_off', 'gave_away', 'eaten_unlogged', 'stock_correction', 'other');

create table public.profile_targets (
  owner_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  kcal_target int not null check (kcal_target between 800 and 6000),
  protein_floor_g numeric not null,
  fibre_floor_g numeric not null,
  fibre_soft_ceiling_g numeric,
  colour_split jsonb not null default '{"green":0.5,"yellow":0.3,"orange":0.2}'
    check (coalesce(abs((colour_split->>'green')::numeric + (colour_split->>'yellow')::numeric
      + (colour_split->>'orange')::numeric - 1) < 0.001, false)),
  colour_tolerance_pts numeric not null default 3,
  dairy_basis public.dairy_basis not null default 'energy',
  base_pattern public.base_pattern not null default 'flexitarian',
  wholegrain_goal numeric not null default 0.75 check (wholegrain_goal between 0 and 1),
  setup_completed_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.profile_group_setting (
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  group_code text not null references public.eat_group (code),
  status public.group_status not null default 'allowed',
  pinned_per_day numeric,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (owner_id, group_code)
);
create index profile_group_setting_group_code_idx on public.profile_group_setting (group_code);

create table public.plan (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  effective_from date not null,
  groups jsonb not null,
  expected jsonb not null,
  accepted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- food FKs are NO ACTION (not RESTRICT): a direct hard delete of a used food
-- still fails (23503), but an account-delete cascade can remove foods and the
-- owner's rows in one statement.
create table public.log_entry (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day date not null,
  slot public.meal_slot not null,
  food_id uuid not null references public.food (id),
  quantity_g numeric not null check (quantity_g > 0),
  unit_id uuid references public.food_unit (id) on delete set null,
  unit_count numeric,
  from_cupboard boolean not null default false,
  breakdown jsonb,
  snapshot jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.cupboard_item (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  food_id uuid not null references public.food (id),
  quantity_g numeric not null check (quantity_g >= 0),
  added_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.cupboard_movement (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- set null: hard-deleting a cupboard item must not erase waste history. Account
  -- deletion still cascades through owner_id.
  cupboard_item_id uuid references public.cupboard_item (id) on delete set null,
  food_id uuid not null references public.food (id),
  reason public.movement_reason not null,
  quantity_g numeric not null check (quantity_g > 0),
  log_entry_id uuid references public.log_entry (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.shopping_item (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  food_id uuid not null references public.food (id),
  quantity_g numeric not null check (quantity_g > 0),
  unit_id uuid references public.food_unit (id) on delete set null,
  unit_count numeric,
  ticked_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.weight_entry (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day date not null,
  kg numeric not null check (kg between 20 and 400),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (owner_id, day)
);

-- Indexes: sync pull, day lookups, repeat-a-meal, and FK columns.
create index profile_targets_sync_idx on public.profile_targets (owner_id, updated_at);
create index profile_group_setting_sync_idx on public.profile_group_setting (owner_id, updated_at);
create index plan_sync_idx on public.plan (owner_id, updated_at);
create index log_entry_sync_idx on public.log_entry (owner_id, updated_at);
create index log_entry_day_idx on public.log_entry (owner_id, day);
create index log_entry_recent_idx on public.log_entry (owner_id, created_at desc);
create index log_entry_food_id_idx on public.log_entry (food_id);
create index log_entry_unit_id_idx on public.log_entry (unit_id);
create index cupboard_item_sync_idx on public.cupboard_item (owner_id, updated_at);
create index cupboard_item_food_id_idx on public.cupboard_item (food_id);
create index cupboard_movement_sync_idx on public.cupboard_movement (owner_id, updated_at);
create index cupboard_movement_item_idx on public.cupboard_movement (cupboard_item_id);
create index cupboard_movement_food_id_idx on public.cupboard_movement (food_id);
create index cupboard_movement_log_entry_idx on public.cupboard_movement (log_entry_id);
create index shopping_item_sync_idx on public.shopping_item (owner_id, updated_at);
create index shopping_item_food_id_idx on public.shopping_item (food_id);
create index shopping_item_unit_id_idx on public.shopping_item (unit_id);
create index weight_entry_sync_idx on public.weight_entry (owner_id, updated_at);

create trigger profile_targets_set_updated_at before update on public.profile_targets
  for each row execute function public.set_updated_at();
create trigger profile_group_setting_set_updated_at before update on public.profile_group_setting
  for each row execute function public.set_updated_at();
create trigger plan_set_updated_at before update on public.plan
  for each row execute function public.set_updated_at();
create trigger log_entry_set_updated_at before update on public.log_entry
  for each row execute function public.set_updated_at();
create trigger cupboard_item_set_updated_at before update on public.cupboard_item
  for each row execute function public.set_updated_at();
create trigger cupboard_movement_set_updated_at before update on public.cupboard_movement
  for each row execute function public.set_updated_at();
create trigger shopping_item_set_updated_at before update on public.shopping_item
  for each row execute function public.set_updated_at();
create trigger weight_entry_set_updated_at before update on public.weight_entry
  for each row execute function public.set_updated_at();

-- RLS + grants
alter table public.profile_targets enable row level security;
alter table public.profile_group_setting enable row level security;
alter table public.plan enable row level security;
alter table public.log_entry enable row level security;
alter table public.cupboard_item enable row level security;
alter table public.cupboard_movement enable row level security;
alter table public.shopping_item enable row level security;
alter table public.weight_entry enable row level security;

revoke all on public.profile_targets, public.profile_group_setting, public.plan,
  public.log_entry, public.cupboard_item, public.cupboard_movement,
  public.shopping_item, public.weight_entry from anon, authenticated;
grant select, insert, update on public.profile_targets, public.profile_group_setting,
  public.plan, public.log_entry, public.cupboard_item, public.shopping_item,
  public.weight_entry to authenticated;
grant select, insert on public.cupboard_movement to authenticated;  -- append-only

-- Simple owner-only tables
create policy profile_targets_select on public.profile_targets for select to authenticated
  using (owner_id = (select auth.uid()));
create policy profile_targets_insert on public.profile_targets for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy profile_targets_update on public.profile_targets for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

create policy profile_group_setting_select on public.profile_group_setting for select to authenticated
  using (owner_id = (select auth.uid()));
create policy profile_group_setting_insert on public.profile_group_setting for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy profile_group_setting_update on public.profile_group_setting for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

create policy plan_select on public.plan for select to authenticated
  using (owner_id = (select auth.uid()));
create policy plan_insert on public.plan for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy plan_update on public.plan for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

create policy weight_entry_select on public.weight_entry for select to authenticated
  using (owner_id = (select auth.uid()));
create policy weight_entry_insert on public.weight_entry for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy weight_entry_update on public.weight_entry for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- Tables referencing foods/units: the referenced rows must be visible to the caller.
-- (food_unit's own select policy follows food visibility, so exists() on it under
-- the caller's RLS is exactly "unit whose food is visible".)
create policy log_entry_select on public.log_entry for select to authenticated
  using (owner_id = (select auth.uid()));
create policy log_entry_insert on public.log_entry for insert to authenticated
  with check (owner_id = (select auth.uid()) and public.food_is_visible(food_id)
    and (unit_id is null or exists (select 1 from public.food_unit u where u.id = unit_id)));
create policy log_entry_update on public.log_entry for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()) and public.food_is_visible(food_id)
    and (unit_id is null or exists (select 1 from public.food_unit u where u.id = unit_id)));

create policy cupboard_item_select on public.cupboard_item for select to authenticated
  using (owner_id = (select auth.uid()));
create policy cupboard_item_insert on public.cupboard_item for insert to authenticated
  with check (owner_id = (select auth.uid()) and public.food_is_visible(food_id));
create policy cupboard_item_update on public.cupboard_item for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()) and public.food_is_visible(food_id));

create policy shopping_item_select on public.shopping_item for select to authenticated
  using (owner_id = (select auth.uid()));
create policy shopping_item_insert on public.shopping_item for insert to authenticated
  with check (owner_id = (select auth.uid()) and public.food_is_visible(food_id)
    and (unit_id is null or exists (select 1 from public.food_unit u where u.id = unit_id)));
create policy shopping_item_update on public.shopping_item for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()) and public.food_is_visible(food_id)
    and (unit_id is null or exists (select 1 from public.food_unit u where u.id = unit_id)));

create policy cupboard_movement_select on public.cupboard_movement for select to authenticated
  using (owner_id = (select auth.uid()));
create policy cupboard_movement_insert on public.cupboard_movement for insert to authenticated
  with check (owner_id = (select auth.uid()) and public.food_is_visible(food_id)
    and (cupboard_item_id is null or exists (
      select 1 from public.cupboard_item c
      where c.id = cupboard_item_id and c.owner_id = (select auth.uid())))
    and (log_entry_id is null or exists (
      select 1 from public.log_entry l
      where l.id = log_entry_id and l.owner_id = (select auth.uid()))));
