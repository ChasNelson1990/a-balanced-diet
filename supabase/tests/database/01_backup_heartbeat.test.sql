begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

select has_table('public', 'backup_heartbeat', 'backup_heartbeat exists');
select col_is_unique('public', 'backup_heartbeat', 'run_id', 'run_id is unique');
select is(
  (select relrowsecurity from pg_class where oid = 'public.backup_heartbeat'::regclass),
  true,
  'RLS is enabled on backup_heartbeat'
);

insert into public.backup_heartbeat (run_id) values ('pgtap-run');

-- Privileges are revoked from the API roles, so they get 42501 (and RLS with no
-- policies would return no rows even if they were granted).
set local role authenticated;
select throws_ok(
  $$ select count(*) from public.backup_heartbeat $$,
  '42501',
  null,
  'authenticated cannot read backup_heartbeat'
);
reset role;

set local role anon;
select throws_ok(
  $$ select count(*) from public.backup_heartbeat $$,
  '42501',
  null,
  'anon cannot read backup_heartbeat'
);
reset role;

select * from finish();
rollback;
