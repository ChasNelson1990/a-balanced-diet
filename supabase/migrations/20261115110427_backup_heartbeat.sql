-- Heartbeat row written by every nightly backup run. The backup script checks
-- that the run's id appears in the dump, proving the dump is fresh and real.
-- RLS on with no policies: only the postgres role (connection string) can use it.
create table public.backup_heartbeat (
  id bigint generated always as identity primary key,
  run_id text not null unique,
  created_at timestamptz not null default now()
);

alter table public.backup_heartbeat enable row level security;

-- Belt and braces: the API roles get no table privileges at all.
revoke all on public.backup_heartbeat from anon, authenticated;
