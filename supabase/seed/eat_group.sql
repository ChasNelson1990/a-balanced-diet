-- EAT-Lancet 2025 Table 1 (full paper, p. 9)
insert into public.eat_group
  (code, name, unit, default_per_day, range_min, range_max, range_basis, energy_share_min, energy_share_max, weight_basis, score_type, ref_kcal_per_day, sort_order)
values
  ('whole_grains', 'Whole grains', 'g', 210, null, null, 'energy_share', 0.20, 0.50, 'dry', 'shortfall', 735, 1),
  ('starchy_roots', 'Tubers and starchy roots', 'g', 50, 0, 100, 'grams', null, null, 'as_eaten', 'excess', 50, 2),
  ('vegetables', 'Vegetables', 'g', 300, 200, 600, 'grams', null, null, 'as_eaten', 'shortfall', 95, 3),
  ('fruits', 'Fruits', 'g', 200, 100, 300, 'grams', null, null, 'as_eaten', 'shortfall', 145, 4),
  ('nuts', 'Tree nuts and peanuts', 'g', 50, 0, 75, 'grams', null, null, 'as_eaten', 'shortfall', 275, 5),
  ('legumes', 'Legumes', 'g', 75, 0, 150, 'grams', null, null, 'dry', 'shortfall', 275, 6),
  ('dairy', 'Milk or equivalents', 'g', 250, 0, 500, 'grams', null, null, 'milk_equivalent', 'excess', 145, 7),
  ('poultry', 'Chicken and other poultry', 'g', 30, 0, 60, 'grams', null, null, 'as_eaten', 'excess', 60, 8),
  ('fish', 'Fish and shellfish', 'g', 30, 0, 100, 'grams', null, null, 'as_eaten', 'excess', 25, 9),
  ('eggs', 'Eggs', 'g', 15, 0, 25, 'grams', null, null, 'as_eaten', 'excess', 20, 10),
  ('red_meat', 'Beef, pork or lamb', 'g', 15, 0, 30, 'grams', null, null, 'as_eaten', 'excess', 45, 11),
  ('unsaturated_oils', 'Unsaturated plant oils', 'g', 40, 20, 80, 'grams', null, null, 'as_eaten', 'shortfall', 355, 12),
  ('palm_coconut_oil', 'Palm and coconut oil', 'g', 6, 0, 8, 'grams', null, null, 'as_eaten', 'excess', 55, 13),
  ('animal_fats', 'Lard, tallow and butter', 'g', 5, 0, 10, 'grams', null, null, 'as_eaten', 'excess', null, 14),
  ('sugar', 'Sugar (added or free)', 'g', 30, 0, 30, 'grams', null, null, 'as_eaten', 'excess', 115, 15),
  ('sodium', 'Sodium', 'mg', null, 0, 2000, 'grams', null, null, 'as_eaten', 'excess', null, 16);
