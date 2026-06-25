# Needs — request-for-pile ("what's hanging")

A **need** is a question you want answered when **no pile exists to catch it**. You post it to an
Atlas you're registered with; Atlas carries it on its public **"what's hanging"** list (a tip line for
journalists, a board for networking) and **matches** it, by constitution, against the piles/Tells it
knows. On a fit, Atlas publishes the real **atlas+tell+pile address** that matched; you pull it
(`bin/need-matches`) and act — re-issue a QR straight to that pile (consent intact), or drop the need.

This repo is the **asker**. Its "address" is the repo itself — it may have no actual pile for this
topic. A need is **both** a committed file here *and* a labeled Issue mirror, so it is structured for
matching and visible as a public dangler.

## Schema — `needs/<id>.json`

```json
{
  "id": "boardgame-80525",
  "scope": "colorado",                 // region/namespace, for Atlas to filter + match
  "topic": "social/boardgames",        // coarse category (slash-delimited)
  "text": "Is anyone running a weekly board-game night near 80525?",
  "guidance": "What kind of pile would satisfy this — the matcher reads this.",
  "terms": ""                          // pre-authorization; see below
}
```

- **`terms`** is your consent posture. **Empty** → a match is only an *invitation*: Atlas marks it
  `consent_required: true`, and nothing happens until you re-issue to the matched pile yourself.
  **Non-empty** (e.g. "usable for civic outreach as-is") → you have pre-authorized that use, and a
  match comes back `consent_required: false` — you may use the matched pile immediately.

## Flow

1. Author `needs/<id>.json`; run **`bin/need <id>`** to print the Atlas registration entry + the Issue
   mirror body. The **`need`** workflow opens the labeled Issue and a registration PR to Atlas.
2. Atlas carries it on **`/needs.json`** and runs its matcher; matches land in Atlas's **`/matches.json`**.
3. **`bin/need-matches`** pulls those and shows any match's address + consent flag.
4. **Revoke** by closing the Issue (and removing the file) — the dangler stops being carried.

Pull, not push: Atlas never writes into you. It publishes; you pull and decide.
