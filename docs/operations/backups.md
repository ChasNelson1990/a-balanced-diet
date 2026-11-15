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
4. Encrypts each file with `age` to the public key in the `AGE_RECIPIENT` secret and shreds
   the plaintext.

The connection uses the **session pooler** URI (`SUPABASE_DB_URL` secret):
`postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres`.
The user must be `postgres.<ref>`, the port `5432` (session mode, not 6543), and any special
characters in the password must be percent-encoded.

### CLI flag

Supabase CLI 3.1.0 (the repo's pinned devDependency) has no `--db-url` on `db dump`; it uses
`--remote=<ref|branch|url>`. The scripts pass `--remote="$SUPABASE_DB_URL"`. Older CLIs
(and the Supabase docs page) may show `--db-url` instead.

## Where the backups are

Each run uploads a GitHub Actions artifact `backup-<run_id>` containing `roles.sql.age`,
`schema.sql.age` and `data.sql.age`. Artifacts are kept for **90 days**.

The private key (`~/.config/a-balanced-diet/backup.agekey`) is not on GitHub. Keep a copy
somewhere safe: without it the backups cannot be decrypted.

## Restoring

```bash
gh run download <run_id> -n backup-<run_id> -D /tmp/abd-restore
scripts/backup/restore-check.sh /tmp/abd-restore ~/.config/a-balanced-diet/backup.agekey <run_id>-1
```

(`-1` is the run attempt; use the attempt number of the run you downloaded.)

`restore-check.sh` decrypts the files, starts a throwaway local Supabase stack (project id
`restore-check`, every port shifted +1000 so it can run beside the dev stack), restores into
it with `psql --single-transaction -v ON_ERROR_STOP=1 -f roles.sql -f schema.sql -c 'SET
session_replication_role = replica' -f data.sql`, checks the heartbeat row, then stops and
removes the stack. It prints `restore check OK: heartbeat <run_id>-1 found` on success.

Before restoring, the script comments out two lines that are known to fail on a fresh stack,
as the Supabase docs advise: `ALTER ... OWNER TO "supabase_admin"` in `schema.sql` and
`GRANT "postgres" TO "cli_login_postgres"` in `roles.sql`.

To restore into a real new project, follow the same `psql` sequence against its connection
string.

### Vault root key caveat

Supabase Vault secrets are encrypted with a project root key that is **not** in the dump.
Before deleting or replacing a project, retrieve its root encryption key (see Supabase's
docs); otherwise Vault secrets (used from Task 6) cannot be decrypted after a restore.

## Pausing

Free projects pause after about a week of inactivity. The nightly heartbeat should prevent
that, but a failed nightly run is the early warning that the project has paused. Resume it
in the Supabase dashboard, then re-run the workflow.

## Troubleshooting connection failures

- User must be `postgres.<ref>`, not `postgres`.
- Port `5432` (session mode), not `6543`.
- Percent-encode special characters in the password.
