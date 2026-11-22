# Backups

## What runs and when

`.github/workflows/backup.yml` runs every night at 03:17 UTC (and on demand via
`workflow_dispatch`). It runs `scripts/backup/dump.sh`, which:

1. Inserts a heartbeat row (`run_id = <github run id>-<attempt>`) into
   `public.backup_heartbeat`. This also counts as database activity, which helps stop the
   free project pausing.
2. Dumps roles, schema and data with `supabase db dump` (`roles.sql`, `schema.sql`,
   `data.sql` with `--use-copy`).
3. Fails if any dump is empty or if `data.sql` does not contain the run id.
4. Encrypts each file with `age` to the public key in `config/supabase.env` and shreds
   the plaintext.

### Configuration

Non-secret settings live in the committed `config/supabase.env` (project ref, URL, pooler
host/port/user/database, and the `AGE_RECIPIENT` public key). The only GitHub secret is
`SUPABASE_DB_PASSWORD`. `dump.sh` sources the config file and connects through the session
pooler (`postgres.<ref>` at `aws-N-<region>.pooler.supabase.com:5432`), passing the password in
the environment, never on a command line.
The project region is **eu-west-1** (Ireland), pooler host `aws-1-eu-west-1.pooler.supabase.com`.
The user must be `postgres.<ref>`, the port `5432` (session mode, not 6543). The workflow
masks the raw and encoded password in the logs.

`AGE_RECIPIENT` in the environment overrides the configured key, for test backups.

### TLS

Every connection `dump.sh` makes uses `sslmode=verify-full` with Supabase's root CA, committed
as `config/supabase-prod-ca-2021.crt` (the public certificate offered in the dashboard, SHA-256
`80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA`,
**expires 26 April 2031**).

Supabase CLI 3.1.0 drops `sslmode` before it runs `pg_dump`, so `dump.sh` doesn't let the CLI
connect. It takes the dump script from `supabase db dump --dry-run` and runs it in the same
Postgres image with verified TLS. When upgrading the CLI, bump `pg_image` in `dump.sh` and run
the backup and restore check once.

Also keep **Enforce SSL** switched on in the dashboard (Database settings, SSL configuration).
It makes the server refuse unencrypted connections from every other client, but it doesn't
replace verification: it can't prove the server's identity to the client.

## Where the backups are

Each run attempt uploads a GitHub Actions artifact `backup-<run_id>-<attempt>` containing
`roles.sql.age`, `schema.sql.age` and `data.sql.age`. Artifacts are kept for **90 days**.
(Runs up to 2026-11-22 11:16 UTC used `backup-<run_id>`, without the attempt.)

The private key (`~/.config/a-balanced-diet/backup.agekey`) is not on GitHub. Keep a copy
somewhere safe: without it the backups cannot be decrypted.

## Restoring

```bash
gh run download <run_id> -n backup-<run_id>-<attempt> -D /tmp/abd-restore
scripts/backup/restore-check.sh /tmp/abd-restore ~/.config/a-balanced-diet/backup.agekey <run_id>-<attempt>
```

(`<attempt>` is 1 unless the run was re-run. The id after `backup-` is also the heartbeat id.)

`restore-check.sh` decrypts the files, starts a throwaway local Supabase stack (project id
`restore-check`, every port shifted +1000 so it can run beside the dev stack), restores into
it with `psql --single-transaction -v ON_ERROR_STOP=1 -f roles.sql -f schema.sql -c 'SET
session_replication_role = replica' -f data.sql`, checks the heartbeat row, then stops and
removes the stack. It prints `restore check OK: heartbeat <run_id>-<attempt> found` on success.
Only one check runs at a time: a second waits for the first (up to 30 minutes).

Before restoring, the script comments out two lines that are known to fail on a fresh stack,
as the Supabase docs advise: `ALTER ... OWNER TO "supabase_admin"` in `schema.sql` and
`GRANT "postgres" TO "cli_login_postgres"` in `roles.sql`.

The throwaway stack runs the **same Auth version as the hosted project**, read from its
`/auth/v1/health` endpoint. Supabase upgrades hosted Auth ahead of the version bundled with the
CLI, and a dump from a newer Auth has columns that an older one lacks (on 2026-11-22 this
failed with `column "link_token_hash" of relation "one_time_tokens" does not exist`). If the
project can't be reached, pass a version yourself: `AUTH_VERSION=vX.Y.Z scripts/backup/restore-check.sh ...`.
The same kind of failure in the `storage` schema would mean Storage has moved ahead too: update
the Supabase CLI.

### Restoring into a new hosted project

