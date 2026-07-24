# Anchored piles — a data-pile wears an anecdote

**Status:** design note / discovery. Nothing here changes running code. It pins
vocabulary and boundaries so implementation can proceed without churn, and so
parallel work across the constellation does not collide.

**One-sentence thesis:** A data-pile wears an *anchor*; the anchor is an
*anecdote*; the anchor's *intent* selects what replies mean. A poll is the
special case where the anchor carries prefab options. The journalism case — an
**ask** — is the case where the anchor carries an object reference and its only
rule is *citation required*.

---

## 0. What this changes, and what it does not

**New surface (safe to build):**
- A new anchor *intent* — `ask` — layered onto the existing pile machinery.
- The journal-side render/write/index of an anecdote-as-exhibit — **already
  landed** in `journal.anecdote.channel` (the `{% anecdote %}` renderer, the
  `bin/promote-exhibit` writer, and the `{% exhibits %}` folder index).
- An antidote screen that *configures an ask* and *browses its replies*.

**Settled — do NOT touch as part of this:**
- The **poll-gathering schema and lifecycle** (`anecdote.poll/v1`, tally,
  rounds, `bin/govern`). See §4. Any "responses could be anecdotes" idea is
  logged in §8 and deliberately deferred.
- The **needs-ballot / pin / satchel** mechanism. It is *not* a pile. See §2.
- The **cryptographic pile invariants** (`bin/verify`, the append-only
  hash-linked ratchet, `bin/ingest` onto `feed/*`, `bin/prove`). We reuse them
  unchanged.

---

## 1. The generalization

The constellation already treats a poll as an anecdote subtype:
- `anecdote/v1` — `{ schema, to:{id,kind,url}, label, body:[…] }`
  (`anecdote.channel/composer/anecdote.mjs`). `body[0]` is verbatim text with a
  reducer `label`; later parts are `ref` receipts
  (`{ kind:"ref", mediaType, hash, source, pile?, bytes? }`).
- `anecdote.poll/v1` — an anecdote whose content is a *question* plus
  *suggested* options (`anecdote.channel/viewer/poll.mjs`). Options are
  non-binding; a custom answer is always allowed.
- This pile is already "a bottle of possibly-mixed items" with a *list* of
  `sources` (`CONTRACT.md`, `pile.yml`; civic-node `docs/PIPELINE.md`).

And the constellation has already named the hinge: **a prefab answer is the
solicitation signal** (`antidote/docs/faces.md`, `tell/docs/solicitation.md`) —
a constitution becomes a poll only where a question grows a prefab answer to
choose from. So the `ask` intent is not a new invention; it is the already-named
complementary case: an anchor with **no** prefab answer.

The move: promote the pile's **anchor** from "question text" to "any anecdote,"
and let an `intent` field say how to read replies.

```
pile
 ├─ anchor: anecdote/v1        # text OR object reference
 │    intent: "poll" | "ask"
 ├─ constitution: <hash>       # governs admission (see §3, §4)
 └─ feed/*: replies + rulings  # append-only, encrypted at rest
```

| intent | anchor is… | a reply means… | projection |
|--------|-----------|----------------|------------|
| `poll` | a question + prefab options | an answer | tally / rounds (unchanged) |
| `ask`  | an object reference, no options | "I cite this / here's a derivative / here's more" | citation graph + hearsay log |

This demotes poll to one intent among two; it does not rewrite it. Intent
dispatches the projection; one schema family underneath.

---

## 2. Explicitly out of scope: needs ballots

A needs ballot is **not** a pile and must not be modeled as one.

- It is a **passive socialization protocol**: labels you champion are pinned in
  your satchel and force-forwarded on contact
  (`anecdote.channel/composer/satchel.mjs`, `docs/ballot-mesh.md`). Atlas trades
  them as **bills** (`atlas…/bin/bill`) and batches as a **stack**.
- Its purpose is **fine-grained metadata withholding** — declaring only as much
  as (say) a state, and letting a reply mingle toward you. It is *not* encrypted
  messaging; an encrypted wrapper is meaningless when it is unclear who the
  payload is for (the key would have to travel with it). The base case is a
  stack of needs headed somewhere concrete (imagine 911), hand-carried if need
  be; the mesh case solicits toward an unknown target and trades to get there.
- Structurally opposite to a pile: pins **push** labels outward with no
  check-in; a pile **sits still**, is appended to, and is **opened and
  searched**. The socialization procedure never opens a pile.

The shape-rhyme (both anecdote-flavored, both trade around the mesh) is real,
but the mechanisms diverge. Keep them separate.

---

## 3. The `ask` intent (the journalism case)

