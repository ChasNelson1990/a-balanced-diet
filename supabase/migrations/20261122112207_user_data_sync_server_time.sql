-- The server sets updated_at on insert as well as update. Otherwise a row created
-- offline keeps the device's time, and a device that pulled in the meantime never
-- fetches it. (Restores are unaffected: they load data with triggers off.)
create or replace trigger profile_targets_set_updated_at before insert or update on public.profile_targets
  for each row execute function public.set_updated_at();
create or replace trigger profile_group_setting_set_updated_at before insert or update on public.profile_group_setting
  for each row execute function public.set_updated_at();
create or replace trigger plan_set_updated_at before insert or update on public.plan
  for each row execute function public.set_updated_at();
create or replace trigger log_entry_set_updated_at before insert or update on public.log_entry
  for each row execute function public.set_updated_at();
create or replace trigger cupboard_item_set_updated_at before insert or update on public.cupboard_item
  for each row execute function public.set_updated_at();
create or replace trigger cupboard_movement_set_updated_at before insert or update on public.cupboard_movement
  for each row execute function public.set_updated_at();
create or replace trigger shopping_item_set_updated_at before insert or update on public.shopping_item
  for each row execute function public.set_updated_at();
create or replace trigger weight_entry_set_updated_at before insert or update on public.weight_entry
  for each row execute function public.set_updated_at();
