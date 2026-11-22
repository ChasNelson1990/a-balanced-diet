begin;
create extension if not exists pgtap with schema extensions;
\ir ../helpers/helpers.psql
select plan(26);

select tests.create_user('a@example.test') as a \gset
select tests.create_user('b@example.test') as b \gset

-- set_and_has_secret
select tests.act_as(:'a'::uuid);
select lives_ok(
  $$select public.set_my_secret('anthropic_api_key', 'sk-ant-test-0123456789abcdef')$$,
  'set_and_has_secret: A can set a secret');
select is(public.has_my_secret('anthropic_api_key'), true, 'set_and_has_secret: A has a secret');
select tests.act_as(:'b'::uuid);
select is(public.has_my_secret('anthropic_api_key'), false, 'set_and_has_secret: B does not see A''s secret');

-- validation, and error messages never carry the value
select throws_ok(
  $$select public.set_my_secret('anthropic_api_key', 'zzSECRETMARKERzzzzz')$$,
  'P0001', null, 'short value rejected');
select throws_ok(
  $$select public.set_my_secret('openai_api_key', 'sk-ant-test-0123456789abcdef')$$,
  'P0001', null, 'unknown kind rejected');
select lives_ok($q$
  do $d$
  begin
    begin
      perform public.set_my_secret('anthropic_api_key', 'zzSECRETMARKERzzzzz');
    exception when others then
      if sqlerrm like '%SECRETMARKER%' then raise exception 'value leaked in error'; end if;
    end;
  end $d$$q$, 'error message does not contain the value');
select is(public.has_my_secret('anthropic_api_key'), false, 'rejected calls store nothing');

-- secret_value_never_selectable (as A)
select tests.act_as(:'a'::uuid);
select is((select count(*)::int from public.user_secret), 0, 'secret_value_never_selectable: user_secret shows 0 rows');
select throws_ok('select * from vault.decrypted_secrets', '42501', null, 'secret_value_never_selectable: vault view denied');
select throws_ok('select * from vault.secrets', '42501', null, 'vault.secrets denied');
select throws_ok(
  format('select private.get_user_secret(%L, %L)', :'a', 'anthropic_api_key'),
  '42501', null, 'secret_value_never_selectable: private getter denied to owner');
select throws_ok(
  format('select private.get_user_secret(%L, %L)', :'b', 'anthropic_api_key'),
  '42501', null, 'private getter denied to other users');
select throws_ok('insert into public.user_secret (owner_id, kind, vault_secret_id) values (gen_random_uuid(), ''anthropic_api_key'', gen_random_uuid())',
  '42501', null, 'authenticated cannot write user_secret directly');

-- anon_cannot_call
reset role;
set local role anon;
select throws_ok(
  $$select public.set_my_secret('anthropic_api_key', 'sk-ant-test-0123456789abcdef')$$,
  '42501', null, 'anon_cannot_call: set_my_secret');
select throws_ok($$select public.has_my_secret('anthropic_api_key')$$,
  '42501', null, 'anon cannot call has_my_secret');

-- service_role_can_read, and update replaces the value
reset role;
set local role service_role;
select is(private.get_user_secret(:'a'::uuid, 'anthropic_api_key'), 'sk-ant-test-0123456789abcdef',
  'service_role_can_read: returns the original string');
reset role;
select tests.act_as(:'a'::uuid);
select public.set_my_secret('anthropic_api_key', 'sk-ant-test-replacement-value-1');
reset role;
set local role service_role;
select is(private.get_user_secret(:'a'::uuid, 'anthropic_api_key'), 'sk-ant-test-replacement-value-1',
  'second set replaces the value');
select is(private.get_user_secret(:'b'::uuid, 'anthropic_api_key'), null, 'service_role gets null for missing secret');
reset role;
select is((select count(*)::int from vault.secrets where name = format('user:%s:anthropic_api_key', :'a')), 1,
  'exactly one vault row after two sets');

-- clear_secret
select tests.act_as(:'b'::uuid);
select public.set_my_secret('anthropic_api_key', 'sk-ant-test-b-key-0123456789');
select tests.act_as(:'a'::uuid);
select public.clear_my_secret('anthropic_api_key');
select is(public.has_my_secret('anthropic_api_key'), false, 'clear_secret: has_my_secret false');
reset role;
select is((select count(*)::int from vault.secrets where name = format('user:%s:anthropic_api_key', :'a')), 0,
  'clear_secret: no vault row remains');
select tests.act_as(:'b'::uuid);
select is(public.has_my_secret('anthropic_api_key'), true, 'clear by A leaves B untouched');

-- account_delete_removes_vault_secret
reset role;
delete from auth.users where id = :'b'::uuid;
select is((select count(*)::int from vault.secrets where name = format('user:%s:anthropic_api_key', :'b')), 0,
  'account_delete_removes_vault_secret');

-- ACLs
select is((select array_agg(g order by g) from (
    select grantee::regrole::text g from aclexplode((select proacl from pg_proc where oid = 'public.set_my_secret(text,text)'::regprocedure))
    where privilege_type = 'EXECUTE') s),
  array['authenticated','postgres'], 'set_my_secret EXECUTE only authenticated (+owner)');
select is((select array_agg(g order by g) from (
    select grantee::regrole::text g from aclexplode((select proacl from pg_proc where oid = 'public.has_my_secret(text)'::regprocedure))
    where privilege_type = 'EXECUTE') s),
  array['authenticated','postgres'], 'has_my_secret EXECUTE only authenticated (+owner)');
select is((select array_agg(g order by g) from (
    select grantee::regrole::text g from aclexplode((select proacl from pg_proc where oid = 'private.get_user_secret(uuid,text)'::regprocedure))
    where privilege_type = 'EXECUTE') s),
  array['postgres','service_role'], 'get_user_secret EXECUTE only service_role (+owner)');

select * from finish();
rollback;
