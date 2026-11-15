begin;
create extension if not exists pgtap with schema extensions;
\ir ../helpers/helpers.psql
select plan(46);

select tests.create_user('a@example.test') as a \gset
select tests.create_user('b@example.test') as b \gset
select tests.create_user('c@example.test') as c \gset

-- fixtures as postgres: shared food, A private food, B private food + unit + cupboard item
insert into public.food (id, name, source, source_ref, visibility, kcal_per_100g)
values ('00000000-0000-0000-0000-0000000000f1', 'Oats (CoFID)', 'cofid', '11-001', 'shared', 372);
insert into public.food (id, name, source, visibility, owner_id) values
  ('00000000-0000-0000-0000-0000000000a1', 'A food', 'user', 'private', :'a'),
  ('00000000-0000-0000-0000-0000000000b1', 'B secret', 'user', 'private', :'b');
insert into public.food_unit (id, food_id, label, grams)
values ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000b1', 'B tub', 100);
insert into public.cupboard_item (id, owner_id, food_id, quantity_g)
values ('00000000-0000-0000-0000-0000000000c2', :'b', '00000000-0000-0000-0000-0000000000b1', 500);
insert into public.log_entry (id, owner_id, day, slot, food_id, quantity_g, snapshot)
values ('00000000-0000-0000-0000-0000000000d2', :'b', '2026-11-15', 'lunch', '00000000-0000-0000-0000-0000000000b1', 50, '{}');
-- B's own rows exist in every table the cross-user update tests touch, so B-side
-- isolation is tested against A's rows only (A ids below are distinct)

-- A inserts one row per table
select tests.act_as(:'a'::uuid);
insert into public.profile_targets (kcal_target, protein_floor_g, fibre_floor_g) values (2000, 60, 30);
insert into public.profile_group_setting (group_code) values ('vegetables');
insert into public.plan (id, effective_from, groups, expected)
values ('00000000-0000-0000-0000-0000000000a5', '2026-11-15', '{"vegetables":2}', '{}');
insert into public.log_entry (id, day, slot, food_id, quantity_g, snapshot)
values ('00000000-0000-0000-0000-0000000000a6', '2026-11-15', 'breakfast', '00000000-0000-0000-0000-0000000000f1', 40, '{}');
insert into public.cupboard_item (id, food_id, quantity_g)
values ('00000000-0000-0000-0000-0000000000a7', '00000000-0000-0000-0000-0000000000f1', 400);
insert into public.cupboard_movement (id, cupboard_item_id, food_id, reason, quantity_g, log_entry_id)
values ('00000000-0000-0000-0000-0000000000a8', '00000000-0000-0000-0000-0000000000a7', '00000000-0000-0000-0000-0000000000f1', 'bought', 400, null);
insert into public.shopping_item (id, food_id, quantity_g)
values ('00000000-0000-0000-0000-0000000000a9', '00000000-0000-0000-0000-0000000000f1', 100);
insert into public.weight_entry (id, day, kg) values ('00000000-0000-0000-0000-0000000000aa', '2026-11-15', 80);

-- owner_id_defaults_to_caller
select results_eq($$select count(*)::int from public.weight_entry where owner_id = '$$ || :'a' || $$'::uuid$$,
                  array[1], 'owner_id_defaults_to_caller');
reset role;

-- owner_isolation_<table>: B sees 0 rows and cannot update A's
select tests.act_as(:'b'::uuid);
select results_eq($$select count(*)::int from public.profile_targets$$, array[0], 'owner_isolation_profile_targets: B sees 0');
select results_eq($$with u as (update public.profile_targets set kcal_target = 1000 returning 1) select count(*)::int from u$$, array[0], 'owner_isolation_profile_targets: B update empty');
select results_eq($$select count(*)::int from public.profile_group_setting$$, array[0], 'owner_isolation_profile_group_setting: B sees 0');
select results_eq($$with u as (update public.profile_group_setting set status = 'excluded' returning 1) select count(*)::int from u$$, array[0], 'owner_isolation_profile_group_setting: B update empty');
select results_eq($$select count(*)::int from public.plan$$, array[0], 'owner_isolation_plan: B sees 0');
select results_eq($$with u as (update public.plan set groups = '{}' returning 1) select count(*)::int from u$$, array[0], 'owner_isolation_plan: B update empty');
select results_eq($$select count(*)::int from public.log_entry where id <> '00000000-0000-0000-0000-0000000000d2'$$, array[0], 'owner_isolation_log_entry: B sees 0 of As');
select results_eq($$with u as (update public.log_entry set quantity_g = 1 where id = '00000000-0000-0000-0000-0000000000a6' returning 1) select count(*)::int from u$$, array[0], 'owner_isolation_log_entry: B update empty');
select results_eq($$select count(*)::int from public.cupboard_item where id <> '00000000-0000-0000-0000-0000000000c2'$$, array[0], 'owner_isolation_cupboard_item: B sees 0 of As');
select results_eq($$with u as (update public.cupboard_item set quantity_g = 1 where id = '00000000-0000-0000-0000-0000000000a7' returning 1) select count(*)::int from u$$, array[0], 'owner_isolation_cupboard_item: B update empty');
select results_eq($$select count(*)::int from public.cupboard_movement$$, array[0], 'owner_isolation_cupboard_movement: B sees 0');
select throws_ok($$update public.cupboard_movement set quantity_g = 1 returning 1$$, '42501', null, 'owner_isolation_cupboard_movement: B update denied');
select results_eq($$select count(*)::int from public.shopping_item$$, array[0], 'owner_isolation_shopping_item: B sees 0');
select results_eq($$with u as (update public.shopping_item set quantity_g = 1 returning 1) select count(*)::int from u$$, array[0], 'owner_isolation_shopping_item: B update empty');
select results_eq($$select count(*)::int from public.weight_entry$$, array[0], 'owner_isolation_weight_entry: B sees 0');
select results_eq($$with u as (update public.weight_entry set kg = 50 returning 1) select count(*)::int from u$$, array[0], 'owner_isolation_weight_entry: B update empty');

