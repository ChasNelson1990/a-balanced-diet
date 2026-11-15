begin;
create extension if not exists pgtap with schema extensions;
select plan(1);
select has_extension('pgtap', 'pgtap is available');
select * from finish();
rollback;
