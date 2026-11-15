begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

-- Catalog-driven: new tables, views and functions in later plans are checked automatically.

-- Sanity: the guard must not pass vacuously against an empty schema.
select ok(
  (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p')) > 0,
  'at least one public table exists');

select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p') and not c.relrowsecurity
$$, 'every public table has RLS enabled');

select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p','v','m','f')
    and (has_table_privilege('anon', c.oid, 'select,insert,update,delete,truncate,references,trigger')
      or exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                 and has_column_privilege('anon', c.oid, a.attnum, 'select,insert,update,references')))
$$, 'anon has no privileges on any public table, view, matview or foreign table');

select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p') and has_table_privilege('authenticated', c.oid, 'truncate')
$$, 'authenticated has no TRUNCATE on any public table');

-- A DELETE grant is only acceptable with a DELETE (or ALL) policy that applies to
-- authenticated, either by name or through PUBLIC (role oid 0).
select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')
    and has_table_privilege('authenticated', c.oid, 'delete')
    and not exists (select 1 from pg_policy p
                    where p.polrelid = c.oid and p.polcmd in ('d','*')
                      and ('authenticated'::regrole::oid = any (p.polroles) or 0::oid = any (p.polroles)))
$$, 'authenticated has DELETE only where a delete policy for authenticated exists');

select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','private') and has_function_privilege('anon', p.oid, 'execute')
$$, 'no public/private function is EXECUTE-able by anon');

select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','private') and p.prosecdef
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%')
$$, 'every SECURITY DEFINER function in public/private sets search_path');

select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','private') and p.prosecdef
    and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%' and cfg <> 'search_path=""')
$$, 'SECURITY DEFINER search_path is empty');

select * from finish();
rollback;