-- B cannot link to A's rows either (movement -> A's item / A's log entry)
select throws_ok($$insert into public.cupboard_movement (cupboard_item_id, food_id, reason, quantity_g) values ('00000000-0000-0000-0000-0000000000a7','00000000-0000-0000-0000-0000000000f1','went_off',1)$$,
                 '42501', null, 'B cannot add movement to A cupboard_item');
select throws_ok($$insert into public.cupboard_movement (food_id, reason, quantity_g, log_entry_id) values ('00000000-0000-0000-0000-0000000000f1','eaten_logged',1,'00000000-0000-0000-0000-0000000000a6')$$,
                 '42501', null, 'B cannot add movement to A log_entry');
reset role;

-- cannot_insert_for_other_user (one per owned table style)
select tests.act_as(:'a'::uuid);
select throws_ok($$insert into public.weight_entry (owner_id, day, kg) values ('$$ || :'b' || $$', '2026-11-14', 70)$$, '42501', null, 'cannot_insert_for_other_user: weight_entry');
select throws_ok($$insert into public.profile_targets (owner_id, kcal_target, protein_floor_g, fibre_floor_g) values ('$$ || :'b' || $$', 2000, 1, 1)$$, '42501', null, 'cannot_insert_for_other_user: profile_targets');
select throws_ok($$insert into public.profile_group_setting (owner_id, group_code) values ('$$ || :'b' || $$', 'vegetables')$$, '42501', null, 'cannot_insert_for_other_user: profile_group_setting');
select throws_ok($$insert into public.cupboard_movement (owner_id, food_id, reason, quantity_g) values ('$$ || :'b' || $$', '00000000-0000-0000-0000-0000000000f1', 'bought', 1)$$, '42501', null, 'cannot_insert_for_other_user: cupboard_movement');
-- cannot hand own row to B via update
select throws_ok($$update public.weight_entry set owner_id = '$$ || :'b' || $$' where id = '00000000-0000-0000-0000-0000000000aa'$$, '42501', null, 'cannot hand row to other user');

-- cannot_reference_other_users_rows
select throws_ok($$insert into public.log_entry (day, slot, food_id, quantity_g, snapshot) values ('2026-11-15','lunch','00000000-0000-0000-0000-0000000000b1',10,'{}')$$,
                 '42501', null, 'cannot_reference_other_users_rows: log_entry with B food');
select throws_ok($$insert into public.cupboard_item (food_id, quantity_g) values ('00000000-0000-0000-0000-0000000000b1',10)$$,
                 '42501', null, 'cannot_reference_other_users_rows: cupboard_item with B food');
select throws_ok($$insert into public.shopping_item (food_id, quantity_g) values ('00000000-0000-0000-0000-0000000000b1',10)$$,
                 '42501', null, 'cannot_reference_other_users_rows: shopping_item with B food');
select throws_ok($$insert into public.cupboard_movement (food_id, reason, quantity_g) values ('00000000-0000-0000-0000-0000000000b1','bought',10)$$,
                 '42501', null, 'cannot_reference_other_users_rows: movement with B food');
select throws_ok($$insert into public.log_entry (day, slot, food_id, quantity_g, unit_id, snapshot) values ('2026-11-15','lunch','00000000-0000-0000-0000-0000000000f1',10,'00000000-0000-0000-0000-0000000000e2','{}')$$,
                 '42501', null, 'cannot_reference_other_users_rows: log_entry with B unit');
select throws_ok($$insert into public.shopping_item (food_id, quantity_g, unit_id) values ('00000000-0000-0000-0000-0000000000f1',10,'00000000-0000-0000-0000-0000000000e2')$$,
                 '42501', null, 'cannot_reference_other_users_rows: shopping_item with B unit');
select throws_ok($$insert into public.cupboard_movement (cupboard_item_id, food_id, reason, quantity_g) values ('00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-0000000000f1','bought',10)$$,
                 '42501', null, 'cannot_reference_other_users_rows: movement with B cupboard_item');
