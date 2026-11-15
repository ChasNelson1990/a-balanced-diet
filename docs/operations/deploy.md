# Deploying to the hosted Supabase project

Connection settings live in `config/supabase.env`. The database password is only ever
supplied through `SUPABASE_DB_PASSWORD` (direnv locally, a GitHub secret in CI).

## 1. Postgres version

`show server_version` on hosted returned `17.11`, matching `[db] major_version = 17`.

## 2. Migrations and seed data

Migrations: `npx supabase db push --yes --remote="<url>"` (CLI 3.1.0; `--db-url` is
deprecated). This applied the four migrations after `backup_heartbeat`.

Seeds: the CLI has `db push --include-seed`, but it was not used. The seeds are plain
`INSERT`s with no `ON CONFLICT`, so they were applied exactly once with psql, after checking
that `eat_group` was empty:

```bash
psql "$URL" -v ON_ERROR_STOP=1 --single-transaction \
  -f supabase/seed/eat_group.sql -f supabase/seed/nutrient.sql -f supabase/seed/scottish_baseline.sql
```

Result: 16 eat groups, 16 nutrients, 1 scottish_baseline row. Never re-run this on a
populated project.

## 3. Auth settings

Set in the dashboard: sign-ups off, email confirmation off. Verified:

```bash
curl -s -X POST "$SUPABASE_URL/auth/v1/signup" -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  -H 'content-type: application/json' -d '{"email":"probe@example.com","password":"probe-password-123"}'
# {"code":422,"error_code":"signup_disabled","msg":"Signups not allowed for this instance"}
```

## 4. Owner account

Created by the owner in the dashboard (Authentication, Users, Add user, auto confirm).
`auth.users` holds exactly one user.

## 5. RLS smoke test

Run in a rolled-back transaction: as `authenticated` with a random `sub`, `eat_group`
returns 16 rows; as `anon`, the same read fails with 42501. Over the public API, the
publishable key alone (sent in the `apikey` header, not as a Bearer token) gets HTTP 401 with
code 42501 (`permission denied for table eat_group`).

## 6. Backup

See `backups.md`, "Proven end to end".
