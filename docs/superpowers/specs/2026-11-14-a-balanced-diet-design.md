# A Balanced Diet: design

*Status: draft for approval · 2026-11-14*

## 1. Intent and why

This is a personal phone app for shopping, cupboard stock-taking and diet tracking. It is built on the **EAT-Lancet Planetary Health Diet (2025)**, adjusted for calorie restriction (for the owner, currently 1,750 kcal/day while working towards a goal weight) and evidence-based protein and fibre floors.

The user shops little and often and checks the cupboard before shopping. Today they keep the list as a text to themselves and log food in Noom, where they often have to pick a similar product as a stand-in and where the barcode scanner never works. The app replaces both: a shopping list that shows what each purchase uses from the week's EAT-Lancet quota, a virtual cupboard filled by ticking items off that list, and a food log that shows the Noom-style colour (green, yellow, orange), the quota impact and the nutrition of everything eaten. The headline measure of a good week is a **rolling 7-day EAT-Lancet score**. CO2e and avoidable food waste are shown as secondary measures against Scottish averages.

## 2. Goals, non-goals and anti-goals

**Goals**
- The home screen answers "where am I today?" (colour budgets, kcal, protein, fibre) and "how am I doing this week?" (the rolling EAT score) at a glance.
- Logging is at least as fast as Noom. Proxy dishes, "repeat a past meal" and simple counts make that possible.
- The cupboard stays roughly true with little effort: it fills from the shopping list and empties when food is eaten or binned.
- Targets can be re-optimised when calories, protein or fibre goals change.
- Several fully separate users are supported from day one.

