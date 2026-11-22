begin;
create extension if not exists pgtap with schema extensions;
\ir ../helpers/helpers.psql
select plan(8);

-- sync_insert_uses_server_time_<table>: a row created offline arrives with the device's old time
select tests.create_user('user-server-time@example.test') as a \gset
insert into public.food (id, name, source, visibility, owner_id)
values ('00000000-0000-0000-0000-00000000e001', 'Oats', 'cofid', 'shared', null);

select tests.act_as(:'a'::uuid);
insert into public.profile_targets (kcal_target, protein_floor_g, fibre_floor_g, updated_at)
values (1750, 80, 30, '2020-01-01');
insert into public.profile_group_setting (group_code, status, updated_at)
values ('poultry', 'excluded', '2020-01-01');
insert into public.plan (effective_from, groups, expected, updated_at)
values ('2026-11-22', '{}', '{}', '2020-01-01');
insert into public.log_entry (day, slot, food_id, quantity_g, snapshot, updated_at)
values ('2026-11-22', 'lunch', '00000000-0000-0000-0000-00000000e001', 40, '{}', '2020-01-01');
insert into public.cupboard_item (food_id, quantity_g, updated_at)
values ('00000000-0000-0000-0000-00000000e001', 500, '2020-01-01');
insert into public.cupboard_movement (food_id, reason, quantity_g, updated_at)
values ('00000000-0000-0000-0000-00000000e001', 'bought', 500, '2020-01-01');
insert into public.shopping_item (food_id, quantity_g, updated_at)
values ('00000000-0000-0000-0000-00000000e001', 500, '2020-01-01');
insert into public.weight_entry (day, kg, updated_at)
values ('2026-11-22', 70, '2020-01-01');

select ok((select updated_at >= now() from public.profile_targets), 'sync_insert_uses_server_time_profile_targets');
select ok((select updated_at >= now() from public.profile_group_setting), 'sync_insert_uses_server_time_profile_group_setting');
select ok((select updated_at >= now() from public.plan), 'sync_insert_uses_server_time_plan');
select ok((select updated_at >= now() from public.log_entry), 'sync_insert_uses_server_time_log_entry');
select ok((select updated_at >= now() from public.cupboard_item), 'sync_insert_uses_server_time_cupboard_item');
select ok((select updated_at >= now() from public.cupboard_movement), 'sync_insert_uses_server_time_cupboard_movement');
select ok((select updated_at >= now() from public.shopping_item), 'sync_insert_uses_server_time_shopping_item');
select ok((select updated_at >= now() from public.weight_entry), 'sync_insert_uses_server_time_weight_entry');
reset role;

select * from finish();
rollback;
