begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

-- Exactly the 16 groups of Table 1, EAT-Lancet 2025 (full paper, p. 9)
select results_eq('select count(*)::int from public.eat_group', array[16], '16 eat groups');
select results_eq($$select default_per_day, energy_share_min, energy_share_max, range_basis::text, weight_basis::text
                    from public.eat_group where code = 'whole_grains'$$,
                  $$values (210::numeric, 0.20::numeric, 0.50::numeric, 'energy_share', 'dry')$$,
                  'whole grains');
select results_eq($$select range_min, range_max, weight_basis::text from public.eat_group where code = 'dairy'$$,
                  $$values (0::numeric, 500::numeric, 'milk_equivalent')$$, 'dairy');
select results_eq($$select unit::text, range_max from public.eat_group where code = 'sodium'$$,
                  $$values ('mg', 2000::numeric)$$, 'sodium');
select results_eq($$select score_type::text from public.eat_group where code in ('vegetables','fruits','legumes','whole_grains','nuts','unsaturated_oils') group by 1$$,
                  $$values ('shortfall')$$, 'shortfall groups');
select results_eq('select count(*)::int from public.nutrient', array[16], '16 nutrients');
select results_eq($$select reference_intake from public.nutrient where code = 'omega3_total'$$,
                  $$values (null::numeric)$$, 'omega3 has no reference intake (NULL, not 0)');
select results_eq('select count(*)::int from public.scottish_baseline', array[1], '1 baseline row');
select results_eq('select count(*)::int from public.co2e_factor', array[0], 'co2e_factor empty');

-- authenticated can read, anon cannot
set local role authenticated;
select results_eq('select count(*)::int from public.eat_group', array[16], 'authenticated reads 16 groups');
select throws_ok($$insert into public.eat_group (code,name,unit,weight_basis,score_type,sort_order) values ('x','x','g','dry','excess',99)$$,
                 '42501', null, 'authenticated cannot write');
reset role;

set local role anon;
select throws_ok('select * from public.eat_group', '42501', null, 'anon cannot read');
reset role;

select * from finish();
rollback;
