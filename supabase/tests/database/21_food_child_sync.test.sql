begin;
create extension if not exists pgtap with schema extensions;
\ir ../helpers/helpers.psql
select plan(21);

-- food_unit and food_group_share sync per row: updated_at + deleted_at, like every other table.
select has_column('public', 'food_unit', 'updated_at', 'food_unit has updated_at');
select has_column('public', 'food_unit', 'deleted_at', 'food_unit has deleted_at');
select has_column('public', 'food_group_share', 'updated_at', 'food_group_share has updated_at');
select has_column('public', 'food_group_share', 'deleted_at', 'food_group_share has deleted_at');
select has_index('public', 'food_unit', 'food_unit_updated_at_idx', 'food_unit has a sync pull index');
select has_index('public', 'food_group_share', 'food_group_share_updated_at_idx', 'food_group_share has a sync pull index');

select tests.create_user('child-sync@example.test') as a \gset
select tests.act_as(:'a'::uuid);
insert into public.food (id, name, source, visibility)
values ('00000000-0000-0000-0000-00000000c001', 'Sourdough', 'user', 'private');

-- child_insert_uses_server_time: an offline device's old time would hide the row from other devices' pulls
insert into public.food_unit (id, food_id, label, grams, updated_at)
values ('00000000-0000-0000-0000-00000000c0e1', '00000000-0000-0000-0000-00000000c001', 'slice', 40, '2020-01-01');
insert into public.food_group_share (food_id, group_code, grams_per_100g, updated_at)
values ('00000000-0000-0000-0000-00000000c001', 'whole_grains', 60, '2020-01-01');
select ok((select updated_at >= now() from public.food_unit where id = '00000000-0000-0000-0000-00000000c0e1'),
          'child_insert_uses_server_time: unit');
select ok((select updated_at >= now() from public.food_group_share where food_id = '00000000-0000-0000-0000-00000000c001'),
          'child_insert_uses_server_time: share');

-- child_update_moves_updated_at
select updated_at as unit_t0 from public.food_unit where id = '00000000-0000-0000-0000-00000000c0e1' \gset
select updated_at as share_t0 from public.food_group_share where food_id = '00000000-0000-0000-0000-00000000c001' \gset
update public.food_unit set grams = 45 where id = '00000000-0000-0000-0000-00000000c0e1';
update public.food_group_share set grams_per_100g = 65 where food_id = '00000000-0000-0000-0000-00000000c001';
select ok((select updated_at > :'unit_t0' from public.food_unit where id = '00000000-0000-0000-0000-00000000c0e1'),
          'child_update_moves_updated_at: unit');
select ok((select updated_at > :'share_t0' from public.food_group_share where food_id = '00000000-0000-0000-0000-00000000c001'),
          'child_update_moves_updated_at: share');

-- child_soft_delete_leaves_tombstone
select updated_at as unit_t1 from public.food_unit where id = '00000000-0000-0000-0000-00000000c0e1' \gset
select updated_at as share_t1 from public.food_group_share where food_id = '00000000-0000-0000-0000-00000000c001' \gset
update public.food_unit set deleted_at = clock_timestamp() where id = '00000000-0000-0000-0000-00000000c0e1';
update public.food_group_share set deleted_at = clock_timestamp() where food_id = '00000000-0000-0000-0000-00000000c001';
select ok((select deleted_at is not null and updated_at > :'unit_t1' from public.food_unit where id = '00000000-0000-0000-0000-00000000c0e1'),
          'child_soft_delete_leaves_tombstone: unit');
select ok((select deleted_at is not null and updated_at > :'share_t1' from public.food_group_share where food_id = '00000000-0000-0000-0000-00000000c001'),
          'child_soft_delete_leaves_tombstone: share');

-- child_hard_delete_blocked, even for the owner
select throws_ok($$delete from public.food_unit where id = '00000000-0000-0000-0000-00000000c0e1'$$,
                 '42501', null, 'child_hard_delete_blocked: unit');
select throws_ok($$delete from public.food_group_share where food_id = '00000000-0000-0000-0000-00000000c001'$$,
                 '42501', null, 'child_hard_delete_blocked: share');

-- deleted_child_can_be_readded
select lives_ok($$insert into public.food_unit (id, food_id, label, grams) values ('00000000-0000-0000-0000-00000000c0e2', '00000000-0000-0000-0000-00000000c001', 'slice', 42)$$,
                'deleted_child_can_be_readded: same unit label');
select throws_ok($$insert into public.food_unit (food_id, label, grams) values ('00000000-0000-0000-0000-00000000c001', 'slice', 43)$$,
                 '23505', null, 'live unit labels stay unique per food');
select lives_ok($$insert into public.food_group_share (food_id, group_code, grams_per_100g)
                  values ('00000000-0000-0000-0000-00000000c001', 'whole_grains', 70)
                  on conflict (food_id, group_code) do update
                    set food_id = excluded.food_id, group_code = excluded.group_code,
                        grams_per_100g = excluded.grams_per_100g, deleted_at = null$$,
                'deleted_child_can_be_readded: share by upsert, setting the key columns as PostgREST does');
select ok((select deleted_at is null and grams_per_100g = 70 from public.food_group_share where food_id = '00000000-0000-0000-0000-00000000c001'),
          'deleted_child_can_be_readded: share is live again');

-- child_key_is_immutable: changing a key would remove the old row without a tombstone
select throws_ok($$update public.food_group_share set group_code = 'legumes' where food_id = '00000000-0000-0000-0000-00000000c001'$$,
                 '23514', null, 'child_key_is_immutable: share group');
select throws_ok($$update public.food_unit set id = gen_random_uuid() where id = '00000000-0000-0000-0000-00000000c0e2'$$,
                 '23514', null, 'child_key_is_immutable: unit id');
reset role;

-- account deletion still cascades through soft-deleted children
delete from auth.users where id = :'a';
select results_eq($$select (select count(*) from public.food_unit where food_id = '00000000-0000-0000-0000-00000000c001')
                         + (select count(*) from public.food_group_share where food_id = '00000000-0000-0000-0000-00000000c001')$$,
                  array[0::bigint], 'account delete removes children, tombstones included');

select * from finish();
rollback;
