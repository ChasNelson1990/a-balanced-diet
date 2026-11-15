begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

-- Catalog-driven: new tables and functions in later plans are checked automatically.
select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p') and not c.relrowsecurity
$$, 'every public table has RLS enabled');

select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')
    and (has_table_privilege('anon', c.oid, 'select,insert,update,delete,truncate,references,trigger')
      or exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                 and has_column_privilege('anon', c.oid, a.attnum, 'select,insert,update,references')))
$$, 'anon has no privileges on any public table');

select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p') and has_table_privilege('authenticated', c.oid, 'truncate')
$$, 'authenticated has no TRUNCATE on any public table');

select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')
    and has_table_privilege('authenticated', c.oid, 'delete')
    and not exists (select 1 from pg_policy p where p.polrelid = c.oid and p.polcmd in ('d','*'))
$$, 'authenticated has DELETE only where a delete policy exists');

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
