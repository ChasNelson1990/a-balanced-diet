# Plan 1: Foundation (schema, RLS, auth config, reference data, proven backups)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Supabase backend with the full v1 schema, row-level security, invite-only auth, seeded EAT-Lancet 2025 targets, and a nightly encrypted backup that has been proven by a real restore.

**Architecture:** All database objects live as SQL migrations in `supabase/migrations/` and are tested with pgTAP (`supabase test db`) against the local Docker stack. They are pushed to one hosted free-tier project. The backups use Supabase's documented three-file `supabase db dump` (roles, schema, data) through the **session pooler** in a GitHub Action, encrypt the files with `age`, and store them as workflow artifacts. A local script restores a backup into a throwaway local Supabase stack and checks a heartbeat row.

**Tech stack:** Supabase CLI (npm devDependency, run via `npx supabase`), Postgres (major version matching the hosted project, expected 17), pgTAP, GitHub Actions (`supabase/setup-cli@v1`), `age`, Docker.

**Spec:** `docs/superpowers/specs/2026-11-14-a-balanced-diet-design.md` (sections 3, 4, 5, 6, 7.3, 9.4 and 12 are the ones this plan implements).

**Plan series:** 1 Foundation (this plan) → 2 Core logic (colour, shares, score, optimiser) → 3 Data pipeline (CoFID, CO2e, mappings) → 4 App (PWA, local store, sync, screens, Edge Functions).

## Global constraints

- Metric only: grams, ml, kcal, mg. No imperial units anywhere: column names, comments, seed data or docs.
- Missing nutrient values are `NULL` (unknown), never `0`.
- Every per-user table has `owner_id uuid not null default auth.uid()` referencing `auth.users(id) on delete cascade`, `updated_at timestamptz not null default now()` maintained by trigger, and `deleted_at timestamptz` (soft delete). Primary keys are `uuid` generated on the client (`default gen_random_uuid()` as a fallback).
- RLS is enabled on **every** table in `public`. No table is left readable by `anon`.
- Free tier only: no paid add-ons, no IPv4 add-on.
- Secrets (database password, `age` private key, Anthropic keys) are never committed and never in a client bundle.
- Commit titles: `<type>: <emoji> <lowercase description>`. Work on branch `feat/foundation`; never commit to `main`.
- Dates use the Europe/London calendar day (a `date` column); timestamps are `timestamptz`.

## Review focus

1. **A backup that "succeeds" but is empty or partial** (wrong pooler user, paused project, dump of the wrong schema). The workflow must fail unless every file is non-empty and the data file contains the heartbeat written in the same run. *Test: Task 2, Step 5.*
2. **A user making a private food shared** by updating `visibility` or `owner_id` on their own row, which would leak edits to everyone. *Test: Task 4, `food_visibility_cannot_escalate`.*
3. **Rewriting cupboard history**: updating or deleting `cupboard_movement` rows, which would corrupt waste totals. *Test: Task 5, `movement_is_append_only`.*
4. **Hard-deleting a food that log entries reference**, which would break history. *Test: Task 4, `food_hard_delete_blocked_when_referenced`.*
5. **Reading another user's Anthropic key**, or one's own raw key, through any select. *Test: Task 6, `secret_value_never_selectable`.*

---

### Task 1: Scaffold the Supabase project, local test harness and CI

**Files:**
- Create: `package.json`, `supabase/config.toml` (via `npx supabase init`), `supabase/tests/database/00_smoke.test.sql`, `.github/workflows/db-tests.yml`, `README.md`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `npm run db:start`, `npm run db:test`, `npm run db:reset`, which later tasks use for verification.

- [ ] **Step 1: Create branch and package.json**

```bash
git checkout main && git pull && git checkout -b feat/foundation
npm init -y && npm pkg set private=true name=a-balanced-diet
npm install --save-dev supabase
npm pkg set scripts.db:start="supabase start" scripts.db:stop="supabase stop" scripts.db:reset="supabase db reset" scripts.db:test="supabase test db"
npx supabase init
```

- [ ] **Step 2: Configure `supabase/config.toml`**

Set `[auth] enable_signup = false`, `[auth.email] enable_confirmations = false`, and `[db] major_version = 17`. This must match the hosted project; Task 7 checks it with `SHOW server_version;`, and if they differ, change this value and re-run `npm run db:reset`. Add `supabase/.temp/`, `supabase/.branches/`, `.env*` and `node_modules/` to `.gitignore`.

