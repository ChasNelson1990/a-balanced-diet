-- The server sets updated_at on insert as well as update. Otherwise a row created
-- offline keeps the device's time, and a device that pulled in the meantime never
-- fetches it. (Restores are unaffected: they load data with triggers off.)
create or replace trigger food_set_updated_at before insert or update on public.food
  for each row execute function public.set_updated_at();
create or replace trigger dish_breakdown_set_updated_at before insert or update on public.dish_breakdown
  for each row execute function public.set_updated_at();

-- 20261115130000 gained this revoke after it was applied to the hosted database, so
-- repeat it here. PUBLIC matters: anon inherits execute from it.
revoke all on function public.set_updated_at() from public, anon;
