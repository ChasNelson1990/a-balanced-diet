# a-balanced-diet

A personal diet-tracking progressive web app, backed by Supabase (Postgres, auth and row-level security). It helps track meals against a planetary-health diet using metric units only. See the [design spec](docs/superpowers/specs/2026-11-14-a-balanced-diet-design.md).

## Local development

Prerequisites: Node.js 24 with npm, and Docker running.

- `npm ci` installs the pinned dependencies, including the Supabase CLI. Run this first.
- `npm run db:start` starts the local Supabase stack.
- `npm run db:reset` rebuilds the local database from the migrations.
- `npm run db:test` runs the pgTAP tests in `supabase/tests/database`.

## Deploying

See [docs/operations/deploy.md](docs/operations/deploy.md) for the hosted deployment steps and [docs/operations/backups.md](docs/operations/backups.md) for the nightly encrypted backup and restore check.

## Licence

The code is released under the [MIT licence](LICENSE). Third-party data keeps its own licence, listed below.

## Data sources and licences

### CoFID (OGL v3.0)

TBD

### Open Food Facts (ODbL)

TBD

### CO2e sources

TBD
