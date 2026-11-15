-- Reference data: EAT-Lancet 2025 targets, nutrient reference intakes,
-- CO2e factors (filled by Plan 3) and Scottish baselines.
-- Only the service role / postgres writes; authenticated users read.
create type public.group_unit as enum ('g', 'mg');
create type public.range_basis as enum ('grams', 'energy_share');
create type public.weight_basis as enum ('as_eaten', 'dry', 'milk_equivalent');
create type public.score_type as enum ('shortfall', 'excess');

create table public.eat_group (
  code text primary key,
  name text not null,
  unit public.group_unit not null,
  default_per_day numeric,
  range_min numeric,
  range_max numeric,
  range_basis public.range_basis not null default 'grams',
  energy_share_min numeric,
  energy_share_max numeric,
  weight_basis public.weight_basis not null,
  score_type public.score_type not null,
  ref_kcal_per_day numeric,
  sort_order int not null
);

create table public.nutrient (
  code text primary key,
  name text not null,
  unit text not null check (unit in ('g', 'mg', 'µg', 'kcal')),
  is_label_set boolean not null,
  reference_intake numeric,
  reference_source text
);

create table public.co2e_factor (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  kg_co2e_per_kg numeric not null check (kg_co2e_per_kg >= 0),
  source text not null,
  system_boundary text,
  confidence text check (confidence in ('high', 'medium', 'low'))
);

create table public.scottish_baseline (
  code text primary key,
  value numeric not null,
  unit text not null,
  source text not null,
  year text not null,
  caveat text
);

do $$
declare t text;
begin
  foreach t in array array['eat_group', 'nutrient', 'co2e_factor', 'scottish_baseline'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create policy "authenticated can read" on public.%I for select to authenticated using (true)', t);
  end loop;
end $$;