Use this when the hosted project is lost. Run commands from the repo root.

1. Create a new Supabase project (same region if you can) and note its ref, database
   password and pooler host.
2. Point the repo at the **new** project before connecting. Update `config/supabase.env`
   (project ref, URL, pooler host, user) and set `SUPABASE_DB_PASSWORD` in your direnv
   environment to the new project's password. Then build `URL` from those values. Building
   it from the old config would target the lost project. Do not echo `URL`:

   ```bash
   eval "$(direnv export bash 2>/dev/null)"
   : "${SUPABASE_DB_PASSWORD:?SUPABASE_DB_PASSWORD is not set}"
   set -a; source config/supabase.env; set +a
   enc="$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "$SUPABASE_DB_PASSWORD")"
   URL="postgresql://${SUPABASE_DB_USER}:${enc}@${SUPABASE_DB_HOST}:${SUPABASE_DB_PORT}/${SUPABASE_DB_NAME}"
   URL_TLS="${URL}?sslmode=verify-full&sslrootcert=$PWD/config/supabase-prod-ca-2021.crt"
   ```

   Switch on **Enforce SSL** for the new project. Use `URL_TLS` with `psql`; the CLI ignores
   those parameters, so it gets the plain `URL`.

3. Decrypt the backup (`age -d -i ~/.config/a-balanced-diet/backup.agekey -o <name>.sql
   <name>.sql.age` for `roles`, `schema` and `data`), apply the two `sed` fixes from the
   section above, and run the documented restore against `$URL`:

   ```bash
   psql "$URL_TLS" --single-transaction -v ON_ERROR_STOP=1 \
     -f roles.sql -f schema.sql -c 'SET session_replication_role = replica' -f data.sql
   ```

4. The `supabase_migrations` schema is excluded from the dump, so the new project does not
   know which migrations were applied. Mark every migration as applied, otherwise the next
   `db push` tries to re-run them. CLI 3.1.0 needs `--yes` for a remote mutation:

   ```bash
   for f in supabase/migrations/*.sql; do
     v="$(basename "$f" | cut -d_ -f1)"
     npx supabase migration repair --status applied "$v" --yes --remote="$URL"
   done
   ```

5. Do **not** re-apply the seeds: the reference data is already in `data.sql`.
6. Re-apply the dashboard auth settings (sign-ups off, email confirmation off).
7. Commit the `config/supabase.env` change, update the `SUPABASE_DB_PASSWORD` GitHub secret,
   then run the backup workflow once to prove it.

### Vault root key caveat

Supabase Vault secrets are encrypted with a project root key that is **not** in the dump.
Before deleting or replacing a project, retrieve its root encryption key (see Supabase's
docs); otherwise Vault secrets (used from Task 6) cannot be decrypted after a restore.

## Proven end to end

Run 43708807036 (attempt 2) produced artifact `backup-43708807036`; restoring it with
`restore-check.sh` printed `restore check OK: heartbeat 43708807036-2 found`. The first
attempt failed only because the heartbeat migration had not yet been applied to the hosted
project: apply migrations (`supabase db push --remote=<url> --yes`) before the first backup.
No extra `sed` fixes beyond the two documented lines were needed for the hosted dump.

## Pausing

Free projects pause after about a week of inactivity. The nightly heartbeat should prevent
that, but a failed nightly run is the early warning that the project has paused. Resume it
in the Supabase dashboard, then re-run the workflow.

### GitHub disables scheduled workflows after 60 days of no repository activity

This repository is public. GitHub disables `schedule:` triggers in a public repo after 60
days without repository activity (commits, PRs, issues and so on; workflow runs do not
count). That would stop both the nightly backups and the keep-alive heartbeat, and Supabase
would then pause the project about 7 days later.

- GitHub sends a warning email shortly before it disables the workflow.
- To re-enable: Actions, `backup`, **Enable workflow**, or `gh workflow enable backup.yml`.
  Pushing any commit to the repo also resets the clock.
- Fallbacks if you do not want to depend on this: run `scripts/backup/dump.sh` from a
  homelab cron job (it needs `SUPABASE_DB_PASSWORD`, `age` and `psql`), or make the repo
  private (scheduled workflows are not disabled there, but private repos use the Actions
  minutes quota).

No workaround is built in; this is a decision for the owner.

## Troubleshooting connection failures

- User must be `postgres.<ref>`, not `postgres`.
- Port `5432` (session mode), not `6543`.
- Paste the password raw into the secret; `dump.sh` needs no percent-encoding.
- `certificate verify failed`: check the CA hasn't expired or been replaced by Supabase. Don't
  lower `sslmode` to get past it.
