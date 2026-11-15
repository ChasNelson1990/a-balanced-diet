-- Food library: shared/public foods have no owner, private foods belong to one user.
create type public.food_source as enum ('user', 'cofid', 'off', 'ai', 'manual');
create type public.visibility as enum ('private', 'shared', 'public');
create type public.food_state as enum ('raw', 'dry', 'cooked', 'as_eaten');
create type public.colour_kind as enum ('solid', 'soup_sauce', 'drink');
create type public.colour as enum ('green', 'yellow', 'orange');
create type public.shares_status as enum ('none', 'guessed', 'confirmed', 'derived');

-- Shared updated_at maintenance (reused by later tasks).
create function public.set_updated_at() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;
-- Trigger-only: nobody needs to call it, and anon must not be able to (catalog guard).
revoke all on function public.set_updated_at() from public, anon;

create table public.food_family (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  reference_state public.food_state not null
);

create table public.food (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  source public.food_source not null,
  source_ref text,
  visibility public.visibility not null,
  owner_id uuid default auth.uid() references auth.users (id) on delete cascade,
  derived_from uuid references public.food (id) on delete set null,
  family_id uuid references public.food_family (id),
  family_yield numeric check (family_yield > 0),
  state public.food_state not null default 'as_eaten',
  colour_kind public.colour_kind not null default 'solid',
  colour_override public.colour,
  kcal_per_100g numeric check (kcal_per_100g >= 0),
  nutrients_per_100g jsonb not null default '{}',
  wholegrain_fraction numeric check (wholegrain_fraction between 0 and 1),
  milk_eq_energy_factor numeric,
  milk_eq_milk_used_factor numeric,
  co2e_kg_per_kg numeric,
  co2e_factor_id uuid references public.co2e_factor (id),
  shares_status public.shares_status not null default 'none',
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check ((visibility = 'private') = (owner_id is not null))
);
create unique index food_shared_source_ref_key on public.food (source, source_ref) where visibility = 'shared';
create index food_owner_id_idx on public.food (owner_id);
create index food_family_id_idx on public.food (family_id);
create trigger food_set_updated_at before update on public.food
  for each row execute function public.set_updated_at();

create table public.food_group_share (
  food_id uuid not null references public.food (id) on delete cascade,
  group_code text not null references public.eat_group (code),
  grams_per_100g numeric not null check (grams_per_100g >= 0),
  primary key (food_id, group_code)
);

create table public.food_unit (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references public.food (id) on delete cascade,
  label text not null,
  grams numeric not null check (grams > 0),
  unique (food_id, label)
);
create index food_unit_food_id_idx on public.food_unit (food_id);

create table public.dish_breakdown (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  dish_food_id uuid not null references public.food (id),
  ingredient_food_id uuid not null references public.food (id),
  grams_per_100g_dish numeric not null check (grams_per_100g_dish > 0),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (owner_id, dish_food_id, ingredient_food_id)
);
create index dish_breakdown_dish_food_id_idx on public.dish_breakdown (dish_food_id);
create index dish_breakdown_ingredient_food_id_idx on public.dish_breakdown (ingredient_food_id);
create trigger dish_breakdown_set_updated_at before update on public.dish_breakdown
  for each row execute function public.set_updated_at();

-- RLS + grants (no delete/truncate for anyone but the service role)
alter table public.food_family enable row level security;
alter table public.food enable row level security;
alter table public.food_group_share enable row level security;
alter table public.food_unit enable row level security;
alter table public.dish_breakdown enable row level security;

revoke all on public.food_family, public.food, public.food_group_share,
  public.food_unit, public.dish_breakdown from anon, authenticated;
grant select on public.food_family to authenticated;
grant select, insert, update on public.food, public.food_group_share,
  public.food_unit, public.dish_breakdown to authenticated;
-- food_group_share/food_unit: owners also remove their own rows (child rows, no soft delete)
grant delete on public.food_group_share, public.food_unit to authenticated;

-- Same rule as food_select, as a definer function so food's own WITH CHECK can
-- test visibility without RLS self-recursion.
create function public.food_is_visible(fid uuid) returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.food f
    where f.id = fid
      and (f.visibility in ('shared', 'public') or f.owner_id = (select auth.uid()))
  )
$$;
revoke all on function public.food_is_visible(uuid) from public, anon;
grant execute on function public.food_is_visible(uuid) to authenticated;

create policy food_family_select on public.food_family
  for select to authenticated using (true);

create policy food_select on public.food for select to authenticated
  using (visibility in ('shared', 'public') or owner_id = (select auth.uid()));
create policy food_insert on public.food for insert to authenticated
  with check (visibility = 'private' and owner_id = (select auth.uid())
    and (derived_from is null or public.food_is_visible(derived_from)));
create policy food_update on public.food for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (visibility = 'private' and owner_id = (select auth.uid())
    and (derived_from is null or public.food_is_visible(derived_from)));

-- Child tables: read if parent visible (RLS on food applies in the subquery),
-- write if the parent is owned by the caller.
create policy food_group_share_select on public.food_group_share for select to authenticated
  using (exists (select 1 from public.food f where f.id = food_id));
create policy food_group_share_insert on public.food_group_share for insert to authenticated
  with check (exists (select 1 from public.food f where f.id = food_id and f.owner_id = (select auth.uid())));
create policy food_group_share_update on public.food_group_share for update to authenticated
  using (exists (select 1 from public.food f where f.id = food_id and f.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.food f where f.id = food_id and f.owner_id = (select auth.uid())));
create policy food_group_share_delete on public.food_group_share for delete to authenticated
  using (exists (select 1 from public.food f where f.id = food_id and f.owner_id = (select auth.uid())));

create policy food_unit_select on public.food_unit for select to authenticated
  using (exists (select 1 from public.food f where f.id = food_id));
create policy food_unit_insert on public.food_unit for insert to authenticated
  with check (exists (select 1 from public.food f where f.id = food_id and f.owner_id = (select auth.uid())));
create policy food_unit_update on public.food_unit for update to authenticated
  using (exists (select 1 from public.food f where f.id = food_id and f.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.food f where f.id = food_id and f.owner_id = (select auth.uid())));
create policy food_unit_delete on public.food_unit for delete to authenticated
  using (exists (select 1 from public.food f where f.id = food_id and f.owner_id = (select auth.uid())));

-- dish_breakdown: owner only; referenced foods must be visible to the caller
-- (FK checks bypass RLS, so this stops probing/linking to others' private foods).
create policy dish_breakdown_select on public.dish_breakdown for select to authenticated
  using (owner_id = (select auth.uid()));
create policy dish_breakdown_insert on public.dish_breakdown for insert to authenticated
  with check (owner_id = (select auth.uid())
    and exists (select 1 from public.food d where d.id = dish_food_id)
    and exists (select 1 from public.food i where i.id = ingredient_food_id));
create policy dish_breakdown_update on public.dish_breakdown for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid())
    and exists (select 1 from public.food d where d.id = dish_food_id)
    and exists (select 1 from public.food i where i.id = ingredient_food_id));