- [ ] **Step 3: Write the smoke test `supabase/tests/database/00_smoke.test.sql`**

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(1);
select has_extension('pgtap', 'pgtap is available');
select * from finish();
rollback;
```

- [ ] **Step 4: Run it**

Run: `npm run db:start && npm run db:test`
Expected: `00_smoke.test.sql .. ok`, `All tests successful.`

- [ ] **Step 5: CI workflow `.github/workflows/db-tests.yml`**

Trigger on `pull_request` and `push` to `main`. Job on `ubuntu-latest`: checkout, `actions/setup-node@v4` (node 24), `npm ci`, `npx supabase start`, `npx supabase test db`.

- [ ] **Step 6: README**

One paragraph on what the app is (link to the spec), a "Local development" section listing the three npm scripts and the Docker prerequisite, and a "Data sources and licences" section with placeholder headings: CoFID (OGL v3.0), Open Food Facts (ODbL), CO2e sources.

- [ ] **Step 7: Commit**

```bash
git add package.json package-lock.json supabase .github README.md .gitignore
git commit -m "chore: :wrench: scaffold supabase project with pgtap and ci"
```

---

### Task 2: Backup workflow and restore check, proven against the hosted project

This goes first by design (spec §12). **Do not start Task 3 until Step 8 passes.** If the pooler route keeps failing after the troubleshooting in Step 7, stop and report back. The spec's fallback (running the same script from the user's machine or homelab) is a decision for the user.

**Files:**
- Create: `supabase/migrations/<ts>_backup_heartbeat.sql`, `supabase/tests/database/01_backup_heartbeat.test.sql`, `scripts/backup/dump.sh`, `scripts/backup/restore-check.sh`, `.github/workflows/backup.yml`, `docs/operations/backups.md`

**Interfaces:**
- Produces: table `public.backup_heartbeat(id bigint generated always as identity primary key, run_id text not null unique, created_at timestamptz not null default now())`. RLS is enabled with **no** policies, so only the `postgres` role (connection string) can read or write it.
- Produces: `scripts/backup/dump.sh <out_dir>` (env: `SUPABASE_DB_URL`, `AGE_RECIPIENT`, `RUN_ID`), which writes `roles.sql.age`, `schema.sql.age` and `data.sql.age`, and exits non-zero if any plaintext file is empty or `data.sql` lacks `RUN_ID`.
- Produces: `scripts/backup/restore-check.sh <dir_with_age_files> <age_identity_file> <expected_run_id>`, which exits 0 only if the restored `backup_heartbeat` contains `expected_run_id`.

- [ ] **Step 1: USER STEP: create the hosted project and secrets** *(the implementer pauses and asks the user)*
  1. Create a Supabase project (free tier, region `eu-west-2` London) and note the project ref and database password.
  2. From *Connect → Session pooler*, copy the URI (`postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres`).
  3. Locally (install `age` first, e.g. `sudo pacman -S age`): `age-keygen -o ~/.config/a-balanced-diet/backup.agekey`, and note the public key (`age1…`). Keep the private key file off GitHub and back it up somewhere safe.
  4. In the GitHub repo settings, add the secrets `SUPABASE_DB_URL` (session pooler URI) and `AGE_RECIPIENT` (the `age1…` public key).

- [ ] **Step 2: Failing pgTAP test `01_backup_heartbeat.test.sql`**

Assertions: `has_table('public','backup_heartbeat')`; `col_is_unique('public','backup_heartbeat','run_id')`; RLS enabled (`select relrowsecurity from pg_class where oid = 'public.backup_heartbeat'::regclass` is true); as role `authenticated`, `select count(*) from public.backup_heartbeat` returns 0 rows visible even after the test inserts one as `postgres` (use `set local role authenticated` after the insert, and `results_eq` on the count = 0).

Run: `npm run db:test`, expected FAIL (table missing).

- [ ] **Step 3: Migration `npx supabase migration new backup_heartbeat`** with the table from Interfaces and `alter table … enable row level security;`. Run `npm run db:reset && npm run db:test`, expected PASS. Then, with the user's approval (it changes the hosted database), apply it to the hosted project with `npx supabase db push --yes --remote="$SUPABASE_DB_URL"`: the first hosted backup in Step 7 writes to this table, long before Task 7 deploys the rest.

- [ ] **Step 4: `scripts/backup/dump.sh`**

Behaviour, in order (with `set -euo pipefail`):
1. `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -c "insert into public.backup_heartbeat(run_id) values ('$RUN_ID')"`. This also counts as database activity, which helps keep the free project from pausing.
2. The three documented dumps into a `mktemp -d` directory:
   `supabase db dump --db-url "$SUPABASE_DB_URL" -f roles.sql --role-only`
   `supabase db dump --db-url "$SUPABASE_DB_URL" -f schema.sql`
   `supabase db dump --db-url "$SUPABASE_DB_URL" -f data.sql --use-copy --data-only -x "storage.buckets_vectors" -x "storage.vector_indexes"`
   (Supabase's docs page shows `--remote=`; use whichever flag `npx supabase db dump --help` lists for the installed CLI version, and record which one in `docs/operations/backups.md`.)
3. Fail if any file is empty (`[ -s file ]`) or if `grep -q "$RUN_ID" data.sql` fails.
4. `age -r "$AGE_RECIPIENT" -o <out>/<name>.sql.age <name>.sql` for each file, then `shred -u` the plaintext.

- [ ] **Step 5: `.github/workflows/backup.yml`**

Triggers: `schedule: cron '17 3 * * *'` and `workflow_dispatch`. Job on `ubuntu-latest` with these steps:
- checkout
- `supabase/setup-cli@v1` (version `latest`)
- `sudo apt-get update && sudo apt-get install -y age postgresql-client`
- run `scripts/backup/dump.sh backup-out` with env from secrets and `RUN_ID=${{ github.run_id }}-${{ github.run_attempt }}`
- `actions/upload-artifact@v4` with name `backup-${{ github.run_id }}`, path `backup-out/*.age`, `retention-days: 90`, `if-no-files-found: error`

The non-empty and heartbeat checks in `dump.sh` (Step 4.3) cover Review Focus #1. Note that `postgresql-client` from Ubuntu may be older than the server. That's fine here because `supabase db dump` runs `pg_dump` inside Docker at the matching version, and `psql` is only used for the heartbeat insert.

- [ ] **Step 6: `scripts/backup/restore-check.sh`**

Behaviour:
1. Decrypt the three files with `age -d -i <identity>` into a `mktemp -d`.
2. Create a throwaway stack in another `mktemp -d`: `npx supabase init`, set `project_id = "restore-check"`, and shift every port in its `config.toml` by +1000 (api 55321, db 55322, studio 55323, inbucket 55324, analytics 55327, pooler 55329) so it can run alongside the dev stack. Then `npx supabase start --workdir <dir>` (fresh, with no migrations).
3. Run the documented restore against `postgresql://postgres:postgres@127.0.0.1:55322/postgres`:
   `psql --single-transaction -v ON_ERROR_STOP=1 -f roles.sql -f schema.sql -c 'SET session_replication_role = replica' -f data.sql`
   If it fails on the known lines (`ALTER … OWNER TO "supabase_admin"` in schema.sql, `GRANT "postgres" TO "cli_login_postgres"` in roles.sql), comment those lines out with `sed` before running, as the Supabase docs advise. Document this in `backups.md`.
4. `psql … -tAc "select count(*) from public.backup_heartbeat where run_id = '<expected>'"` must print `1`.
5. Always `npx supabase stop --workdir <dir> --no-backup` (in a `trap`), and remove the temp directories.

- [ ] **Step 7: Prove it end to end**

A new `workflow_dispatch` workflow can't be dispatched until GitHub has registered it (it is on the default branch, or has run once). So commit the files now (Step 10's command), add a temporary `push: branches: [feat/foundation]` trigger in its own commit, push, and `gh run watch` the run it starts. Remove the trigger in its own commit once Step 8 passes; later runs, including Task 7's, can then use `gh workflow run backup.yml --ref <branch>`.
Expected: a green run and an artifact `backup-<run_id>` with three `.age` files.
If it fails on connection: confirm the URI's user is `postgres.<ref>` (not `postgres`), the port is `5432` (session mode, not 6543), and the password has no unescaped URL characters (percent-encode them). Record any fix in `backups.md`.

- [ ] **Step 8: Restore check**

```bash
gh run download <run_id> -n backup-<run_id> -D /tmp/abd-restore
scripts/backup/restore-check.sh /tmp/abd-restore ~/.config/a-balanced-diet/backup.agekey <run_id>-1
```
Expected: exit 0, prints `restore check OK: heartbeat <run_id>-1 found`.

- [ ] **Step 9: Document `docs/operations/backups.md`**: what runs and when, where the artifacts are, how long they're kept (90 days), how to restore (the Step 8 commands, plus the vault root-key caveat from Supabase's docs: retrieve the old project's root encryption key *before* deleting it, or Task 6's Vault secrets cannot be decrypted), and the pause behaviour (a failed nightly run is the early warning that the project paused; resume it in the dashboard).

- [ ] **Step 10: Commit**

```bash
git add supabase scripts .github docs/operations
git commit -m "feat: :floppy_disk: add nightly encrypted backup with restore check"
```

---

### Task 3: Reference data schema and EAT-Lancet 2025 seed

**Files:**
- Create: `supabase/migrations/<ts>_reference_data.sql`, `supabase/seed/eat_group.sql` (included from `supabase/seed.sql`), `supabase/tests/database/10_reference_data.test.sql`
- Modify: `supabase/config.toml` (`[db.seed] sql_paths = ['./seed.sql']`)

**Interfaces:**
- Produces enums: `group_unit ('g','mg')`, `range_basis ('grams','energy_share')`, `weight_basis ('as_eaten','dry','milk_equivalent')`, `score_type ('shortfall','excess')`.
- Produces `public.eat_group(code text primary key, name text not null, unit group_unit not null, default_per_day numeric, range_min numeric, range_max numeric, range_basis range_basis not null default 'grams', energy_share_min numeric, energy_share_max numeric, weight_basis weight_basis not null, score_type score_type not null, ref_kcal_per_day numeric, sort_order int not null)`.
- Produces `public.nutrient(code text primary key, name text not null, unit text not null check (unit in ('g','mg','µg','kcal')), is_label_set boolean not null, reference_intake numeric, reference_source text)`.
- Produces `public.co2e_factor(id uuid primary key default gen_random_uuid(), category text not null, kg_co2e_per_kg numeric not null check (kg_co2e_per_kg >= 0), source text not null, system_boundary text, confidence text check (confidence in ('high','medium','low')))`. It is left empty here and filled by Plan 3.
- Produces `public.scottish_baseline(code text primary key, value numeric not null, unit text not null, source text not null, year text not null, caveat text)`.
- All four: RLS enabled, with policy `select to authenticated using (true)`. No insert, update or delete policies (only the service role writes).

- [ ] **Step 1: Failing test `10_reference_data.test.sql`**

```sql
-- Exactly the 16 groups of Table 1, EAT-Lancet 2025 (full paper, p. 9)
select results_eq('select count(*)::int from public.eat_group', array[16]);
select results_eq($$select default_per_day, energy_share_min, energy_share_max, range_basis::text, weight_basis::text
                    from public.eat_group where code = 'whole_grains'$$,
                  $$values (210::numeric, 0.20::numeric, 0.50::numeric, 'energy_share', 'dry')$$);
select results_eq($$select range_min, range_max, weight_basis::text from public.eat_group where code = 'dairy'$$,
                  $$values (0::numeric, 500::numeric, 'milk_equivalent')$$);
select results_eq($$select unit::text, range_max from public.eat_group where code = 'sodium'$$,
                  $$values ('mg', 2000::numeric)$$);
select results_eq($$select score_type::text from public.eat_group where code in ('vegetables','fruits','legumes','whole_grains','nuts','unsaturated_oils') group by 1$$,
                  $$values ('shortfall')$$);
-- authenticated can read, anon cannot
set local role anon;
select throws_ok('select * from public.eat_group', '42501');
```
(Use `plan(n)` and `finish()` in the same wrapper as Task 1.)

- [ ] **Step 2: Run it.** `npm run db:reset && npm run db:test`, expected FAIL.

- [ ] **Step 3: Migration and seed.** Seed values copied from the full 2025 paper, Table 1:

| code | name | unit | default | min | max | basis | weight basis | score type | ref kcal | order |
|---|---|---|---|---|---|---|---|---|---|---|
| whole_grains | Whole grains | g | 210 | – | – | energy_share 0.20–0.50 | dry | shortfall | 735 | 1 |
| starchy_roots | Tubers and starchy roots | g | 50 | 0 | 100 | grams | as_eaten | excess | 50 | 2 |
| vegetables | Vegetables | g | 300 | 200 | 600 | grams | as_eaten | shortfall | 95 | 3 |
| fruits | Fruits | g | 200 | 100 | 300 | grams | as_eaten | shortfall | 145 | 4 |
| nuts | Tree nuts and peanuts | g | 50 | 0 | 75 | grams | as_eaten | shortfall | 275 | 5 |
| legumes | Legumes | g | 75 | 0 | 150 | grams | dry | shortfall | 275 | 6 |
| dairy | Milk or equivalents | g | 250 | 0 | 500 | grams | milk_equivalent | excess | 145 | 7 |
| poultry | Chicken and other poultry | g | 30 | 0 | 60 | grams | as_eaten | excess | 60 | 8 |
| fish | Fish and shellfish | g | 30 | 0 | 100 | grams | as_eaten | excess | 25 | 9 |
| eggs | Eggs | g | 15 | 0 | 25 | grams | as_eaten | excess | 20 | 10 |
| red_meat | Beef, pork or lamb | g | 15 | 0 | 30 | grams | as_eaten | excess | 45 | 11 |
| unsaturated_oils | Unsaturated plant oils | g | 40 | 20 | 80 | grams | as_eaten | shortfall | 355 | 12 |
| palm_coconut_oil | Palm and coconut oil | g | 6 | 0 | 8 | grams | as_eaten | excess | 55 | 13 |
| animal_fats | Lard, tallow and butter | g | 5 | 0 | 10 | grams | as_eaten | excess | null | 14 |
| sugar | Sugar (added or free) | g | 30 | 0 | 30 | grams | as_eaten | excess | 115 | 15 |
| sodium | Sodium | mg | null | 0 | 2000 | grams | as_eaten | excess | null | 16 |

Nutrient seed (label set `true`; micronutrients `false`; reference intakes are UK adult RNIs/RIs. The implementer fills `reference_intake` from the SACN/COMA tables and cites the source in `reference_source`): `energy_kcal` (kcal), `fat` (g), `saturates` (g), `carbohydrate` (g), `sugars` (g), `fibre_aoac` (g), `protein` (g), `salt` (g), `vitamin_b12` (µg), `iron` (mg), `calcium` (mg), `iodine` (µg), `vitamin_d` (µg), `zinc` (mg), `folate` (µg), `omega3_total` (g).

Scottish baseline seed: `household_food_waste_edible_kg_per_person_year` = 63, unit `kg/person/year`, source `Zero Waste Scotland, Household food waste in Scotland 2021/22 (460,000 t; 73% edible)`, year `2021/22`, caveat `"edible" used as proxy for "avoidable"; derived from 460,000 t × 0.73 ÷ population`. The diet CO2e baseline is left for Plan 3.

- [ ] **Step 4: Run tests.** `npm run db:reset && npm run db:test`, expected PASS.

- [ ] **Step 5: Commit**: `feat: :seedling: add reference tables and eat-lancet 2025 targets`

---

### Task 4: Food library schema with visibility rules

**Files:**
- Create: `supabase/migrations/<ts>_food_library.sql`, `supabase/tests/database/20_food_library.test.sql`, `supabase/tests/helpers/helpers.psql` (test helpers; deliberately outside `tests/database/` and not ending `.sql`, so `supabase test db` doesn't run it as a test)

**Interfaces:**
- Produces helper (test-only, in `supabase/tests/helpers/helpers.psql`, sourced at the top of each test file with `\ir ../helpers/helpers.psql`; it creates schema `tests` inside the test transaction, so nothing reaches migrations): `tests.create_user(email text) returns uuid` (inserts into `auth.users`) and `tests.act_as(uid uuid)`, which does `set local role authenticated; perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true)` (`SET` can't take an expression).
- Produces enums: `food_source ('user','cofid','off','ai','manual')`, `visibility ('private','shared','public')`, `food_state ('raw','dry','cooked','as_eaten')`, `colour_kind ('solid','soup_sauce','drink')`, `colour ('green','yellow','orange')`, `shares_status ('none','guessed','confirmed','derived')`.
- Produces `public.food_family(id uuid pk, name text not null, reference_state food_state not null)`. Read: authenticated. Write: service role only.
- Produces `public.food`:
  - `id uuid pk`, `name text not null`, `source food_source not null`, `source_ref text`
  - `visibility visibility not null`, `owner_id uuid references auth.users on delete cascade`, `derived_from uuid references food(id)`
  - `family_id uuid references food_family(id)`, `family_yield numeric check (family_yield > 0)` (grams of family reference state per gram of this food)
  - `state food_state not null default 'as_eaten'`, `colour_kind colour_kind not null default 'solid'`, `colour_override colour`
  - `kcal_per_100g numeric check (kcal_per_100g >= 0)`, `nutrients_per_100g jsonb not null default '{}'` (keys = `nutrient.code`; absent key = unknown)
  - `wholegrain_fraction numeric check (wholegrain_fraction between 0 and 1)`, `milk_eq_energy_factor numeric`, `milk_eq_milk_used_factor numeric`
  - `co2e_kg_per_kg numeric`, `co2e_factor_id uuid references co2e_factor(id)`, `shares_status shares_status not null default 'none'`
  - plus the global sync columns
  - constraints: `check ((visibility = 'private') = (owner_id is not null))`; `unique (source, source_ref) where visibility = 'shared'` (partial unique index)
- Produces `public.food_group_share(food_id uuid references food(id) on delete cascade, group_code text references eat_group(code), grams_per_100g numeric not null check (grams_per_100g >= 0), primary key (food_id, group_code))`.
- Produces `public.food_unit(id uuid pk, food_id uuid not null references food(id) on delete cascade, label text not null, grams numeric not null check (grams > 0), unique (food_id, label))`.
- Produces `public.dish_breakdown(id uuid pk, owner_id …, dish_food_id uuid not null references food(id), ingredient_food_id uuid not null references food(id), grams_per_100g_dish numeric not null check (grams_per_100g_dish > 0), sync columns, unique (owner_id, dish_food_id, ingredient_food_id))`.
- RLS:
  - `food` select: `visibility in ('shared','public') or owner_id = auth.uid()`.
  - `food` insert and update: `with check (visibility = 'private' and owner_id = auth.uid())`; update additionally `using (owner_id = auth.uid())`.
  - `food` delete: no policy (soft delete via `deleted_at`).
  - `food_group_share` and `food_unit`: select if the parent food is visible; write if the parent food's `owner_id = auth.uid()`.
  - `dish_breakdown`: owner only, for all commands.

- [ ] **Step 1: Failing tests `20_food_library.test.sql`**, named:
  - `private_food_visible_only_to_owner`: user A inserts a private food; as B, `count = 0`; as A, `count = 1`.
  - `shared_food_visible_to_all`: insert as `postgres` a shared CoFID food; both A and B see it.
  - `user_cannot_insert_shared`: as A, insert with `visibility='shared', owner_id=null` → `throws_ok(…, '42501')`.
  - `food_visibility_cannot_escalate` (Review Focus #2): as A, `update food set visibility='shared', owner_id=null where id=<A's food>` → `throws_ok '42501'`; and `update … set owner_id=<B>` → `throws_ok '42501'`.
  - `user_cannot_edit_shared_food`: as A, an update of a shared food affects 0 rows (`results_eq` on `update … returning 1` → empty).
  - `group_share_follows_parent`: A can insert shares for their own private food; inserting shares for a shared food → `throws_ok '42501'`.
  - `food_hard_delete_blocked_when_referenced` (Review Focus #4): this goes in Task 5's test file once `log_entry` exists; here assert that `authenticated` has no delete policy (`delete … returning 1` as A → empty).
  - `wholegrain_fraction_bounds`: inserting 1.2 → `throws_ok '23514'`.

- [ ] **Step 2: Run.** `npm run db:test`, expected FAIL.
- [ ] **Step 3: Write the migration** to satisfy the Interfaces. Add the shared `set_updated_at()` trigger function here (`before update … for each row`), which Task 5 reuses.
- [ ] **Step 4: Run.** `npm run db:reset && npm run db:test`, expected PASS.
- [ ] **Step 5: Commit**: `feat: :lock: add food library with visibility rls`

---

### Task 5: Per-user tables (targets, plan, log, cupboard, shopping, weight)

**Files:**
- Create: `supabase/migrations/<ts>_user_data.sql`, `supabase/tests/database/30_user_data.test.sql`

**Interfaces:**
- Consumes: `food`, `eat_group`, `set_updated_at()` and the test helpers from Task 4.
- Produces enums: `group_status ('excluded','allowed','favoured')`, `dairy_basis ('energy','milk_used')` default `'energy'`, `base_pattern ('flexitarian','pescatarian','vegetarian','vegan')` default `'flexitarian'`, `meal_slot ('breakfast','lunch','dinner','snacks')`, `movement_reason ('bought','eaten_logged','went_off','gave_away','eaten_unlogged','stock_correction')`.
- Produces tables (all with the global owner and sync columns; RLS: owner-only for `select`, `insert`, `update`; **no** delete policy, so soft delete only):
  - `profile_targets(owner_id pk, kcal_target int not null check (kcal_target between 800 and 6000), protein_floor_g numeric not null, fibre_floor_g numeric not null, fibre_soft_ceiling_g numeric, colour_split jsonb not null default '{"green":0.5,"yellow":0.3,"orange":0.2}', colour_tolerance_pts numeric not null default 3, dairy_basis …, base_pattern …, wholegrain_goal numeric not null default 0.75 check (wholegrain_goal between 0 and 1), setup_completed_at timestamptz)`. The `colour_split` values must sum to 1 (check with tolerance 0.001).
  - `profile_group_setting(owner_id, group_code references eat_group, status group_status not null default 'allowed', pinned_per_day numeric, primary key (owner_id, group_code))`.
  - `plan(id pk, owner_id, effective_from date not null, groups jsonb not null, expected jsonb not null, accepted_at timestamptz not null default now())`. `groups` = `{group_code: per_day}`; `expected` = `{kcal, protein_g, fibre_g, colour_split}`.
  - `log_entry(id pk, owner_id, day date not null, slot meal_slot not null, food_id uuid not null references food(id) on delete restrict, quantity_g numeric not null check (quantity_g > 0), unit_id uuid references food_unit(id), unit_count numeric, from_cupboard boolean not null default false, breakdown jsonb, snapshot jsonb not null)`.
  - `cupboard_item(id pk, owner_id, food_id references food(id) on delete restrict, quantity_g numeric not null check (quantity_g >= 0), added_at timestamptz not null default now())`.
  - `cupboard_movement(id pk, owner_id, cupboard_item_id uuid references cupboard_item(id), food_id uuid not null references food(id) on delete restrict, reason movement_reason not null, quantity_g numeric not null check (quantity_g > 0), log_entry_id uuid references log_entry(id), created_at timestamptz not null default now())`. RLS: **select and insert only**, so it is append-only.
  - `shopping_item(id pk, owner_id, food_id references food(id) on delete restrict, quantity_g numeric not null check (quantity_g > 0), unit_id uuid references food_unit(id), unit_count numeric, ticked_at timestamptz)`.
  - `weight_entry(id pk, owner_id, day date not null, kg numeric not null check (kg between 20 and 400), unique (owner_id, day))`.
- Indexes: `(owner_id, updated_at)` on every table here (for the sync pull "changed since"), `log_entry (owner_id, day)`, and `log_entry (owner_id, created_at desc)` (for "repeat a meal", most recent first).

- [ ] **Step 1: Failing tests `30_user_data.test.sql`**, named:
  - `owner_isolation_<table>` for each of the 8 tables: A inserts a row; B sees 0 rows and B's `update … returning 1` is empty.
  - `owner_id_defaults_to_caller`: as A, insert without `owner_id`; the stored value equals A's uid.
  - `cannot_insert_for_other_user`: as A, insert with `owner_id = B` → `throws_ok '42501'`.
  - `movement_is_append_only` (Review Focus #3): as A, `update cupboard_movement …` and `delete from cupboard_movement …` with `returning 1` are both empty, and the row is unchanged.
  - `food_hard_delete_blocked_when_referenced` (Review Focus #4): as `postgres`, `delete from food where id = <food used in A's log_entry>` → `throws_ok '23503'`.
  - `colour_split_must_sum_to_one`: `{"green":0.5,"yellow":0.3,"orange":0.3}` → `throws_ok '23514'`.
  - `updated_at_moves_on_update`: update a row and assert `updated_at` is greater than its insert value (use `clock_timestamp()` in the trigger, since `now()` is fixed within a transaction).
  - `one_weight_per_day`: a second weight row for the same day → `throws_ok '23505'`.

- [ ] **Step 2: Run.** Expected FAIL.
- [ ] **Step 3: Migration.** Use `clock_timestamp()` in `set_updated_at()` (change Task 4's function in this migration if it used `now()`).
- [ ] **Step 4: Run.** `npm run db:reset && npm run db:test`, expected PASS.
- [ ] **Step 5: Commit**: `feat: :card_file_box: add per-user tables with owner rls`

---

### Task 6: Per-user Anthropic key storage (Vault)

**Files:**
- Create: `supabase/migrations/<ts>_user_secrets.sql`, `supabase/tests/database/40_user_secrets.test.sql`

**Interfaces:**
- Consumes: the Vault extension (`vault.create_secret`, `vault.update_secret`, `vault.decrypted_secrets`), available on Supabase by default.
- Produces `public.user_secret(owner_id uuid references auth.users on delete cascade, kind text not null check (kind in ('anthropic_api_key')), vault_secret_id uuid not null, updated_at timestamptz not null default now(), primary key (owner_id, kind))`. RLS enabled with **no** policies (callers can't read it directly).
- Produces `public.set_my_secret(p_kind text, p_value text) returns void`: `security definer`, `set search_path = ''`. Creates or updates the Vault secret named `user:<uid>:<kind>` and upserts `user_secret`. Raises if `auth.uid()` is null or `p_value` is under 20 characters.
- Produces `public.has_my_secret(p_kind text) returns boolean`: `security definer`.
- Produces `public.clear_my_secret(p_kind text) returns void`: `security definer`; deletes from Vault and from `user_secret`.
- Produces `private.get_user_secret(p_owner uuid, p_kind text) returns text` in schema `private`: `security definer`, with `execute` granted **only** to `service_role`, for Plan 4's Edge Function.
- Grants: `execute` on the three `public` functions to `authenticated` only; revoke from `public` and `anon`.

- [ ] **Step 1: Failing tests `40_user_secrets.test.sql`**:
  - `set_and_has_secret`: as A, `set_my_secret('anthropic_api_key', 'sk-ant-test-0123456789abcdef')` then `has_my_secret(…)` → true; as B → false.
  - `secret_value_never_selectable` (Review Focus #5): as A, `select * from public.user_secret` → 0 rows; `select * from vault.decrypted_secrets` → `throws_ok '42501'`; `select private.get_user_secret(A, 'anthropic_api_key')` → `throws_ok '42501'`.
  - `service_role_can_read`: `set local role service_role`; `private.get_user_secret(A, …)` returns the original string.
  - `clear_secret`: after `clear_my_secret`, `has_my_secret` → false and no Vault row named `user:<A>:anthropic_api_key` remains.
  - `anon_cannot_call`: as `anon`, `set_my_secret(…)` → `throws_ok '42501'`.
- [ ] **Step 2: Run.** Expected FAIL.
- [ ] **Step 3: Migration.**
- [ ] **Step 4: Run.** `npm run db:reset && npm run db:test`, expected PASS.
- [ ] **Step 5: Commit**: `feat: :key: add vault-backed per-user api key storage`

---

### Task 7: Deploy to the hosted project and re-prove the backup

**Files:**
- Modify: `docs/operations/backups.md`, `README.md` ("Deploying" section)
- Create: `docs/operations/deploy.md`

- [ ] **Step 1: Check the Postgres version.** `psql "$SUPABASE_DB_URL" -tAc 'show server_version'`. If the major version isn't 17, set `[db] major_version` to match, then run `npm run db:reset && npm run db:test` and commit.
- [ ] **Step 2: Link and push migrations.** `npx supabase link --project-ref <ref>`, then `npx supabase db push`. Expected: all migrations applied. Then `npx supabase db push --include-seed`, *only if* the CLI supports it for hosted projects; otherwise run `psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/eat_group.sql` (and the other seed files). Record which in `deploy.md`.
- [ ] **Step 3: Auth settings on the hosted project.** Run `npx supabase config push` if the installed CLI supports it (check `--help`); otherwise set them in the dashboard: *Authentication → Sign In / Providers → Allow new users to sign up: off*, and *Email → Confirm email: off*. Verify with `curl -s -X POST "$SUPABASE_URL/auth/v1/signup" -H "apikey: $ANON_KEY" -H 'content-type: application/json' -d '{"email":"probe@example.com","password":"probe-password-123"}'`. Expected: an error mentioning that signups are disabled.
- [ ] **Step 4: USER STEP: create the owner account** in the dashboard (*Authentication → Users → Add user*, email and password, "auto confirm"). This is the user's own account, used from the app later.
- [ ] **Step 5: Smoke-test RLS on hosted.** With the anon key and the owner's session (`curl …/auth/v1/token?grant_type=password`), `GET /rest/v1/eat_group?select=code` returns 16 rows. Without a session (anon key only), the same request returns `401`/`42501` or an empty array, and **not** 16 rows.
- [ ] **Step 6: Re-run the backup** (`gh workflow run backup.yml --ref feat/foundation`) and the restore check (Task 2, Step 8). Additionally assert in `restore-check.sh` that `select count(*) from public.eat_group` = 16 after the restore. Expected: both pass.
- [ ] **Step 7: Commit, push and open a PR**

```bash
git add docs README.md scripts supabase
git commit -m "docs: :rocket: document deployment and verify hosted backup"
git push -u origin feat/foundation
gh pr create --base main --title "feat: :construction: foundation schema, rls, auth and backups" --body "<summary + test evidence + the restore check output>"
```

---

## Self-review notes

- **Spec coverage:** §3 users and auth → Tasks 1, 7. §4 free tier and pooler → Tasks 2, 7. §5 auth and secrets → Tasks 1, 6, 7. §6 data model → Tasks 3–6. §7.3 settled values (dry, energy-share grains, milk equivalents, sodium) → Task 3 seed. §9.4 score types → Task 3 seed. §12 backups, pause and secrets → Task 2. `scottish_baseline` waste value → Task 3. Items deferred by design: colour, score, optimiser (Plan 2); CoFID, CO2e factors, family and yield data, diet CO2e baseline (Plan 3); sync engine, screens, Open Food Facts and AI functions (Plan 4).
- **Not covered here, on purpose:** `food.colour` is computed client-side (Plan 2), so it has no column beyond `colour_override`.