select throws_ok($$insert into public.cupboard_movement (food_id, reason, quantity_g, log_entry_id) values ('00000000-0000-0000-0000-0000000000f1','bought',10,'00000000-0000-0000-0000-0000000000d2')$$,
                 '42501', null, 'cannot_reference_other_users_rows: movement with B log_entry');
-- update path too: repoint own log_entry at B's food
select throws_ok($$update public.log_entry set food_id = '00000000-0000-0000-0000-0000000000b1' where id = '00000000-0000-0000-0000-0000000000a6'$$,
                 '42501', null, 'cannot_reference_other_users_rows: log_entry update to B food');

-- movement_is_append_only
select throws_ok($$update public.cupboard_movement set quantity_g = 1 where id = '00000000-0000-0000-0000-0000000000a8'$$, '42501', null, 'movement_is_append_only: update denied');
select throws_ok($$delete from public.cupboard_movement where id = '00000000-0000-0000-0000-0000000000a8'$$, '42501', null, 'movement_is_append_only: delete denied');
reset role;
select results_eq($$select quantity_g from public.cupboard_movement where id = '00000000-0000-0000-0000-0000000000a8'$$, array[400::numeric], 'movement_is_append_only: row unchanged');

-- no hard delete on soft-delete tables; truncate blocked
select tests.act_as(:'a'::uuid);
select throws_ok($$delete from public.log_entry where id = '00000000-0000-0000-0000-0000000000a6'$$, '42501', null, 'no hard delete: log_entry');
select throws_ok($$truncate public.log_entry$$, '42501', null, 'truncate blocked');
reset role;

-- food_hard_delete_blocked_when_referenced
select throws_ok($$delete from public.food where id = '00000000-0000-0000-0000-0000000000f1'$$, '23503', null, 'food_hard_delete_blocked_when_referenced');

-- colour_split_must_sum_to_one
select throws_ok($$update public.profile_targets set colour_split = '{"green":0.5,"yellow":0.3,"orange":0.3}'$$, '23514', null, 'colour_split_must_sum_to_one');
select throws_ok($$update public.profile_targets set colour_split = '{"green":1}'$$, '23514', null, 'colour_split_requires_all_keys');

-- updated_at_moves_on_update
create temp table t0 as select updated_at from public.weight_entry where id = '00000000-0000-0000-0000-0000000000aa';
update public.weight_entry set kg = 79 where id = '00000000-0000-0000-0000-0000000000aa';
select ok((select w.updated_at > t0.updated_at from public.weight_entry w, t0 where w.id = '00000000-0000-0000-0000-0000000000aa'), 'updated_at_moves_on_update');

-- one_weight_per_day
select throws_ok($$insert into public.weight_entry (owner_id, day, kg) values ('$$ || :'a' || $$', '2026-11-15', 81)$$, '23505', null, 'one_weight_per_day');

-- anon reads nothing
set local role anon;
select throws_ok($$select * from public.log_entry$$, '42501', null, 'anon_cannot_read_log_entry');
reset role;

-- user_account_delete_cascades
insert into public.food (id, name, source, visibility, owner_id)
values ('00000000-0000-0000-0000-0000000000c1', 'C food', 'user', 'private', :'c');
insert into public.food_unit (id, food_id, label, grams) values ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c1', 'c unit', 10);
insert into public.log_entry (id, owner_id, day, slot, food_id, quantity_g, unit_id, snapshot)
values ('00000000-0000-0000-0000-0000000000c4', :'c', '2026-11-15', 'dinner', '00000000-0000-0000-0000-0000000000c1', 10, '00000000-0000-0000-0000-0000000000c3', '{}');
insert into public.cupboard_item (id, owner_id, food_id, quantity_g) values ('00000000-0000-0000-0000-0000000000c5', :'c', '00000000-0000-0000-0000-0000000000c1', 10);
insert into public.cupboard_movement (owner_id, cupboard_item_id, food_id, reason, quantity_g, log_entry_id)
values (:'c', '00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000c1', 'eaten_logged', 10, '00000000-0000-0000-0000-0000000000c4');
insert into public.shopping_item (owner_id, food_id, quantity_g, unit_id) values (:'c', '00000000-0000-0000-0000-0000000000c1', 10, '00000000-0000-0000-0000-0000000000c3');
select lives_ok($$delete from auth.users where id = '$$ || :'c' || $$'$$, 'user_account_delete_cascades: delete succeeds');
select results_eq($$select (select count(*) from public.food where id = '00000000-0000-0000-0000-0000000000c1')
  + (select count(*) from public.log_entry where owner_id = '$$ || :'c' || $$')
  + (select count(*) from public.cupboard_item where owner_id = '$$ || :'c' || $$')
  + (select count(*) from public.cupboard_movement where owner_id = '$$ || :'c' || $$')
  + (select count(*) from public.shopping_item where owner_id = '$$ || :'c' || $$')$$,
  array[0::bigint], 'user_account_delete_cascades: nothing left');

select * from finish();
rollback;
