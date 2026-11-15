#!/usr/bin/env bash
# Usage: scripts/backup/dump.sh <out_dir>
# Env:   SUPABASE_DB_URL (session pooler URI), AGE_RECIPIENT (age1... public key),
#        RUN_ID (unique per run; written to public.backup_heartbeat and checked in the dump)
# Writes <out_dir>/{roles,schema,data}.sql.age. Plaintext never leaves a private temp dir.
set -euo pipefail

out_dir="${1:?usage: dump.sh <out_dir>}"
: "${SUPABASE_DB_URL:?SUPABASE_DB_URL is required}"
: "${AGE_RECIPIENT:?AGE_RECIPIENT is required}"
: "${RUN_ID:?RUN_ID is required}"

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

mkdir -p "$out_dir"
tmp="$(mktemp -d)"
cleanup() {
  find "$tmp" -type f -exec shred -u {} + 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

# 1. Heartbeat: proves the dump is fresh, and counts as activity (keeps the free project awake).
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v run_id="$RUN_ID" \
  <<< "insert into public.backup_heartbeat(run_id) values (:'run_id');"

# 2. The three documented dumps. CLI 3.1.0 targets a URL with --remote=<url> (older CLIs: --db-url).
"${sb[@]}" db dump --remote="$SUPABASE_DB_URL" -f "$tmp/roles.sql" --role-only
"${sb[@]}" db dump --remote="$SUPABASE_DB_URL" -f "$tmp/schema.sql"
"${sb[@]}" db dump --remote="$SUPABASE_DB_URL" -f "$tmp/data.sql" --use-copy --data-only \
  -x "storage.buckets_vectors" -x "storage.vector_indexes"

# 3. Sanity checks: nothing empty, and the heartbeat made it into the data dump.
for name in roles schema data; do
  if ! [ -s "$tmp/$name.sql" ]; then
    echo "backup failed: $name.sql is empty" >&2
    exit 1
  fi
done
if ! grep -qF -- "$RUN_ID" "$tmp/data.sql"; then
  echo "backup failed: data.sql does not contain heartbeat $RUN_ID" >&2
  exit 1
fi

# 4. Encrypt, then shred the plaintext.
for name in roles schema data; do
  age -r "$AGE_RECIPIENT" -o "$out_dir/$name.sql.age" "$tmp/$name.sql"
  shred -u "$tmp/$name.sql"
done
echo "backup OK: $out_dir (heartbeat $RUN_ID)"
