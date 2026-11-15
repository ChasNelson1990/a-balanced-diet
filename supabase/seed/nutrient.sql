-- reference_intake: UK legal Reference Intakes / NRVs for adults, retained Regulation (EU) No 1169/2011
-- Annex XIII (Part A vitamins/minerals, Part B energy and macronutrients), as applied in the UK.
insert into public.nutrient (code, name, unit, is_label_set, reference_intake, reference_source) values
  ('energy_kcal', 'Energy', 'kcal', true, 2000, 'UK Reference Intake, retained Reg (EU) 1169/2011 Annex XIII Part B (8400 kJ / 2000 kcal)'),
  ('fat', 'Fat', 'g', true, 70, 'UK Reference Intake, retained Reg (EU) 1169/2011 Annex XIII Part B'),
  ('saturates', 'Saturates', 'g', true, 20, 'UK Reference Intake, retained Reg (EU) 1169/2011 Annex XIII Part B'),
  ('carbohydrate', 'Carbohydrate', 'g', true, 260, 'UK Reference Intake, retained Reg (EU) 1169/2011 Annex XIII Part B'),
  ('sugars', 'Sugars', 'g', true, 90, 'UK Reference Intake, retained Reg (EU) 1169/2011 Annex XIII Part B (total sugars)'),
  ('fibre_aoac', 'Fibre (AOAC)', 'g', true, 30, 'SACN Carbohydrates and Health report (2015): 30 g/day for adults, AOAC method; no Annex XIII value'),
  ('protein', 'Protein', 'g', true, 50, 'UK Reference Intake, retained Reg (EU) 1169/2011 Annex XIII Part B'),
  ('salt', 'Salt', 'g', true, 6, 'UK Reference Intake, retained Reg (EU) 1169/2011 Annex XIII Part B'),
  ('vitamin_b12', 'Vitamin B12', 'µg', false, 2.5, 'UK NRV, retained Reg (EU) 1169/2011 Annex XIII Part A'),
  ('iron', 'Iron', 'mg', false, 14, 'UK NRV, retained Reg (EU) 1169/2011 Annex XIII Part A'),
  ('calcium', 'Calcium', 'mg', false, 800, 'UK NRV, retained Reg (EU) 1169/2011 Annex XIII Part A'),
  ('iodine', 'Iodine', 'µg', false, 150, 'UK NRV, retained Reg (EU) 1169/2011 Annex XIII Part A'),
  ('vitamin_d', 'Vitamin D', 'µg', false, 5, 'UK NRV, retained Reg (EU) 1169/2011 Annex XIII Part A'),
  ('zinc', 'Zinc', 'mg', false, 10, 'UK NRV, retained Reg (EU) 1169/2011 Annex XIII Part A'),
  ('folate', 'Folate', 'µg', false, 200, 'UK NRV for folic acid, retained Reg (EU) 1169/2011 Annex XIII Part A'),
  ('omega3_total', 'Omega-3 (total)', 'g', false, null, 'No UK RNI or legal Reference Intake exists for total omega-3; left NULL deliberately');
