#!/usr/bin/env bash
# Usage: scripts/backup/dump.sh <out_dir>
# Config: config/supabase.env (host, port, user, db name, AGE_RECIPIENT; committed, not secret).
# Env:   SUPABASE_DB_PASSWORD (secret),
#        RUN_ID (unique per run; written to public.backup_heartbeat and checked in the dump).
#        Optional override: AGE_RECIPIENT (replaces the one in the config file).
# Every connection is TLS, verified against Supabase's CA (sslmode=verify-full).
# Writes <out_dir>/{roles,schema,data}.sql.age. Plaintext never leaves a private temp dir.
set -euo pipefail

out_dir="${1:?usage: dump.sh <out_dir>}"
: "${RUN_ID:?RUN_ID is required}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
override_age="${AGE_RECIPIENT:-}"
set -a
# shellcheck source=/dev/null
source "$repo_root/config/supabase.env"
set +a
[ -z "$override_age" ] || AGE_RECIPIENT="$override_age"
: "${AGE_RECIPIENT:?AGE_RECIPIENT is required}"

# Connection settings for psql and pg_dump. No URL, so the password is never on a command line.
: "${SUPABASE_DB_PASSWORD:?SUPABASE_DB_PASSWORD is required}"
ca_file="$repo_root/config/supabase-prod-ca-2021.crt"
export PGHOST="$SUPABASE_DB_HOST" PGPORT="$SUPABASE_DB_PORT" PGUSER="$SUPABASE_DB_USER"
export PGDATABASE="$SUPABASE_DB_NAME" PGPASSWORD="$SUPABASE_DB_PASSWORD"
export PGSSLMODE=verify-full PGSSLROOTCERT="$ca_file"

# The image CLI 3.1.0 dumps with. Bump it with the CLI (its major must be >= the server's).
pg_image="public.ecr.aws/supabase/postgres:17.11.0.018"

if ! [[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "RUN_ID must match [A-Za-z0-9._-]+" >&2
  exit 1
fi

# Prefer an installed supabase CLI (CI), else the repo's npm devDependency.
if command -v supabase >/dev/null 2>&1; then
  sb=(supabase)
else
  sb=(npx supabase)
fi

# `supabase db dump` drops sslmode before it runs pg_dump. So have the CLI print its dump script
# (a dry run against a dummy URL, which connects to nothing) and run that with verified TLS.
verified_dump() {
  local out="$1" script
  shift
  script="$("${sb[@]}" db dump --dry-run "$@" --remote='postgresql://unused:unused@127.0.0.1:1/postgres' |
    sed -n '/^#!\/usr\/bin\/env bash/,$p' |
    grep -v -E '^export PG(HOST|PORT|USER|PASSWORD|DATABASE)=')"
  if [[ "$script" != *pg_dump* || "$script" == *"export PG"* ]]; then
    echo "backup failed: unexpected dry-run output from supabase db dump (CLI changed?)" >&2
    return 1
  fi
  docker run --rm --entrypoint bash \
    -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE -e PGSSLMODE \
    -e PGSSLROOTCERT=/supabase-ca.crt -v "$ca_file:/supabase-ca.crt:ro" \
    "$pg_image" -c "$script" > "$out"
}

mkdir -p "$out_dir"
tmp="$(mktemp -d)"
cleanup() {
  find "$tmp" -type f -exec shred -u {} + 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

# 1. Heartbeat: proves the dump is fresh, and counts as activity (keeps the free project awake).
psql -v ON_ERROR_STOP=1 -v run_id="$RUN_ID" \
  <<< "insert into public.backup_heartbeat(run_id) values (:'run_id');"

# 2. The three documented dumps.
verified_dump "$tmp/roles.sql" --role-only
verified_dump "$tmp/schema.sql"
verified_dump "$tmp/data.sql" --use-copy --data-only \
  -x "storage.buckets_vectors" -x "storage.vector_indexes"

# 3. Sanity checks: nothing empty, and the heartbeat made it into the data dump.
for name in roles schema data; do
  if ! [ -s "$tmp/$name.sql" ]; then
    echo "backup failed: $name.sql is empty" >&2
    exit 1
  fi
done
# The COPY row is tab-delimited: id <TAB> run_id <TAB> created_at.
if ! grep -qF -- "$(printf '\t%s\t' "$RUN_ID")" "$tmp/data.sql"; then
  echo "backup failed: data.sql does not contain heartbeat $RUN_ID" >&2
  exit 1
fi

# 4. Encrypt, then shred the plaintext.
for name in roles schema data; do
  age -r "$AGE_RECIPIENT" -o "$out_dir/$name.sql.age" "$tmp/$name.sql"
  shred -u "$tmp/$name.sql"
done
echo "backup OK: $out_dir (heartbeat $RUN_ID)"
