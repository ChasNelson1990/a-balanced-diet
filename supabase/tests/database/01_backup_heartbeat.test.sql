begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

select has_table('public', 'backup_heartbeat', 'backup_heartbeat exists');
select col_is_unique('public', 'backup_heartbeat', 'run_id', 'run_id is unique');
select is(
  (select relrowsecurity from pg_class where oid = 'public.backup_heartbeat'::regclass),
  true,
  'RLS is enabled on backup_heartbeat'
);

insert into public.backup_heartbeat (run_id) values ('pgtap-run');

set local role authenticated;
select results_eq(
  $$ select count(*)::bigint from public.backup_heartbeat $$,
  $$ values (0::bigint) $$,
  'authenticated sees no heartbeat rows (RLS, no policies)'
);

select * from finish();
rollback;
