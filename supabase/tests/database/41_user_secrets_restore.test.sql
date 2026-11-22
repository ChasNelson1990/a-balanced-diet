begin;
create extension if not exists pgtap with schema extensions;
\ir ../helpers/helpers.psql
select plan(8);

select tests.create_user('a@example.test') as a \gset
select tests.create_user('b@example.test') as b \gset

select tests.act_as(:'a'::uuid);
select lives_ok($$select public.set_my_secret('anthropic_api_key', 'sk-ant-test-0123456789abcdef')$$, 'A sets a key');
select is(public.has_my_secret('anthropic_api_key'), true, 'has_my_secret true after set');

-- simulate a restore: user_secret survives in the dump, vault.secrets does not
reset role;
delete from vault.secrets where name = format('user:%s:anthropic_api_key', :'a');
select is((select count(*)::int from public.user_secret where owner_id = :'a'::uuid), 1, 'dangling user_secret row remains');

select tests.act_as(:'a'::uuid);
select is(public.has_my_secret('anthropic_api_key'), false, 'dangling row reads as false');
select lives_ok($$select public.set_my_secret('anthropic_api_key', 'sk-ant-test-after-restore-0001')$$,
  'set after restore succeeds');
select is(public.has_my_secret('anthropic_api_key'), true, 'has_my_secret true after re-set');

reset role;
set local role service_role;
select is(private.get_user_secret(:'a'::uuid, 'anthropic_api_key'), 'sk-ant-test-after-restore-0001',
  'service_role reads the new value');
reset role;
select is((select count(*)::int from vault.secrets where name = format('user:%s:anthropic_api_key', :'a')), 1,
  'exactly one vault row for the name');

select * from finish();
rollback;
