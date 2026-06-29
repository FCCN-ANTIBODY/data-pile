# Lifecycle: from live mailbox to a sealed bottle, and the pile's backing role

This note describes the **whole life of a data-pile** — how it starts as a live thing on a Tell, how
it becomes addressable, how a finished poll seals off as "a little bottle of data," and what the pile
*is* in the reporting model: the **verifiable backing** behind a Tell's anonymous report, never the
reporter itself. It is **doc-only**; it names how the existing pieces compose.

## Chain of custody — the Tell signs, the pile holds

The pile signs nothing it receives. **The Tell signs every delivery manifest**
([`tell.anecdote.channel/bin/deliver`](https://github.com/FCCN-ANTIBODY/tell.anecdote.channel/blob/main/bin/deliver);
[`CONTRACT.md`](../CONTRACT.md) Layer 2), and the pile pulls, verifies, and persists it. So a sealed
pile **carries the Tell's signature as provenance** — neither party can later deny its role without
breaking the signature. This is what makes a sealed pile a trustworthy bottle rather than a private
assertion.

## The four states

- **Live (a mailbox).** `bin/ingest` pulls deliveries onto `feed/<source>` and verifies each before
  persisting ([`CONTRACT.md`](../CONTRACT.md) feed protocol). The pile is the Tell's encrypted
  mailbox for that poll's inner chatter.
- **Addressable.** When the fronting Tell lists on an Atlas, distant neighbors can answer without
  being on that Tell. **The pile's behavior does not change** — listing only widens *who can answer*.
  The QR entry to a poll can be handed out individually regardless of any registry.
- **Sealed (a bottle).** When a poll/round closes (`lifecycle.closes_at` in the poll's constitution),
  the pile's blocks for that poll are a self-verifying, **Tell-signed** artifact — the
  [`docs/transfer.md`](transfer.md) bundle, scoped to the closed poll. The bottle travels and verifies
  with no live origin; the signed manifest is its sole anchor.
- **Disclosed (proven), at the owner's discretion.** The owner may keep the bottle sealed forever, or
  publish a ratchet checkpoint with `bin/prove` so anyone can decrypt from that point and confirm the
  raw against the Tell-signed manifest. Disclosure is forward-only and never surrenders the master
  identity ([`CONTRACT.md`](../CONTRACT.md) Layer 3).

## Multiple Tells, one pile

`pile.yml` `sources:` is a **list**: the same driver/question/opinion can be offered to several Tells
that register the poll, each delivering on its own signed `feed/<source>` branch. `bin/ingest` /
`bin/verify` process each source independently (*one source per branch*). Each Tell **independently
reports over what it witnessed**; the pile is the **union of the raw**, each segment carrying its own
Tell's signature. Being on more than one Tell is a sharing posture, not a different pile.

## The pile's role in reporting — backing, not reporting

The reporting locus is the **Atlas pool**, not the Tell and not the pile (see
[`tell.anecdote.channel/docs/reporting.md`](https://github.com/FCCN-ANTIBODY/tell.anecdote.channel/blob/main/docs/reporting.md)).
A standalone Tell publishes no public report; *only when it joins an Atlas* does it deliver de-identified,
membership-tagged summaries, and the **Atlas pools across Tells and applies small-N suppression** before
publishing a constituency aggregate. The pile is the **second-order raw proof** that backs those figures:

- **The figures are already committed.** Each Tell summary (`tell.poll.summary/v1`) rides in a **signed
  manifest head**; the pile holds those manifests verbatim, so the pool's aggregate is recomputable from
  them without decryption.
- **The pile substantiates on demand.** `bin/prove` discloses a checkpoint; a verifier decrypts the
  raw records, confirms they hash to the Tell-signed manifest, and confirms they aggregate to the
  published figure — falsifiable against the raw **without the raw ever being public**.
- **Single-record disclosure is the per-row form of the same proof.** The sealed govern log is an
  **evidence locker**: one record disclosed on a justified query (the identity tie is the Issue author),
  never a bulk dump.
- **`bin/report` is owner-side aggregation over *verified* state, not a second judging round**
  ([`CONSTITUTION.md`](../CONSTITUTION.md)); it already carries the manifest digest + signature flag as
  provenance ([`bin/report`](../bin/report)).

So: **per-record answers and `asker` stay sealed in the pile**; the Atlas pool abstracts the membership-
tagged summaries; the pile can prove any figure. The pile is the system of record; the Atlas pool is the
first public abstraction; the Tell only delivers into an Atlas it has joined.