An ask says: *here is a thing — do you need this? Citation required.* You are
not selling data; you are publishing something **citable** that only you hold.
Juxtapose with the needs ballot's *"what do you need?"*: here it is *"do you
need this?"*, and **the reply that cites it is the acknowledgment**. Citation is
the stateless state — there is no accept/reject round.

### 3.1 Anchor
An `anecdote/v1` whose leading part is an object reference (a photo you took, a
URI, a screenshot) rather than a question. The implied question mark comes from
the intent, not the text. The anecdote is itself an assistive description of its
subject; pulling more structure out of it is gravy.

### 3.2 Constitution: OPEN + "citation required"
The pile never does semantic comparison itself — it validates *cryptographic*
shape only (`bin/verify`, fails closed); semantic admission is a *constitution*
applied upstream (`CONSTITUTION.md`, `tell/bin/govern`). antidote already reads
an **OPEN** vs **LIMITING** constitution shape
(`antidote/bin/constitution-shape.mjs`).

An ask wears an **OPEN** constitution: it admits everything and auto-rejects
nothing — a **hearsay log**. But keep `tell/bin/vouch` on, so each reply still
carries an origin stamp and a "how real is this claim?" measurement. You keep
the gravel *and* the metadata to sift it. That measured-but-ungated posture is
what "citation required" means: the anecdote's own constitution posed as the
pile's rule.

### 3.3 Replies are first-order anecdotes
Not prefab text and not custom text — full `anecdote/v1` objects pointing
wherever the replier wants, carrying additional fragments (a new photo with new
coordinates, another pointer, an accusation, more hearsay). URI refs **stay
URIs** in the pile (native: a `ref` may be source-only with no `bytes`; the
64 KiB inline cap exists so an anecdote can never become a file host). Full
offline hydration of URI refs is a later quality-of-life item (§8). Appended via
the existing feed protocol (`bin/ingest` → `feed/<source>`), encrypted at rest
by the ratchet.

### 3.4 Rulings are first-class
The pile is append-only, so a reply is never deleted — it is **annotated**. A
*ruling* is a small record pointing at a reply's content-id and stating an
origin-vetting result (kept / hearsay / discarded). "Discard, but cite the
chain you discarded" becomes a citable ruling, not a mutation of history. This
keeps a hearsay log from degrading into undifferentiated sludge.

### 3.5 Be your own vertical
You can author the anchor, author a reply, and own the pile — all under one
signing key (`anecdote.channel/composer/sign.mjs`). Then "pile holder == pile
maker" is provable, and a reply's signature is where a real `original_ts` comes
from (the unsigned anecdote core has no timestamp). So self-gathered evidence —
a photo you took — sits encrypted in your own pile until you choose to reveal
it, and when you embed it later it is framed in exactly the same terms as anyone
else's evidence, just identifiably yours. Flattening the "gather your own
evidence" case: the anchor is your inciting incident, and you answer it
yourself, backdated and verifiable.

### 3.6 Quiet reveal
`bin/prove` discloses one ratchet checkpoint, exposing exactly that item and
nothing earlier — the "draft exhibits stay private; going public discloses just
this one" flow. Proving you *hold* an item (by content-id) without divulging it
is itself a signal. Publishing an item into a piece's `exhibits/` folder is the
other, coarser way to make it public.

### 3.7 Subject convergence
The reducer's ratchet is merge-only and cannot flicker
(`anecdote.channel/reducer/reducer.mjs`). An anchor's label plus its replies'
labels converge toward a stable subject over time — which turns a pile into "a
citable independent question with contemporaneous evidence around it," even
across years, provided items are labeled consistently.

---

## 4. The `poll` intent (unchanged)

Polls keep their current schema, tally, rounds, and governance
(`anecdote.channel/viewer/poll.mjs`, `tell/bin/govern`,
`tell/_data/constitutions/<pile>/<poll>.json`). The `ask` intent sits *beside*
poll; it does not modify poll-gathering. Options → tally projection; object ref
and no options → citation-graph projection.

---

## 5. Presentation & the publish boundary

- **Domain-agnostic face.** A pile's addressable face is a **Floor** — Tell
  serves an identical offline PWA on every `<name>.tell.anecdote.channel`
  (`tell/floor/`, `tell/docs/floor.md`). A "journal-themed bottle" is *the same
  Floor with a citation-required skin*, not a new `*.journal.anecdote.channel`
  routing case (that subdomain does not exist; journal is the path `/journal/`).
  The mechanism is domain-agnostic; the domain/skin is presentation of intent.
- **Contactable source ≠ jurisdiction move.** If a source opts into contact, you
  expose an addressable face — but a Tell *is a data-pile again*, so nothing
  crosses from "journal" to "tell." Keep the mechanism single; let domains be
  costumes.
