begin;
create extension if not exists pgtap with schema extensions;
\ir ../helpers/helpers.psql
select plan(25);

select tests.create_user('a@example.test') as a \gset
select tests.create_user('b@example.test') as b \gset

-- shared CoFID food, inserted as postgres (service-level)
insert into public.food (id, name, source, source_ref, visibility, kcal_per_100g)
values ('00000000-0000-0000-0000-0000000000f1', 'Oats (CoFID)', 'cofid', '11-001', 'shared', 372);

-- private_food_visible_only_to_owner
select tests.act_as(:'a'::uuid);
insert into public.food (id, name, source, visibility)
values ('00000000-0000-0000-0000-0000000000a1', 'A secret', 'user', 'private');
select results_eq($$select count(*)::int from public.food where id = '00000000-0000-0000-0000-0000000000a1'$$,
                  array[1], 'private_food_visible_only_to_owner: owner sees it');
select results_eq($$select owner_id = '$$ || :'a' || $$'::uuid from public.food where id = '00000000-0000-0000-0000-0000000000a1'$$,
                  array[true], 'owner_id defaults to auth.uid()');
reset role;
select tests.act_as(:'b'::uuid);
select results_eq($$select count(*)::int from public.food where id = '00000000-0000-0000-0000-0000000000a1'$$,
                  array[0], 'private_food_visible_only_to_owner: other user sees 0');

-- shared_food_visible_to_all
select results_eq($$select count(*)::int from public.food where id = '00000000-0000-0000-0000-0000000000f1'$$,
                  array[1], 'shared_food_visible_to_all: B sees shared');
reset role;
select tests.act_as(:'a'::uuid);
select results_eq($$select count(*)::int from public.food where id = '00000000-0000-0000-0000-0000000000f1'$$,
                  array[1], 'shared_food_visible_to_all: A sees shared');

-- user_cannot_insert_shared
select throws_ok($$insert into public.food (name, source, visibility, owner_id) values ('x','user','shared',null)$$,
                 '42501', null, 'user_cannot_insert_shared');
select throws_ok($$insert into public.food (name, source, visibility, owner_id) values ('x','user','public',null)$$,
                 '42501', null, 'user_cannot_insert_public');
select throws_ok($$insert into public.food (name, source, visibility, owner_id) values ('x','user','private','$$ || :'b' || $$')$$,
                 '42501', null, 'user_cannot_insert_for_other_owner');

-- food_visibility_cannot_escalate
select throws_ok($$update public.food set visibility = 'shared', owner_id = null where id = '00000000-0000-0000-0000-0000000000a1'$$,
                 '42501', null, 'food_visibility_cannot_escalate: promote');
select throws_ok($$update public.food set owner_id = '$$ || :'b' || $$' where id = '00000000-0000-0000-0000-0000000000a1'$$,
                 '42501', null, 'food_visibility_cannot_escalate: hand to B');

-- user_cannot_edit_shared_food
update public.food set name = 'pwned' where id = '00000000-0000-0000-0000-0000000000f1';
reset role;
select results_eq($$select name from public.food where id = '00000000-0000-0000-0000-0000000000f1'$$,
                  array['Oats (CoFID)'], 'user_cannot_edit_shared_food: 0 rows affected');

-- group_share_follows_parent
select tests.act_as(:'a'::uuid);
select lives_ok($$insert into public.food_group_share (food_id, group_code, grams_per_100g) values ('00000000-0000-0000-0000-0000000000a1','vegetables',50)$$,
                'group_share_follows_parent: own private food ok');
select throws_ok($$insert into public.food_group_share (food_id, group_code, grams_per_100g) values ('00000000-0000-0000-0000-0000000000f1','vegetables',50)$$,
                 '42501', null, 'group_share_follows_parent: shared food rejected');
select lives_ok($$insert into public.food_unit (food_id, label, grams) values ('00000000-0000-0000-0000-0000000000a1','1 slice',30)$$,
                'food_unit: own private food ok');
select throws_ok($$insert into public.food_unit (food_id, label, grams) values ('00000000-0000-0000-0000-0000000000f1','1 cup',30)$$,
                 '42501', null, 'food_unit: shared food rejected');
reset role;
select tests.act_as(:'b'::uuid);
select results_eq($$select (select count(*) from public.food_group_share) + (select count(*) from public.food_unit)$$,
                  array[0::bigint], 'B cannot see shares/units of A private food');
select throws_ok($$insert into public.food_unit (food_id, label, grams) values ('00000000-0000-0000-0000-0000000000a1','x',1)$$,
                 '42501', null, 'B cannot add unit to A food');

-- dish_breakdown: owner only, and only over visible foods
reset role;
select tests.act_as(:'a'::uuid);
select lives_ok($$insert into public.dish_breakdown (dish_food_id, ingredient_food_id, grams_per_100g_dish) values ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000f1',40)$$,
                'dish_breakdown: owner inserts');
reset role;
select tests.act_as(:'b'::uuid);
select results_eq($$select count(*)::int from public.dish_breakdown$$, array[0], 'dish_breakdown: other user sees 0');
select throws_ok($$insert into public.dish_breakdown (dish_food_id, ingredient_food_id, grams_per_100g_dish) values ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000f1',40)$$,
                 '42501', null, 'dish_breakdown: B cannot reference A private food');

-- food_hard_delete_blocked (no delete grant/policy), no truncate
reset role;
select tests.act_as(:'a'::uuid);
select throws_ok($$delete from public.food where id = '00000000-0000-0000-0000-0000000000a1'$$,
                 '42501', null, 'food_hard_delete_blocked');
select throws_ok($$truncate public.food cascade$$, '42501', null, 'truncate blocked');
select throws_ok($$insert into public.food_family (name, reference_state) values ('f','raw')$$,
                 '42501', null, 'food_family not writable by authenticated');

-- wholegrain_fraction_bounds
select throws_ok($$insert into public.food (name, source, visibility, wholegrain_fraction) values ('w','user','private',1.2)$$,
                 '23514', null, 'wholegrain_fraction_bounds');
reset role;

-- anon_cannot_read_food
set local role anon;
select throws_ok($$select * from public.food$$, '42501', null, 'anon_cannot_read_food');
reset role;

select * from finish();
rollback;
