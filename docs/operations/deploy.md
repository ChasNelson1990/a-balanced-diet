# Deploying to the hosted Supabase project

Connection settings live in `config/supabase.env` (committed, not secret). The database
password is only ever supplied through `SUPABASE_DB_PASSWORD` (direnv locally, a GitHub
secret in CI). `supabase link` is not needed: every command below targets the database with
`--remote=<url>` instead.

## 0. Build the connection URL

Run this in each shell session. It loads direnv (which exports `SUPABASE_DB_PASSWORD`),
sources the config, percent-encodes the password and builds `URL`. The password is never
typed on a command line. Do not echo `URL`.

```bash
eval "$(direnv export bash 2>/dev/null)"
set -a; source config/supabase.env; set +a
enc="$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "$SUPABASE_DB_PASSWORD")"
URL="postgresql://${SUPABASE_DB_USER}:${enc}@${SUPABASE_DB_HOST}:${SUPABASE_DB_PORT}/${SUPABASE_DB_NAME}"
```

## 1. Postgres version

```bash
psql "$URL" -tAc 'show server_version'
```

Hosted returned `17.11`, matching `[db] major_version = 17`.

## 2. Migrations and seed data

Migrations (CLI 3.1.0; `--db-url` is deprecated):

```bash
npx supabase db push --yes --remote="$URL"
```

This applied the four migrations after `backup_heartbeat`.

Seeds: the CLI has `db push --include-seed`, but it was not used. The seeds are plain
`INSERT`s with no `ON CONFLICT`, so apply them exactly once with psql. Pre-check first;
this must print `0`, otherwise stop, because the project is already seeded:

```bash
psql "$URL" -tAc 'select count(*) from public.eat_group'
psql "$URL" -v ON_ERROR_STOP=1 --single-transaction \
  -f supabase/seed/eat_group.sql -f supabase/seed/nutrient.sql -f supabase/seed/scottish_baseline.sql
```

Result: 16 eat groups, 16 nutrients, 1 scottish_baseline row.

## 3. Auth settings

Set in the dashboard: sign-ups off, email confirmation off. Verify with the publishable key
(public by design; it goes in the `apikey` header, never as a Bearer token):

```bash
/usr/bin/curl -s -X POST "$SUPABASE_URL/auth/v1/signup" -H "apikey: $SUPABASE_PUBLISHABLE_KEY" \
  -H 'content-type: application/json' -d '{"email":"probe@example.com","password":"probe-password-123"}'
# {"code":422,"error_code":"signup_disabled","msg":"Signups not allowed for this instance"}
```

Note: `curl` may be aliased to `curlie` in an interactive shell, which adds a JSON body to
GET requests and returns a bogus `PGRST102`. Use `/usr/bin/curl` for probes.

## 4. Owner account

Created by the owner in the dashboard (Authentication, Users, Add user, auto confirm).
Read-only check: `psql "$URL" -tAc 'select count(*) from auth.users'` returns `1`.

## 5. RLS smoke test

Runs in a transaction that is rolled back, so nothing persists:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
do $$ declare n int; begin
  select count(*) into n from public.eat_group;
  assert n = 16, 'authenticated saw ' || n;
  raise notice 'authenticated eat_group rows: %', n;
end $$;
set local role anon;
do $$ begin
  begin
    perform count(*) from public.eat_group;
    raise exception 'anon read succeeded';
  exception when insufficient_privilege then
    raise notice 'anon denied with 42501';
  end;
end $$;
rollback;
```

Save it as a file and run `psql "$URL" -v ON_ERROR_STOP=1 -f <file>`. Then the public API
check, which must not return 16 rows (it returns HTTP 401 with code 42501):

```bash
/usr/bin/curl -s -i "$SUPABASE_URL/rest/v1/eat_group?select=code" -H "apikey: $SUPABASE_PUBLISHABLE_KEY"
```

## 6. Backup and restore check

```bash
gh workflow run backup.yml --ref <branch>
gh run watch <run_id> --exit-status
gh run download <run_id> -D <empty_dir>      # creates <empty_dir>/backup-<run_id>/
scripts/backup/restore-check.sh <empty_dir>/backup-<run_id> ~/.config/a-balanced-diet/backup.agekey <run_id>-<attempt>
```

Expected last line: `restore check OK: heartbeat <run_id>-<attempt> found, eat_group = 16`.
See `backups.md`, "Proven end to end", for details and the recorded run.