**Non-goals (v1)**
- Barcode scanning.
- Use-by and best-before dates, or nudges about them.
- Suggestions about when to revisit targets (that is the user's call).
- Alcohol, coffee, tea and cocoa quotas.
- Shared kitchens or shared cupboards between users.
- Public recipe sharing (the data model allows for it; there is no UI).
- A native Android app.

**Anti-goals (failure even if it technically works)**
- **Imperial units anywhere.** Use grams, ml, kcal and simple counts ("2 medium apples"). No cups, ounces, pounds or handfuls.
- Logging that is slower or fussier than Noom.
- Breaking or losing data when offline in a shop.
- Presenting estimates as precision. Uncertain data (unknown micronutrients, guessed CO2e) must look uncertain, never like a confident zero.
- Running costs above £0/month for this scale of use.

## 3. Decisions made by the user

| Area | Decision |
|---|---|
| Platform | **PWA**, installed from Chrome or Firefox (not Klar) so Klar's auto-clearing doesn't affect it. No APK for now; it can be wrapped later. |
| Backend | **Supabase free tier** (Postgres, Auth, row-level security, Edge Functions). |
| Backups | A scheduled `pg_dump` (e.g. a GitHub Action). The user has had trouble with GitHub Actions and the session pooler before, so this must be proven early (§12). |
| Users | Multiple users, **completely separate** (own targets, plan, cupboard, logs, shopping list). A shared kitchen is a later idea. |
| Diet base | Always starts from **EAT-Lancet 2025**: all 16 targets including sugar (added/free), palm/coconut oil, lard/tallow/butter and sodium. |
| Food groups | Driven by ethics. Each group is excluded, allowed or favoured; this changes rarely. Currently poultry is excluded, and wild venison, line-caught fish and eggs are the animal foods. |
| Targets that change | Calorie target, protein floor and fibre floor will change. The colour split (50/30/20 by kcal) is fairly stable. |
| Colour | Assigned **per food**, mainly by calorie density with protein density taken into account (Noom-like). Colour drives the *daily* colour budget; grams count separately against the *weekly* food-group quotas. |
| Mixed foods | Every food belongs to one or more EAT groups, split by weight (crisps → starchy roots + oil; beer → grain). No food is outside the groups. |
| Logging | Named slots (breakfast, lunch, dinner, snacks). Grams or simple counts. Proxy dishes allowed. "Repeat a meal" searches **any** past meal, most recent first. |
| "Made from my cupboard" | Off by default (eating out). When it's flagged, the app asks for an ingredient breakdown (suggested where possible), caches it per dish, uses the ingredients for nutrition, colour and quotas, and removes **only the portion eaten** from the cupboard. The cached breakdown is a starting point that can be edited each time. |
| Food lookup order | 1. User's library (their own and edited items, plus cached imports) → 2. CoFID → 3. Open Food Facts → 4. manual breakdown (cached) → 5. **optional** AI-suggested breakdown on request (cached). Anything imported from a third party is cached into the library. |
| Sharing of library items | Edits and the user's own dishes are **private**. Untouched third-party imports are **shared** across users. A **public** visibility level is reserved for future recipe sharing. |
| Waste | Recorded when an item is removed from the cupboard and the app asks why. Only "went off / binned"-type reasons count as waste. Only avoidable waste of edible food matters; peelings, tops and tails, and plate scraps are ignored. |
| Weekly score | **Rolling 7 days**, based **only on EAT-Lancet quotas**. Mainly rewards staying inside EAT ranges, gives extra credit for being close to personal targets, and is asymmetric by group type (shortfall vs excess). CO2e and waste are shown but not scored. |
| Home screen | **Layout A, daily budget first:** kcal left with green, yellow and orange bars; protein and fibre tiles; a 7-day score card with its top two "why" hints; one line with CO2e, waste and weight; a "+ Log food" button; bottom nav (Today, Shop, Cupboard, Plan). |
| Shopping list | **Option A, share of a week:** each item shows its colour dot and "% of a week's <group>"; the footer shows the basket's colour split (kcal) against 50/30/20. It does not factor in cupboard stock. |
| Nutrition shown | The label set **plus key micronutrients**. |
| Weight | A trend line next to calories, nothing more. |
| AI | Allowed as an optional, on-request step for dish breakdowns. **Each user supplies their own Anthropic API key**; there is no shared key and no owner-paid usage. Without a key the AI option is hidden. |
| Dairy conversion | Dairy counts in **milk equivalents**. Default: **by energy** (food kcal ÷ milk's ~0.58 kcal/g, the value the paper models with; skyr ≈ 1.1×, cheddar ≈ 7×). A **per-user setting** switches to **raw milk used** (strained yoghurt/skyr ≈ 3–4×, cheese ≈ 8–10×; factors per food in the pipeline). The setting has an **info tooltip** explaining that the energy basis favours diet over sustainability, because a kg of skyr takes several kg of milk to make. Switching recalculates quotas and the score and offers a re-optimise; past log snapshots are unchanged. |
| Refined grains | White bread, white rice, ordinary pasta and refined flour **count in the grains group** (whole-grains target), but the app **highlights the whole-grain share** of grains to push it ever higher (§9.5). |
| New users and history | Everyone starts **empty**: no Noom or other imports. **Every user, including the owner,** goes through the same short setup (targets, food-group status) from neutral EAT-Lancet defaults before the first optimiser run. Weight history arrives later through the Garmin sync, whose first run back-fills past weigh-ins. |
| Setup acceptance test | When the owner goes through setup with their real inputs, the optimiser should produce a plan **close to their existing spreadsheet plan** (allowing for the four extra groups the sheet lacks). That is the proof the optimiser works (§9.1). |

## 4. Constraints

- Free tiers only. Supabase Free: 500 MB database, 5 GB egress/month, 2 active projects, **paused after 7 days of low activity** (data kept and resumable; owners get emailed), **no backups included**, and the default email sender only sends to project team members at 2 emails/hour.
- On Supabase Free the direct database connection is IPv6-only, and GitHub-hosted runners lack IPv6, so external jobs must use the **session pooler (port 5432, IPv4)**.
- The PWA runs in Chrome or Firefox on Android. Auth must not depend on redirects through the default browser (Klar), so **no magic links and no OAuth**.
- Third-party licences: CoFID is under the Open Government Licence v3.0 (attribution needed). Open Food Facts is ODbL: the app must show attribution in its UI, and because imports are cached into a shared library that is never published, that library must not be made public as a database without honouring ODbL share-alike. CO2e datasets have their own licences, to be confirmed per source.
- Metric only, everywhere: code, data, UI and seed files.

## 5. Architecture

```
Android phone: installed PWA
├─ UI (React + TypeScript)
├─ Local store (IndexedDB) ← the primary copy of the user's data; fully works offline
├─ Optimiser (LP solver, runs on the phone)
└─ Sync engine ⇄ Supabase (when online)

Supabase (free)
├─ Postgres: shared reference data + per-user data (RLS)
├─ Auth: email + password, sign-up closed (invite-only)
└─ Edge Functions: Open Food Facts lookup proxy, AI breakdown (uses the calling user's own encrypted Anthropic key)

GitHub Actions (scheduled)
└─ pg_dump via the session pooler → encrypted backup (also keeps the project awake)

Offline data pipeline (Python, in the repo)
└─ CoFID + CO2e sources + EAT targets → seed SQL for the shared reference tables
```

Technology choices are the builder's unless marked as decided in §3. The suggested defaults are Vite and `vite-plugin-pwa`, Dexie for IndexedDB, `supabase-js`, a small WASM LP solver such as `glpk.js` or `highs-js`, and uv-managed Python for the pipeline.

**Local-first sync.** Every per-user row has a UUID primary key generated on the device, plus `updated_at` and `deleted_at` (soft delete). Changes queue locally and push when online; pulls fetch rows with `updated_at` later than the last sync. Last write wins per row, which is enough for one person on one or two devices. The app calls `navigator.storage.persist()` on first run.

**Auth.** Email and password with email confirmation **off**, and public sign-up **disabled**. The owner creates further users in the Supabase dashboard, so no SMTP setup is needed. Sessions persist in the installed PWA's own storage.

## 6. Data model (logical)

**Shared reference data** (readable by every authenticated user; writable only by the pipeline or service role):
- `eat_group`: the 16 EAT-Lancet 2025 targets. Fields: code, name, unit (g or mg), default/day, range min/max (for the ~2,400 kcal reference), weight basis (as eaten / dry equivalent), score type (see §9).
- `nutrient`: the label set plus key micronutrients, with UK reference intakes.
- `co2e_factor`: kg CO2e per kg, by food category, with source and confidence.
- `scottish_baseline`: comparison values with source, year and notes (§10).

**Library** (shared across users, or private to one, decided by `visibility`):
- `food`: name, `source` (user / cofid / off / ai / manual), `source_ref`, `visibility` (private / shared / public), `owner_id` (null when shared), `derived_from` (the food it was edited from), state (raw, cooked, dry, as eaten), nutrients per 100 g (null = **unknown**, never 0), kcal per g, colour (computed) plus an optional colour override, and CO2e per kg plus factor reference.
- `food_group_share`: for each food, a list of (EAT group, grams of group per 100 g of food). This is where dry equivalents live: 100 g of cooked lentils carries ~40 g of legumes (dry equivalent), and 100 g of crisps carries ~X g of starchy roots plus ~Y g of unsaturated oil.
- `food_family`: links the generic, raw/dry, cooked and branded forms of one food (e.g. "red lentils": dried, boiled, a branded pouch), with a **yield factor** per member relative to the family's reference state. *My call (from the builder check).* It's needed so that eating "lentils, boiled" can draw down "red lentils, dried" in the cupboard. `food.family_id` is nullable.
- `food.wholegrain_fraction`: 0–1 for foods in the grains group (wholemeal bread ≈ 1, white rice 0, a 50/50 loaf 0.5). Null = unknown.
- `food_unit`: simple count units per food ("1 medium apple = 182 g", "1 bar = 40 g"). Editable, metric weights only.
- `dish_breakdown`: ingredients for a proxy dish (food → grams per 100 g of dish), owned per user (private).

**Per-user data** (RLS: `owner_id = auth.uid()`):
- `profile_targets`: kcal target, protein floor, fibre floor, fibre soft ceiling, colour split and tolerance, per-group status (excluded / allowed / favoured), and per-group pins.
- `plan`: an optimiser output the user accepted (g/day per group plus expected totals), versioned with the date it took effect.
- `log_entry`: date (Europe/London day), slot, food or dish, quantity (g or count × unit), `from_cupboard` flag, and the breakdown used (a copy of the edited breakdown, so later edits don't rewrite history).
- `cupboard_item`: food, quantity on hand (g), added_at.
- `cupboard_movement`: an append-only ledger with reason (bought / eaten via log / went off / gave away / stock correction / other), quantity, and a link to the log entry if any. Waste = movements whose reason is waste.
- `shopping_item`: food, quantity, ticked state. Ticking it adds a "bought" movement to the cupboard.
- `weight_entry`: date and kg.

**Cupboard draw-down rule** (*my call*). When a "made from my cupboard" entry or breakdown uses ingredient F: deduct from cupboard items of the **same food**, then the **same family** (converted by yield factor), oldest first. If there's no match or not enough stock, show a quick picker ("take from: <similar items in the same EAT group> / skip"). Stock never goes negative, and a skip is recorded so nothing is silently lost.

**Group shares for non-CoFID foods** (*my call*). Open Food Facts imports get **auto-guessed** group shares from the OFF category and ingredient list (with ingredient percentages where OFF has them), plus colour kind (solid, liquid, soup/sauce), stored on the shared copy and marked "guessed". On first use the user sees the guess and can confirm or edit it; **an edit creates a private copy**, following the edit-is-private rule. User-made foods get their group shares in the add-food form, defaulting from the nearest CoFID or family match. A food with no group shares is allowed but shown as "unassigned" and nudges for a breakdown. It still counts towards kcal and colour.

**Per-user secrets.** Each user's Anthropic API key is stored server-side, encrypted (e.g. Supabase Vault, keyed by user), and only read by the AI Edge Function on that user's own requests. It is never returned to the client after entry.

Nutrition, colour, quota contribution and CO2e for a log entry are **computed** from the food, or its breakdown, **when the entry is saved or explicitly edited**, and stored as a snapshot on the entry. Reads use the snapshot, so history stays stable if library data later changes. The snapshot holds **both** dairy-equivalent contributions (energy basis and milk-used basis), so changing the dairy setting (§3) recalculates the score from the snapshot without rewriting history.

## 7. Food data

### 7.1 Sources and lookup order
1. **The user's library**: private items first, then shared cached imports.
2. **CoFID 2021** (McCance & Widdowson's Composition of Foods Integrated Dataset; Excel; OGL v3.0; 2,887 foods plus a 393-item "old foods" file). It covers generic foods and many cooked dishes, with full micronutrients. It is loaded wholesale into the shared library by the pipeline.
3. **Open Food Facts**: a live search via an Edge Function (one call per real user lookup, as their API terms require; never scraped in bulk). The chosen result is cached as a shared food. Usually it has the label set only.
4. **Manual breakdown**: the user builds the ingredient list; it is cached privately.
5. **AI breakdown (optional, on request)**: an Edge Function sends the dish name, portion and the user's candidate foods to the Claude API and returns an ingredient list mapped to library foods with gram amounts. The user reviews and edits it, then it is cached privately. Each user's own API key is used, held server-side only. The model is chosen at build time. The AI step also returns group shares and a colour kind for the dish.

### 7.2 Pipeline jobs (the data-engineering core)
- **CoFID → EAT groups.** Map each CoFID food to `food_group_share` rows. Single-ingredient foods map directly from the CoFID food-group code to an EAT group. Composite dishes get a breakdown where one can be derived; otherwise they are marked "needs breakdown" and only get group shares once the user (or AI) supplies one. The mapping is a reviewed CSV in the repo, not hidden logic.
- **Dry-equivalent conversion** for grains and legumes. Use CoFID's paired raw/dry and boiled entries (water content ratio) to derive yield factors, for example cooked lentils → dry lentils. Bread, tofu, peas and edamame need explicit factors; the user's spreadsheet notes these are the least certain numbers.
- **Colour.** Compute colour per food from as-eaten kcal/g (§8).
- **CO2e.** Attach CO2e per kg to each food (§10).
- **Unknown, not zero.** Missing nutrient values stay null, and the UI shows "unknown" or a lower-bound marker in totals.

### 7.3 Verified facts and open data questions
*Primary source: the full 2025 Commission paper (Table 1 and its footnotes, p. 9 and Panel 3), with the 2019 and 2025 summaries as cross-checks.*

- *Dry or cooked:* **settled as dry weight.** The full paper says grains are "210 g per day dry weight". The kcal column confirms it for legumes too: whole grains 210 g = 735 kcal (3.5 kcal/g) and legumes 75 g = 275 kcal (3.7 kcal/g). (The 2019 table is consistent: 232 g = 811 kcal.) For calculations the paper assumes legumes are 50% soy and 50% other legumes.
- *Whole grains range:* **settled, and energy-based.** "210 (20–50% of daily energy intake)": 210 g is a midpoint reference, "considering this to be flexible". So the optimiser and score use a constraint on energy share (grain kcal between 20% and 50% of the kcal target), not a gram range. At 1,750 kcal that's 350–875 kcal, roughly 97–243 g dry. The user's sheet (115 g ≈ 24% of energy) is in range.
- *Dairy basis:* **settled as milk equivalents; neither the paper nor appendix 1 defines the conversion.** Table 1 says "Milk or equivalents (eg, cheese) 250 (0–500)". Appendix 1 says "250 g/day (about 1 glass of milk or cheese equivalents)" and models it as 144 kcal (i.e. milk at ~0.58 kcal/g). It also notes "yoghurt may have specific benefits" and "if intakes of red meat and poultry are low, higher intakes of dairy foods would be reasonable". The conversion was a **user decision** (§3): by energy by default, with a setting to switch to raw milk used. Each dairy food therefore carries **two** factors (energy basis, milk-used basis), and the user's setting picks one at calculation time.
- *PHD at other energy intakes:* appendix 1 (pp 24–25, Table DP1) gives example **flexitarian, pescatarian, vegetarian and vegan** patterns, all at ~2,373 kcal. It does **not** give scaled versions for lower energy intakes. Their regional method: raise encouraged foods (fruit, vegetables, legumes, nuts, whole grains, oils) to their minimums, cap moderated foods (red meat, poultry, milk, eggs, fish, sugar, roots, oils) at their maximums, then **balance energy by varying grains**. So the "use the ranges unscaled" rule (§9.1) stands. *My call:* setup lets the user pick one of these four patterns as the optimiser's reference point (the objective's `default_g`) instead of the flexitarian Table 1 defaults; for the owner, pescatarian plus venison is the closest. Table DP1 also has a 10 g/day "other" group (28 kcal), which we ignore.
- *Sodium:* "<2" g/day (summary: <2,000 mg). Same thing.
- *Butter, lard, tallow:* the paper's kcal for these are "included with dairy and meats". That doesn't affect us, since we count each food's own kcal directly.
- *Saturated fats:* 2019 had one "saturated oils" target (11.8 g, 0–11.8); 2025 splits it into palm/coconut oil (6 g, 0–8) and lard/tallow/butter (5 g, 0–10). Use 2025.
- *Alcohol, coffee, tea, cocoa:* neither summary sets targets. The 2019 summary mentions alcohol only as a health risk factor. That supports keeping them parked (§13).
- *Free sugars:* check whether CoFID 2021 carries free/added sugars. If not, sugar-group grams come from the breakdown (the sugar ingredient) or are estimated from total sugars minus intrinsic sugars, and are flagged as estimated.
- *CoFID recipe proportions:* the public dataset doesn't appear to include ingredient proportions for recipes. The user guide should be checked; if they aren't there, dishes rely on steps 4 and 5.

## 8. Colour rule

Noom publishes the method (calorie density = kcal ÷ grams, with soups, sauces and drinks treated separately, alcohol and sodas bumped up a colour, and artificially sweetened drinks yellow) but not exact cutoffs. Defaults (all configurable):

| Kind | Green | Yellow | Orange |
|---|---|---|---|
| Solid foods (as eaten) | < 1.0 kcal/g | 1.0–2.4 | > 2.4 |
| Soups, sauces, spreads | < 0.5 kcal/ml | 0.5–1.0 | > 1.0 |
| Drinks | < 0.2 | 0.2–0.5 | > 0.5 |

Adjustments:
- **Protein density:** move up one colour (orange → yellow, or yellow → green) when protein is ≥ 20% of energy and kcal/g ≤ 2.4. The user has said skyr is green.
- **Fibre-rich whole foods:** whole grains and legumes as eaten may move up one colour when fibre is ≥ 3 g per 100 kcal (Noom treats several whole grains and legumes favourably).
- **Alcohol and sugary drinks:** down one colour.
- **Per-food manual override** always wins.

Colour is computed on the **as-eaten** state. Dry pasta or lentils in the cupboard take the colour of their cooked form when logged as eaten cooked. Acceptance check: the builder makes a list of ~30 of the user's regular foods, and the user marks any whose colour feels wrong. Thresholds get tuned once, then overrides handle the rest.

The plan's colour split is computed per group from the colours of that group's representative foods, so a group can be part green and part yellow.

## 9. Targets, optimiser and score

### 9.1 Optimiser (runs on the phone, the user accepts the result)
Decision variables are `x_g`, grams per day for each of the 16 groups (sodium in mg).

- **Bounds:** EAT range `[min_g, max_g]`. Excluded groups are fixed at 0. Pinned groups are fixed at the pinned value. The ranges are those in the report, which assumes ~2,400 kcal; they are *not* scaled down. The user's earlier spreadsheet tried scaling and found it infeasible at 1,750 kcal with a 20% orange share, so it used the defaults flexed within ranges. **Exception: whole grains**, whose range is 20–50% of energy (§7.3), is expressed as a linear constraint on grain kcal (0.20 × kcal target ≤ grain kcal ≤ 0.50 × kcal target), and its score uses the same energy-share band. Appendix 1's PHD versions at other energy intakes may replace the "don't scale" rule once we have it.
- **Per-group densities:** kcal, protein and fibre per gram of group, and the colour mix of the group's kcal, all from an editable "representative mix" per group. This mirrors the "per 100 g" inputs in the user's sheet, seeded from it, and can later be refreshed from what the user actually eats.
- **Constraints:** kcal within ±25 of the target; protein ≥ floor; fibre ≥ floor; each colour's kcal share within ±tolerance (default 3 points) of the split. These are linear because the kcal total is fixed within the band.
- **Objective:** minimise Σ weighted |x_g − default_g| / (max_g − min_g), plus a penalty for fibre above its soft ceiling, plus a pull towards max_g for favoured groups. Absolute values are handled with standard LP splitting.
- **If infeasible**, report which constraints conflict by relaxing tolerances in order (colour, then fibre ceiling) and say what was relaxed. Never fail silently.
- **Output:** a proposed plan beside the current one (per-group grams, kcal, protein, fibre, colour split), which the user accepts or rejects. Accepting it versions the `plan`.
- **No seeding:** every user, the owner included, starts from neutral EAT-Lancet defaults and goes through setup.
- **Acceptance test:** using the owner's inputs (1,750 kcal, 80 g protein floor, 30 g fibre floor, 50/30/20, poultry excluded, venison favoured, the sheet's per-100 g values as representative mixes), the optimiser must produce a plan close to the spreadsheet's (`planetary-health-diet-plan.xlsx`, Plan sheet), group by group. Because the sheet lacks sugar, palm/coconut oil and butter/lard (~205 kcal at defaults), some groups will be trimmed to make room. The test should check each difference is explained by that, and should also run once with those three groups pinned to 0 to compare like for like. Turn this into an automated test with tolerances.

### 9.2 Daily colour budget
Each colour's daily budget is its share of the kcal target: at 1,750 kcal and 50/30/20, that's green 875, yellow 525 and orange 350 kcal. The home screen shows kcal left per colour.

### 9.3 Weekly quotas
The weekly quota per group is the accepted plan's g/day × 7. The shopping list shows `item grams of group ÷ weekly quota`. Items in several groups show their main group, and the detail view shows every group.

### 9.4 Rolling 7-day EAT score (0–100)
For each group, let `a` be the average daily intake over the last 7 complete days plus today so far, pro-rated. *Builder: choose one consistent definition and show it in the UI.* Then:

- **In range** `[min, max]`: score = 70 + 30 × closeness to the personal target `t`, where closeness = 1 − |a − t| / (half the range width), floored at 0.
- **Out of range in the penalised direction:** the score falls linearly from 70 at the bound to 0 at 50% beyond it (for an "at most" group with max 30 g, 0 at 45 g).
- **Out of range in the tolerated direction:** score 60.
- **Group types (my call, editable):**
  - *Shortfall-penalised*: vegetables, fruit, legumes, whole grains, nuts, unsaturated oil.
  - *Excess-penalised*: red meat, poultry, eggs, fish, dairy, starchy roots, sugar, palm/coconut oil, lard/tallow/butter, sodium.
  - *Excluded groups* (user decision): **stay in the score**, since other users may well eat poultry. An excluded group keeps its EAT range for scoring (poultry 0–60 g) with a personal target of 0, so the in-range formula works without dividing by zero. Zero intake scores 100; any intake lowers it through the closeness term and is also flagged in the score card ("poultry eaten: 40 g this week").
- **Overall** = the unweighted mean across all 16 groups (weights configurable later).
- **"Why" hints:** the two lowest-scoring groups with a direction, for example "↓ legumes low", "↑ sugar near cap".

### 9.5 Whole-grain share
Refined grains count towards the grains quota (user decision), with a separate highlight:
- **Whole-grain share** = Σ(grain grams × wholegrain_fraction) ÷ Σ grain grams over the rolling 7 days.
- The user sets a **whole-grain goal** on the Plan screen (default 75%) and can raise it over time.
- It's shown in the grains row of the score breakdown, on grain items in the log and shopping list (a "refined" or "whole" tag), and as a "why" hint on the home score card when below the goal ("↑ whole-grain share 52%, goal 75%").
- It doesn't change the score number (keeping the score purely EAT-Lancet).

Alcoholic drinks and chocolate get group shares like any other food (beer → grains, wine → fruit, chocolate → sugar plus cocoa fat as palm/coconut-type oil or nuts by breakdown). Their kcal always counts.

## 10. Sustainability metrics

**CO2e for food eaten and wasted.** kg CO2e = food kg × factor (kg CO2e/kg). Source preference, for the builder to finalise:
1. **Rippin et al. 2021**, *PLoS ONE* 16(11): e0259418, CC-BY 4.0. It attaches GHG emissions to 98% (3,233) of CoFID items, so it maps natively to our main food source. **Check whether the linked values are published in the supporting information.**
2. **SU-EATABLE LIFE** (Petersson et al. 2021, *Scientific Data*; Figshare v2): 323 carbon-footprint items, literature-based, Europe-focused. A fallback by category.
3. Category-level Poore & Nemecek (2018) figures, via the 2026 FIO Food look-up table (200 categories, DOI 10.82147/013), as a last resort.

Each factor records its source and system boundary; values are typically farm-to-retail. Composite dishes sum their ingredients. Foods with no factor show "unknown".

**Waste.** kg of food from waste-reason cupboard removals, plus their CO2e. Removing part of an item is supported. Waste doesn't count towards diet quotas.

**Scottish comparison values** (stored in `scottish_baseline`, with source, year and caveats shown in the UI):
- *Household food waste:* Zero Waste Scotland, 2021/22. Households generated 460,000 t, 73% of it edible. That's ~86 kg per person per year in total, so roughly **63 kg/person/year edible ≈ 1.2 kg/week**. ZWS uses "edible" for this split; it is the closest match to "avoidable". Older figures differ (2021 Scottish Government review: 111 kg/person/year household), so the UI notes this.
- *Diet CO2e per person per day:* no clean Scottish figure has been found yet. The best candidate is the baseline in **Kennedy et al. 2026, *Nature Food*** (DOI 10.1038/s43016-026-01384-3), which models a representative sample of Scottish adults; to be extracted from the paper or its supplement. Fallback: the UK mean of 7.4 kg CO2e/day (Rippin et al. 2021), labelled "UK".
- Comparison is per day and rolling 7 days, the same as the user's own figures.

## 11. Screens

- **Today (home), layout A:** kcal left (big) with "eaten of target"; green, yellow and orange bars with kcal left; protein and fibre tiles with ✓ at the floor; a 7-day EAT score card with two "why" hints; a secondary line with CO2e/day vs the Scottish figure, waste kg over 7 days, and weight with a trend arrow; a "+ Log food" button; bottom nav Today / Shop / Cupboard / Plan. Tapping the score opens the per-group breakdown.
- **Log food:** choose a slot → search (lookup order in §7) or "Repeat a meal" (every past meal, most recent first) → amount in g or count × unit → preview of colour, colour-budget impact, group quota impact and nutrition → the "Made from my cupboard" toggle opens the breakdown editor (cached, suggested, or AI on request) → save. Entries can be edited and deleted, and past days can be back-filled.
- **Food / day detail:** the label set plus micronutrients against UK reference intakes, with unknowns shown as unknown; group contributions; CO2e.
- **Shop, option A:** add from the library; each row has a checkbox, colour dot, name and amount, and "% of a week's <group>". The footer shows the basket's colour split (kcal) against target. Ticking an item moves it to the cupboard (amount editable on tick).
- **Cupboard:** a list grouped by EAT group with amounts. Remove (all or part) → reason picker (went off / binned, gave away, eaten but not logged, stock correction). Manual add as well.
- **Plan:** targets (kcal, protein, fibre floor and soft ceiling, colour split), group status (excluded, allowed, favoured, pinned), representative mixes, "Re-optimise" → side-by-side proposal → accept. Also weight entry and the weight-vs-kcal trend.
- **First-run setup (all users, owner included):** kcal target, protein and fibre floors, colour split, food-group status (excluded, allowed, favoured), then the first optimiser run, starting from neutral EAT-Lancet defaults.
- **Settings:** account, dairy basis (energy / raw milk used, with the info tooltip), own Anthropic API key (optional; enables AI breakdowns), sync status and last sync, data sources and attributions (CoFID OGL, Open Food Facts ODbL, CO2e sources), export (JSON/CSV).

Visual design: clean, works in light and dark mode (follows the system), designed for phone width first. The mockups chosen in brainstorming live in `.superpowers/brainstorm/` for reference.

## 12. Operations

- **Backups:** a nightly GitHub Action runs `pg_dump` (client version ≥ the server's Postgres major version) against the **session pooler** connection string (IPv4), encrypts the dump (e.g. `age`), and stores it. Default destination: a GitHub Actions artifact with maximum retention; the user may choose another. This doubles as activity that keeps the free project from pausing. **This is the first thing to prove** (a throwaway dump and restore into a local Postgres). Fallback if it's unreliable: the same script run on a schedule from the user's own machine or homelab.
- **If paused:** the app keeps working offline and sync resumes after the user clicks "Resume" in the Supabase dashboard. The app shows "sync paused since <date>".
- **Secrets:** the Supabase service key goes only in Edge Function and GitHub Actions secrets; per-user Anthropic keys are encrypted in the database (§6). Neither is ever in the PWA bundle.
- **Migrations:** SQL migrations in the repo (Supabase CLI). Reference data is seeded from the pipeline output.

## 13. Parked for later

- Research into alcohol, coffee, tea and cocoa: look for work that balances health and sustainability for them.
- Shared kitchen (a shared cupboard and shopping list between users).
- Public recipe sharing (the `visibility = public` level already exists).
- Garmin Connect Personal API weight sync (opened 21 Oct 2026; read-only; personal key per user, no approval). **The user is to check that weight/body composition is included.** v1 uses manual weight entry. When built, the first sync back-fills all available past weigh-ins.
- Use-by dates and nudges.
- Land and water use metrics (SU-EATABLE LIFE has water footprints).
- An APK wrapper (Capacitor) if the PWA ever annoys.

## 14. Left to the builder

- Exact libraries, folder layout, component design and test strategy.
- Sync conflict details beyond last-write-wins per row.
- Exact list of micronutrients (suggested: B12, iron, calcium, iodine, vitamin D, zinc, folate, omega-3) and the UK reference intake source (SACN/COMA RNIs).
- Default count units and portion weights.
- The CoFID → EAT-group mapping, as a reviewed CSV.
- Colour threshold tuning, after the user's ~30-food check.
- Score definition details marked "builder" in §9.4.
- Confirming the open data questions in §7.3 and §10, and recording what was found.

## 15. Sources

- EAT-Lancet 2025 summary report: https://eatforum.org/wp-content/uploads/2026/04/EL_Summary-Report_2025_v1.pdf (Figure 1, p. 11)
- EAT-Lancet 2025 Commission, *The Lancet* 406(10512): 1625–1700, DOI 10.1016/S0140-6736(25)01201-2
- CoFID 2021: https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid
- Open Food Facts data and licence: https://world.openfoodfacts.org/data
- Rippin et al. 2021, *PLoS ONE*, DOI 10.1371/journal.pone.0259418
- SU-EATABLE LIFE: https://figshare.com/articles/dataset/SU-EATABLE_LIFE_a_comprehensive_database_of_carbon_and_water_footprints_of_food_commodities/13271111
- Kennedy et al. 2026, *Nature Food*, DOI 10.1038/s43016-026-01384-3
- Zero Waste Scotland, household food waste 2021/22: https://www.zerowastescotland.org.uk/resources/household-food-waste-scotland-2021-22
- Noom colour system: https://www.noom.com/support/faqs/using-the-app/logging-and-tracking/food-and-water/2025/10/how-nooms-food-color-system-works/
- Supabase pricing, pausing, compute, SMTP and IPv4 docs: supabase.com/pricing, /docs/guides/platform/free-project-pausing, /docs/guides/auth/auth-smtp, /docs/guides/platform/ipv4-address
- Garmin Connect Developer Program: https://developer.garmin.com/gc-developer-program/overview
- User's plan spreadsheet: `planetary-health-diet-plan.xlsx` (reference only, not committed)
