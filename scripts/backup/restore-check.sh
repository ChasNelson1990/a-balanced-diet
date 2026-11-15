#!/usr/bin/env bash
# Usage: scripts/backup/restore-check.sh <dir_with_age_files> <age_identity_file> <expected_run_id>
# Decrypts a backup, restores it into a throwaway local Supabase stack (ports +1000 so it can
# run beside the dev stack), and exits 0 only if public.backup_heartbeat contains the run id.
set -euo pipefail

backup_dir="${1:?usage: restore-check.sh <dir_with_age_files> <age_identity_file> <expected_run_id>}"
identity="${2:?missing age identity file}"
expected="${3:?missing expected run id}"

if ! [[ "$expected" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "expected_run_id must match [A-Za-z0-9._-]+" >&2
  exit 1
fi

# Make the arguments absolute before changing directory.
backup_dir="$(cd "$backup_dir" && pwd)"
identity="$(cd "$(dirname "$identity")" && pwd)/$(basename "$identity")"

# Resolve the repo's pinned CLI: always run npx from the repo root, so it cannot fetch another.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
if command -v supabase >/dev/null 2>&1; then
  sb=(supabase)
else
  sb=(npx --prefix "$repo_root" supabase)
fi

plain="$(mktemp -d)"
stack="$(mktemp -d)"
db_url="postgresql://postgres:postgres@127.0.0.1:55322/postgres"

cleanup() {
  "${sb[@]}" stop --workdir "$stack" --no-backup >/dev/null 2>&1 || true
  find "$plain" -type f -exec shred -u {} + 2>/dev/null || true
  rm -rf "$plain" "$stack"
}
trap cleanup EXIT

# 1. Decrypt.
for name in roles schema data; do
  age -d -i "$identity" -o "$plain/$name.sql" "$backup_dir/$name.sql.age"
done

# 2. Throwaway stack: fresh project, every port shifted by +1000, no migrations.
"${sb[@]}" init --workdir "$stack" >/dev/null
cfg="$stack/supabase/config.toml"
sed -i -E \
  -e 's/^project_id = .*/project_id = "restore-check"/' \
  -e 's/^((shadow_|inspector_)?port[[:space:]]*=[[:space:]]*)543([0-9]{2})/\1553\3/' \
  -e 's/^(inspector_port[[:space:]]*=[[:space:]]*)8083/\19083/' \
  "$cfg"
"${sb[@]}" start --workdir "$stack"

# 3. Restore (documented method). Known-harmless lines that fail on a fresh local stack are
#    commented out, as the Supabase docs advise.
sed -i -E 's/^(ALTER .* OWNER TO "supabase_admin";)/-- \1/' "$plain/schema.sql"
sed -i -E 's/^(GRANT "postgres" TO "cli_login_postgres".*)/-- \1/' "$plain/roles.sql"

psql "$db_url" --single-transaction -v ON_ERROR_STOP=1 \
  -f "$plain/roles.sql" \
  -f "$plain/schema.sql" \
  -c 'SET session_replication_role = replica' \
  -f "$plain/data.sql"

# 4. The heartbeat must be there exactly once.
count="$(psql "$db_url" -tAc "select count(*) from public.backup_heartbeat where run_id = '$expected'")"
if [ "$count" != "1" ]; then
  echo "restore check FAILED: heartbeat $expected found $count times (expected 1)" >&2
  exit 1
fi
# 5. Reference data must have survived the restore.
groups="$(psql "$db_url" -tAc "select count(*) from public.eat_group")"
if [ "$groups" != "16" ]; then
  echo "restore check FAILED: eat_group has $groups rows (expected 16)" >&2
  exit 1
fi
echo "restore check OK: heartbeat $expected found, eat_group = 16"
