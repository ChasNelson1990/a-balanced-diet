begin;
create extension if not exists pgtap with schema extensions;
\ir ../helpers/helpers.psql
select plan(6);

-- Catalog-driven, so synced tables added by later migrations are checked automatically.
-- tgtype bits: 1 = row, 2 = before, 4 = insert, 16 = update.
select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')
    and (select count(*) from pg_attribute a
         where a.attrelid = c.oid and not a.attisdropped and a.attname in ('updated_at','deleted_at')) = 2
    and not exists (select 1 from pg_trigger t
                    where t.tgrelid = c.oid and t.tgenabled <> 'D'
                      and t.tgfoid = 'public.set_updated_at()'::regprocedure
                      and (t.tgtype::int & 23) = 23)
$$, 'every synced table gets its updated_at from the server on insert and update');

-- sync_insert_uses_server_time: a device that was offline sends an old time
select tests.create_user('server-time@example.test') as a \gset
select tests.act_as(:'a'::uuid);
insert into public.food (id, name, source, visibility, updated_at)
values ('00000000-0000-0000-0000-00000000d001', 'Dal', 'user', 'private', '2020-01-01'),
       ('00000000-0000-0000-0000-00000000d002', 'Red lentils', 'user', 'private', '2099-01-01');
insert into public.dish_breakdown (dish_food_id, ingredient_food_id, grams_per_100g_dish, updated_at)
values ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000d002', 30, '2020-01-01');
select ok((select updated_at >= now() from public.food where id = '00000000-0000-0000-0000-00000000d001'),
          'sync_insert_uses_server_time: food, past client time');
select ok((select updated_at < now() + interval '1 hour' from public.food where id = '00000000-0000-0000-0000-00000000d002'),
          'sync_insert_uses_server_time: food, future client time');
select ok((select updated_at >= now() from public.dish_breakdown where dish_food_id = '00000000-0000-0000-0000-00000000d001'),
          'sync_insert_uses_server_time: dish_breakdown');
reset role;

-- restore_keeps_timestamps: backups load data with session_replication_role = replica
set local session_replication_role = replica;
insert into public.food (id, name, source, visibility, owner_id, updated_at)
values ('00000000-0000-0000-0000-00000000d003', 'Oats', 'cofid', 'shared', null, '2021-06-01 12:00:00+00');
set local session_replication_role = origin;
select is((select updated_at from public.food where id = '00000000-0000-0000-0000-00000000d003'),
          '2021-06-01 12:00:00+00'::timestamptz, 'restore_keeps_timestamps');

select ok(not has_function_privilege('anon', 'public.set_updated_at()', 'execute'),
          'anon cannot execute set_updated_at');

select * from finish();
rollback;
