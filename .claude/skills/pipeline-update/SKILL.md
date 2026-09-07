---
name: pipeline-update
description: Use this whenever working on index.html in the Tracking-companies repo — TFGI's VC pipeline tracker, a single-page app with no backend. Trigger it any time Troy asks to update, sync, refresh, or check the pipeline; check Attio for new, tracked, or missed companies; add a company to the tracker (Key or general); move a company's date/quarter, mark something "raising now," push a round out, or remove a company; or asks to populate/verify company info from Attio or Specter. Also consult it any time you're about to hand-edit the `const CO = [...]` array directly, even if the request doesn't use any of these exact words — it documents the data model, the Attio/Specter lookup process, the dating methodology, the house style, and the validation step this file needs before every commit.
---

# Pipeline update (TFGI Tracking-companies)

`index.html` is the whole app: no backend, no build step, no framework beyond
Tailwind loaded from a CDN. Every company lives as one JS object literal in
`const CO = [...]` inside the single `<script>` block. There's no type system
and no build-time check — the only thing standing between an edit and a
broken page is the validation script in `scripts/validate.sh`. Treat that as
non-negotiable.

## The data model

Each entry in `CO` is one company:

| Field | Meaning |
|---|---|
| `id` | slug, unique, kebab-case |
| `tier` | `1` = "Key Companies" (only set this when explicitly asked — see below), `2` = "Other" |
| `q` | calendar column: `'active'`, `'q3-2026'`, `'q4-2027'`, ... or `'tbd'` if undated |
| `raising` | bool — reserved for near-term urgency, see dating section |
| `dc` | bool — shows the ★ "company contact" star; true once there's been real direct contact (email, call, meeting), not just an Attio record existing |
| `name`, `sector`, `desc` | display fields |
| `sb`, `st` | Tailwind bg/text classes for the sector chip — reuse existing pairs, see Style below |
| `stage` | current funding stage, e.g. `'Series A ($15.4M, Jul 2025)'` |
| `nr` | the **next** round label, e.g. `'Series B'` — must be the real next round, not a generic placeholder |
| `nrd` | the display date, kept in sync with `q` (e.g. `'Q4 2026'`, `'Active Now'`, `'TBD'`) |
| `lc` | last contact date, or `'—'` if none |
| `ct` | one-line contact summary ("Meeting — Jon Goh met founder X (May 2026)") |
| `narr` | 2-4 sentence narrative: who did what, when, why it matters to TFG |
| `na` | next action, imperative, one line |
| `fd` | fundraise detail: round(s) raised + reasoning for the `nrd` estimate |
| `str` | 0-5, connection-strength dots |
| `sl` | strength label matching `str` (see `STRENGTH` array in the file) |
| `aid` | the Attio company `record_id`, **first 8 hex characters only** (matches the UUID's first segment before the first hyphen) |

Read a handful of neighboring entries before adding or editing one — the
narrative voice (terse, factual, names names, cites $ amounts and dates) is
part of what makes new entries look native rather than bolted on.

## Step 1 — Find what's new in Attio

The source-of-truth pipeline list is Attio's **TFGI Pipeline Tracker**
(`list` slug `vc_deal_flow_1`), which carries a `deal_stage` status field.
Known stages include `0. New`, `1. Screened`, `2. Founder email`,
`3. Founder meeting`, `4. Data Review (Scorecard)`, `5. Diligence`,
`6. Invested`, `7. Tracking`, `8. Passed`, `9. Lost`, `9. Missed` — confirm
the live option list with `mcp__Attio__list-list-attribute-definitions`
since it can change.

To find net-new companies:

1. `mcp__Attio__list-records-in-list` filtered on `deal_stage`, paginating
   with `offset`/`limit` — this list regularly exceeds 100 records, don't
   assume one page is everything.
2. For each entry, take the first 8 hex characters of
   `parent_record.record_id` and diff that set against every `aid` already
   in `CO` (grep the file for `aid:'` to get the current set fast). What's
   left over is net-new.
3. `mcp__Attio__get-records-by-ids` on the `companies` object for the
   net-new ids to pull name, domain, sector, and Specter-synced description.
4. `mcp__Attio__list-workspace-members` once per session to map
   `workspace_membership_id` → name (Jon Goh, Charlie Daniel, Troy Horrell,
   and others — don't hardcode this list, membership changes) so narratives
   can say who actually made contact. For company-side people, follow the
   `team[]` references through `get-records-by-ids` on the `people` object.

**"7. Tracking" companies** are candidates — surface them to Troy (name,
sector, one-line description, connection state) and let him say which are
worth adding and at what tier, rather than adding all of them silently.

**"9. Missed" companies** — Troy has treated every one of these as an
automatic Tier 1 / priority add in past sessions ("these should ALL be
included... and are all PRIORITY deals"). Default to that, but it's a
standing preference, not a hard rule — say what you're about to do before
doing it if it's a large batch.

## Step 2 — Enrich with Specter

Once you know which companies to add or refresh:

1. `mcp__Specter__find_company` by **domain** (preferred over name — a bare
   name search can resolve to the wrong company entirely).
2. `mcp__Specter__get_company_funding_rounds` on the resulting id for real
   round history: type, date, amount, investors.
3. Use the most recent round to set `stage` and to derive the *real* `nr` —
   never leave `nr` as a generic `'Next round'` when Specter gives you an
   actual last-round type (Series B raised → `nr` is `'Series C'`, not a
   placeholder).
4. Sanity-check the match: does the investor list and description match
   what Attio/the web already told you about this company? Specter has
   occasionally resolved a domain to a same-named but unrelated company
   (e.g. a UK IT analyst firm instead of a stealth manufacturing startup) —
   when that happens, discard the bad match, say so on the card's `fd`
   field, and don't use the wrong data.
5. If `get_company_funding_rounds` returns zero rounds, don't invent a
   date — leave the company undated (`q:'tbd'`, `nrd:'TBD'`) and note in
   `fd` that Specter has no funding rounds on file, so a human knows why
   it's still blank.
6. Specter calls occasionally fail with "MCP tool call requires approval."
   This has cleared on retry after a short pause in practice — don't
   fabricate data to work around it; if it keeps failing, leave the company
   flagged and tell the user rather than guessing.

## Step 3 — Dating companies with no confirmed next-round date

This section **only applies to a company that has no date yet** —
freshly added, or already sitting at `q:'tbd'` / `nrd:'TBD'`. A company that
already has a real quarter assigned (`q3-2026`, `q1-2028`, etc.) has been
placed there deliberately at some point — never recompute or move it on
your own initiative. If Troy wants it moved he'll say so directly, and a
direct instruction always overrides this whole section (see below).

For companies that do need a first-time estimate, base it on the most
recent round's date and stage:

| Last round | Next round | Add to base date |
|---|---|---|
| No funding / Pre-Seed / Seed | Series A | +12 months |
| Series A | Series B | +18 months |
| Series B | Series C | +18 months |
| Series C or later | next round | +24 months |

The quarter you actually place the company in (`q` and `nrd`) is the
**estimated next raise minus 3 months** — this represents target-outreach
timing, not the raise date itself, so it's normal for `fd` to spell out
both ("Series B raised $50M Sep 2025. Series C estimated Q1 2027. Target
outreach: Q4 2026.").

If that computed date has already passed relative to today, don't put it
in a future quarter that's already behind — place it in the `'active'`
column instead (`q:'active'`, `raising:true`, `nrd:'Active Now'`), and say
plainly in `fd`/`narr` that this is "overdue per the timing model — likely
raising now or stalled, worth a sanity check" rather than presenting it as
confirmed fact.

`raising:true` otherwise belongs on the `'active'` column and on quarters
close enough to count as near-term (a quarter or so out — judge this
against what's already marked `raising:true` elsewhere in the file for
similar lead time, rather than a fixed cutoff).

**Manual overrides from Troy always win.** If he says "do 6 months," "kill
this one," "they're currently raising, so track the *next* round 18 months
out," or "they actually raised a Series A in <date>, use that" — follow it
literally instead of recomputing from Specter. When he says a company is
*currently* raising a round, that means: don't reset the clock to "active"
for the round already in flight — instead date the card for the round
*after* that one, per his instruction, and note in `narr`/`fd` that the
current round is already underway.

## Step 4 — Match the house style

- **Tier 1 ("Key Companies") is opt-in, not the default.** Only set
  `tier:1` when Troy explicitly asks for it ("add as key," "they're all
  key!"). Default new adds to `tier:2` and say so, so he can promote any of
  them in one line if needed.
- **Sector colors**: before inventing an `sb`/`st` pair, `grep` the file for
  existing `sector:'...'` values and their paired classes, and reuse the
  pair from the closest matching sector already present (Robotics AI →
  `bg-orange-900`/`text-orange-300`, Automotive → `bg-blue-900`/
  `text-blue-300`, Aerospace/Defense/Deep Tech → `bg-slate-700`/
  `text-slate-300`, EV/CleanTech → `bg-emerald-900`/`text-emerald-300`,
  and so on). Only pick a fresh Tailwind `*-900`/`*-300` pair when nothing
  close exists — the file keeps growing, so treat this as "search first,"
  not a fixed table to memorize.
- `aid` is always the first 8 hex characters of the Attio record UUID, not
  the full UUID — every other entry in the file follows this convention and
  breaking it will break the aid-diffing step in Step 1 for future sessions.
- Removing a company: delete its **entire object literal, including the
  trailing blank line**, don't null out its fields — a half-blanked entry
  will fail rendering or leave dead weight in the array.

## Step 5 — Validate, then commit and push

Before every commit that touches `CO`, run:

```
bash .claude/skills/pipeline-update/scripts/validate.sh
```

It checks the embedded `<script>` block parses (`node --check`) and that no
`id` or `aid` was duplicated across the array. Don't commit if it fails —
fix the conflict first (a duplicate `aid` usually means the same Attio
company got added twice under different names/domains).

This repo works on a single long-lived feature branch per session, not a
new branch per change — commit directly to the current branch with a
descriptive message and push, the same way you would for any other change
here.

## Data-quality edge cases worth knowing

- **Duplicate Attio records for the same real company** happen (seen with
  two "Kela Technologies" entries under different domains, and a "Mulberry
  Industries"/"Mulberry Magnetics" pair at the identical street address).
  When you spot this, flag it in the card's `narr` rather than silently
  merging the two or adding both — it's a data hygiene issue for Attio,
  not something to paper over on the tracker.
- **A Specter domain match resolving to the wrong company** is a real
  failure mode, not a hypothetical — verify the investor list/description
  actually matches what you already know about the target before trusting
  it.
- **Zero funding rounds from Specter** doesn't mean assume Seed/undated —
  it sometimes means the record just isn't populated. Say so rather than
  guessing a stage.
