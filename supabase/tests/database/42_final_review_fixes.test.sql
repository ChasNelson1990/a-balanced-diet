begin;
create extension if not exists pgtap with schema extensions;
\ir ../helpers/helpers.psql
select plan(5);

select tests.create_user('a@example.test') as a \gset
insert into public.food (id, name, source, visibility, owner_id)
values ('00000000-0000-0000-0000-0000000000f1', 'F', 'user', 'private', :'a');
insert into public.cupboard_item (id, owner_id, food_id, quantity_g)
values ('00000000-0000-0000-0000-0000000000c5', :'a', '00000000-0000-0000-0000-0000000000f1', 10);
insert into public.cupboard_movement (id, owner_id, cupboard_item_id, food_id, reason, quantity_g)
values ('00000000-0000-0000-0000-0000000000c6', :'a', '00000000-0000-0000-0000-0000000000c5',
        '00000000-0000-0000-0000-0000000000f1', 'went_off', 10);

select lives_ok($$delete from public.cupboard_item where id = '00000000-0000-0000-0000-0000000000c5'$$,
  'hard-deleting a cupboard item succeeds');
select is((select count(*)::int from public.cupboard_movement where id = '00000000-0000-0000-0000-0000000000c6'), 1,
  'movement history survives item delete');
select is((select cupboard_item_id from public.cupboard_movement where id = '00000000-0000-0000-0000-0000000000c6'), null,
  'movement cupboard_item_id set to null');
select ok('other' = any (enum_range(null::public.movement_reason)::text[]), 'movement_reason has other');
select is((select array_agg(g order by g) from (
    select grantee::regrole::text g from aclexplode((select proacl from pg_proc where oid = 'public.has_my_secret(text)'::regprocedure))
    where privilege_type = 'EXECUTE') s),
  array['authenticated','postgres'], 'has_my_secret EXECUTE only authenticated (+owner)');

select * from finish();
rollback;