- **Journal is the publish boundary.** Writing an anecdote into
  `journal/<author>/<piece>/exhibits/` makes it public in that author
  submodule's git history. Already implemented engine-side: `{% anecdote %}`
  renders one exhibit, `{% exhibits %}` renders the whole folder, and
  `bin/promote-exhibit` materialises an anecdote into it. Images render from a
  same-origin exhibit file (CSP `img-src 'self'`), never a `data:` URI.

---

## 6. Provenance & references

The anecdote core carries per-attachment provenance (`ref.source`) but not a
whole-anecdote origin, and no time until signed. At promotion/ingest, stamp an
origin block:

- **Atlas origin (public, ideal):** the addressable atlas URL / pile `map.xml`
  path — routable.
- **Tell / private origin (anonymous):** a **stable-but-non-routable** reference
  — the signer **fingerprint (`kid`)**, which "names the origin; does not confer
  trust" (`tell/docs/qr-provenance.md`), plus the **content-address (`sha256`)**
  naming the item. Trust is always local; the reference identifies without
  routing.
- `captured_at` (when promoted) and `original_ts` (only if the source anecdote
  was signed — absent otherwise, and honestly marked so).

---

## 7. Division of labor (grounded)

| Layer | Role | Key files |
|-------|------|-----------|
| **anecdote** (substrate) | objects, `ref` receipts, signing, reducer labels; NEW: `ask`/`intent` marker | `composer/anecdote.mjs`, `composer/sign.mjs`, `reducer/reducer.mjs`, `viewer/poll.mjs` |
| **data-pile** (this repo) | wears an anchor anecdote; `poll`\|`ask`; OPEN+citation-required; replies + rulings; `bin/prove` | `CONTRACT.md`, `CONSTITUTION.md`, `bin/verify`, `bin/ingest`, `bin/prove`, `pile.yml`, `needs/` |
| **antidote** (UI / dev surface) | configure an ask (`bottle.html`), browse replies + promote-to-exhibit (`shelf.html`, `index.html`) | `bottle.html`, `shelf/shelf.mjs`, `vault/chronicle.mjs`, `bin/judge-constitution.mjs`, `bin/constitution-shape.mjs` |
| **atlas / tell** (socialization) | post ask publicly / trade QR; vouch + origin stamp; Floor face | `atlas/bin/match`, `atlas/bin/snapshot`, `tell/bin/govern`, `tell/bin/vouch`, `tell/floor/` |
| **journal** (publish boundary) | exhibits as files; render + write + index (done) | `_plugins/anecdote.rb`, `bin/promote-exhibit`, `_includes/figure.html` |

---

## 8. Deferred / to revisit (logged, not built)

1. **Response-as-anecdote unification.** A poll's custom answer is already
   anecdote-shaped; a "response" (a Tell-submitted answer) could eventually just
   *be* an anecdote rather than a bespoke shape, making "source anecdote →
   replies" and "poll → answers" the same shape. **Do not change poll-gathering
   schema yet.** Log now; revisit after the `ask` path is real.
2. **URI ref hydration.** Pulling a URI ref's bytes durable into the pile (vs.
   staying a pointer). QoL, later.
3. **Ruling propagation.** How a keep/discard ruling travels with an item when
   it is re-shared. Later.
4. **Contactable-source addressable face.** The opt-in-to-contact flag and its
   Floor face. Later.
5. **Standalone exhibit browse.** A self-rendering `index.xml` + `.xsl` (the
   atlas `map.xml`/`map.xsl` pattern) for browsing an exhibit pile outside a
   built page.

---

## 9. Open questions before code

- Anchor `intent` field: on the anecdote, on the pile, or both? (Leaning: on the
  pile's anchor record, so the anecdote stays intent-neutral.)
- Ruling record shape and where it lives on the feed branch.
- Whether the `ask` OPEN constitution is a distinct named shape or a convention
  over the existing OPEN shape in `antidote/bin/constitution-shape.mjs`.

---

## 10. Sequencing

- **V1 — render + promote + index (done, journal engine).** `{% anecdote %}`,
  `bin/promote-exhibit`, `{% exhibits %}`. Ships value for any anecdote already
  held — including one you authored yourself — with no crypto and no matching.
- **V2 — the ask + browse face.** The `ask` anchor + `intent` marker; an
  antidote screen listing replies under a pile with a promote button.
- **V3 — back it with a real pile.** Encryption for private/tell-sourced
  material; `bin/prove` disclosure wired to publish.
- **V4 — socialize.** Post asks to atlases; `atlas/bin/match` feeds the browse
  face across peers; QR-trade for the private path.
