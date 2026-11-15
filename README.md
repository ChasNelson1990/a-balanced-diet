# a-balanced-diet

A personal diet-tracking progressive web app, backed by Supabase (Postgres, auth and row-level security). It helps track meals against a planetary-health diet using metric units only. See the [design spec](docs/superpowers/specs/2026-11-14-a-balanced-diet-design.md).

## Local development

Prerequisite: Docker must be running.

- `npm run db:start` starts the local Supabase stack.
- `npm run db:reset` rebuilds the local database from the migrations.
- `npm run db:test` runs the pgTAP tests in `supabase/tests/database`.

Local ports are shifted by +100 (database on 54422) to avoid clashing with other local Supabase stacks.

## Deploying

See [docs/operations/deploy.md](docs/operations/deploy.md) for the hosted deployment steps and [docs/operations/backups.md](docs/operations/backups.md) for the nightly encrypted backup and restore check.

## Data sources and licences

### CoFID (OGL v3.0)

TBD

### Open Food Facts (ODbL)

TBD

### CO2e sources

TBD
