---
name: pipeline-sync
description: >
  Syncs the TFGI investment pipeline dashboard (index.html in the Tracking-companies repo) with live
  data from Attio CRM. Use this skill whenever the user says "sync pipeline", "refresh pipeline",
  "update pipeline from attio", "sync from attio", "check contact history", "update contact flags",
  or asks to pull the latest Attio data into the dashboard. Also use it when the user asks whether
  any company's dc flag, last contact, or connection strength needs updating.
---

# Pipeline Sync — Attio → Dashboard

This skill keeps the TFGI pipeline dashboard (`index.html`) in sync with Attio CRM contact history.
The dashboard data is **static** — Attio is the source of truth, and this skill pulls the latest
interaction data from Attio and writes it back into the `CO` array in `index.html`.

## What gets updated

For each company in the `CO` array that has an `aid` field (the first 8 chars of its Attio record_id):

| Dashboard field | Attio source | Logic |
|---|---|---|
| `dc` | `first_interaction` | `true` if any interaction exists, else `false` |
| `lc` | `last_interaction`, `last_calendar_interaction`, `last_email_interaction` | Most recent of these dates, formatted `DD MMM YYYY` |
| `ct` | `last_calendar_interaction` vs `last_email_interaction` | `"Meeting (calendar)"` if calendar is most recent, else `"Email"`, else `"Call/other"` |
| `str` | `strongest_connection_strength` | Very weak→1, Weak→2, Good→3, Strong→4, Very Strong→5 (0 if no data) |
| `sl` | derived from `str` | Human label, e.g. `"Strong — regular meetings"` |

Fields `narr` and `na` require human judgment — do **not** overwrite them automatically.

## Step-by-step process

### 1. Read the current CO array

Read `/home/user/Tracking-companies/index.html`. The `CO` array is in the `<script>` block and
looks like:

```js
const CO = [
  {id:'rerun', tier:1, ..., dc:false, lc:'', ct:'', str:0, sl:'', aid:'a1b2c3d4'},
  ...
];
```

Extract every company object. Companies without an `aid` field cannot be looked up — skip them and
note them in the summary.

### 2. Look up Attio records in batches

Use `mcp__Attio__get-records-by-ids` with `object_type: "companies"`. The `aid` stored in the
dashboard is the **first 8 characters** of the full Attio `record_id` UUID — you need the full ID.

**To get the full ID:** Use `mcp__Attio__search-records` with `object_type: "companies"` and query
the company name, or use `mcp__Attio__list-records` filtered by the known partial ID. The safest
approach is to search by company name and confirm the result's record_id starts with the stored `aid`.

Batch companies in groups of 10 to avoid overwhelming the API.

**Fields to request from Attio:**
- `first_interaction`
- `last_interaction`
- `last_email_interaction`
- `last_calendar_interaction`
- `first_calendar_interaction`
- `strongest_connection_strength`
- `name` (for verification)

### 3. Map Attio data to dashboard fields

For each company record returned:

**`dc` (company contact flag):**
```
dc = first_interaction is not null and not empty
```

**`lc` (last contact date):**
Take the most recent non-null date among `last_interaction`, `last_calendar_interaction`,
`last_email_interaction`. Format as `DD MMM YYYY` (e.g. `"08 Oct 2025"`).

**`ct` (contact type):**
- If `last_calendar_interaction` is the most recent → `"Meeting (calendar)"`
- Else if `last_email_interaction` is most recent → `"Email"`
- Else → `"Call/other"`

**`str` (connection strength, 0–5):**
Map `strongest_connection_strength`:
- null / absent → `0`
- `"very_weak"` or `"Very weak"` → `1`
- `"weak"` or `"Weak"` → `2`
- `"good"` or `"Good"` → `3`
- `"strong"` or `"Strong"` → `4`
- `"very_strong"` or `"Very strong"` → `5`

**`sl` (strength label):**
| str | sl |
|---|---|
| 0 | `""` |
| 1 | `"Very weak — minimal contact"` |
| 2 | `"Weak — occasional emails"` |
| 3 | `"Good — regular communication"` |
| 4 | `"Strong — regular meetings"` |
| 5 | `"Very strong — close relationship"` |

### 4. Write changes to index.html

For each company with changes, do a targeted find-and-replace of its entry in the CO array. Match on
the company's `id` field (which is unique). Replace only the fields that changed — do not reformat
the entire file.

The typical pattern in the file for a company entry spans multiple lines like:
```js
{id:'rerun', tier:1, q:'active', raising:true, dc:false,
 name:'Rerun', ..., lc:'', ct:'', ..., str:0, sl:'', aid:'a1b2c3d4'},
```

Use the Edit tool with surgical replacements. If a field wasn't present before, add it in the right
position (dc near the top, lc/ct after dc, str/sl near aid).

### 5. Commit and push

```bash
cd /home/user/Tracking-companies
git add index.html
git commit -m "sync: update contact data from Attio

[list key changes, e.g. '- Updated dc flag for 3 companies: Cogna, Aerolane, Circuit']

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DLF5RSyhTNfZVXS73MujCz"
git push -u origin claude/wonderful-volta-5tnpL
```

### 6. Print a summary

Report clearly what changed:

```
## Attio Sync Summary

**Updated (N companies):**
- Cogna: dc false→true, lc ''→'15 Mar 2024', ct ''→'Email', str 0→2
- Aerolane: dc false→true, lc ''→'12 Apr 2026', str 2→3

**No change (N companies):**
- Rerun, Shinkei Systems, Matta, ...

**Skipped — no aid (N companies):**
- [companies with no aid field]

**Not found in Attio (N companies):**
- [companies where search returned no match]
```

## Important rules

- Never overwrite `narr` (narrative) or `na` (next action) — these require human judgment.
- Never change `tier`, `q`, `raising`, `name`, `sector`, `stage`, `nr`, `nrd`, `desc`, `fd`, `sb`, `st`.
- If Attio returns no result for a company, log it in the summary but do not change the company's fields.
- If `dc` would change from `true` to `false` (i.e. Attio shows no interaction but the dashboard says there was one), flag it as a warning and ask the user to confirm before making that change. Contact history is rarely deleted from Attio.
- Verify company identity: when looking up by name, confirm the Attio result's domain/description matches what's in the dashboard before trusting the interaction data.
