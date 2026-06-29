# Roadmap — data-pile

Where this is going, and why today's shape is a way-station. `CONSTITUTION.md` binds what the pile
does *now*; this file is the direction, so an agent reading the code doesn't mistake the current
single ingest path for the whole story. The unsolved mechanisms each step depends on are tracked in
the workspace's
[`OPEN-QUESTIONS.md`](https://github.com/FCCN-ANTIBODY/civic-node/blob/main/OPEN-QUESTIONS.md).

## The principle: a pure system of record, privacy as the floor

The tank collects; nothing reaches into it. Everything below preserves two invariants, or it is wrong:
**it leaks nothing until the owner decides to prove it**, and **judging does not relocate back to the
pile by default**. New capability arrives as a *channel* or an *opt-in*, never as a change to those two.

## Today — one ingest path, judged upstream

The pile pulls its sealed digests from the **Tell that fronts it**: a one-way hash ratchet whose seed
only the Tell holds, `age`-encrypted to the pile's committed recipient and signed. `bin/ingest` →
`bin/verify` is the gate; nothing is trusted until the chain, signature, and ratchet commitments check.
Judging already happened at the Tell before sealing, so every record arrives carrying its `governed`
verdict and `constitution_sha`. Report aggregation ships as a documented stub — **yours to define** — on
purpose, because the project hasn't chosen an aggregation model.

## Where it's going

- **A second, Tell-less ingest channel.** `keys/pile.age.pub` is public and encrypt-only, so anyone
  *could* seal a payload to the pile without a Tell — but there is no path to **ingest** such a drop
  today, because the live feed is a ratchet only the Tell can extend. The direction is a separate
  `feed/drop` channel: `age`-to-recipient blocks under their own signed, hash-linked manifest (no
  ratchet, since there is no shared seed), for archival imports and direct owner-to-owner handoff —
  storage *and* encryption solved out of band, never by borrowing the Tell's key. **Now specified**
  in [`docs/transfer.md`](docs/transfer.md), together with the sendable whole-pile **bundle** (a pile
  relocates between origins as one self-verifying artifact) and the archive-and-reset **clear-space**
  ingress — the build surface is named there; the code is the next step.
- **Elective self-governance, opt-in only.** The owner may already **re-judge by hand** after
  `bin/decrypt`. A pile that wants its boundary governed systematically can summon the judge itself —
  paying with its own credentials or a timeshare on its Tell — and only ever as an **optional** action.
  The full pile-side governor was built once and set aside (closed
  [PR #6](https://github.com/FCCN-ANTIBODY/data-pile/pull/6)) precisely because, as a *default*, it
  re-relocates judging to the pile and re-severs the pile↔Atlas path that shipped. If it returns, it
  returns electively.
- **Reporting: the pile backs, the Tell reports.** The reporting locus is the **Tell**, which publishes
  one compulsory **anonymous** poll report. The pile's job is to **back it in verifiable fact** as
  second-order raw proof: per-record answers stay sealed here, the report's figures are already
  committed in the Tell-signed manifests this pile holds, and `bin/prove` substantiates any figure on
  demand. `bin/report` graduates from a generic stub toward *aggregation over verified state that
  reads the Tell's `reports/poll-*` as the public abstraction it backs* — never a second judging round.
  See [`docs/lifecycle.md`](docs/lifecycle.md) and
  [`tell.anecdote.channel/docs/reporting.md`](https://github.com/FCCN-ANTIBODY/tell.anecdote.channel/blob/main/docs/reporting.md).

## What this means for today's code

- **`main` stays the clean face; `feed/**` is the log.** Don't make the site build depend on feed
  contents, and don't land the append-log on `main`.
- **Keep the two decryption paths independent** — the `age` identity (owner-only, everything) and the
  hash ratchet (scoped, publishable). Proving the past must never require revealing the master identity.
- **Verification is the gate.** Ingest, reports, and proofs build on verified state, never raw feed
  contents — and a future `feed/drop` gets its own `bin/verify` variant, not a relaxed one.

## Open mechanisms

Tracked in [`OPEN-QUESTIONS.md`](https://github.com/FCCN-ANTIBODY/civic-node/blob/main/OPEN-QUESTIONS.md):
the Tell-less `feed/drop` ingest channel (**G**), and the elective pile-side judge (**A**). The
registration idiom the pile's `handshake`/`need` flows share with the rest of the constellation is
tracked in **B**.
