# The inbound response contract

This defines how responses enter a **data-pile** and what governs whether they are kept. A
data-pile is a durable, **encrypted-at-rest** tank you own. It receives responses from two kinds
of source and **tolerates only what its own `questions/` permit**.

A **data-pile never talks to Atlas.** Its counterpart is **Tell**. Atlas is, separately, only a
queue of unmet *needs* that Tells report to — never a party that reads or writes a pile.

## Sources: the Tells you joined (+ the direct path)

A **source** is a feed delivering responses to one branch, `feed/<source>`, independently keyed —
so joining several Tells gives several differently-encrypted streams and the pile always knows
which channel added which blocks. `pile.yml` lists them under `tells:`. Two modes:

- **A Tell you joined (signed).** You join by opening a PR on that Tell (its engine is submoduled
  into a workspace; it hosts `questions/` + `needs/`). The Tell delivers ratchet-encrypted blocks
  under a **signed** manifest to `feed/<tell>`. Jurisdiction/scale is whatever your CONSTITUTION
  declares — board of commissioners, water district 9, a neighborhood, a D&D group — negotiated at
  the join PR.
- **Direct QR ingress (unsigned).** A poll's QR opens `//tell.anecdote.channel` carrying config
  that addresses *this pile* as the authorized ingress party — no Tell server. The respondent's
  browser `age`-encrypts their reply to the pile's committed public key and opens a PR onto
  `feed/direct`. There is no registered signer; the **acceptance governor is the only gate**.

The same pile can solicit the same question through several Tells *and* the direct path, and get
responses back differently encrypted from each.

## The crypto model (carried over, producer-agnostic)

Unchanged from how the tank already works — the producer is now a Tell instead of any one party.

- **Encryption at rest.** Setup generates an [`age`](https://github.com/FiloSottile/age) keypair.
  The **recipient public key** is committed at `keys/pile.age.pub` (encrypt-only, safe in public);
  the **private identity is never committed** — it lives in the secret `PILE_AGE_IDENTITY`.
- **Signed Tell feeds** use a forward hash ratchet: a seed `K_0` (delivered once, `age`-wrapped to
  the recipient as `inbox/seed.age`), `K_{seq+1}=sha256("ratchet:"||K_seq)`, each block
  symmetric-encrypted under `K_seq` as `inbox/<seq>.enc`. **Direct feeds** skip the ratchet: each
  block is an `age`-to-recipient file `inbox/<seq>.age`.
- **Integrity.** `inbox/manifest.json` is a hash-linked chain (`this_hash`=sha256(ciphertext),
  `prev_hash` links the prior entry). For signed Tells the **head is signed** (reusing the
  SSH-signature trust anchor; `bin/verify` checks it against `keys/<tell>.signers`, whose
  fingerprint must equal `pile.yml`'s `signer`) and each entry carries a `ratchet_pub` commitment.
  Direct manifests are unsigned with `ratchet_pub: null`.
- **Disclosure.** `bin/prove` publishes a ratchet checkpoint `K_n` to prove blocks `seq ≥ n`
  against the signed manifest — forward-only, without ever revealing `PILE_AGE_IDENTITY`. (Signed
  Tell feeds only.)

`main` carries only the template, `pile.yml`, `keys/pile.age.pub`, `questions/`, and the artifacts
you choose to publish — **never the encrypted log** (that lives on `feed/**`) and **never
plaintext**.

## questions/ — the governor

The pile **owns its questions**. Each lives under `questions/<qid>/`:

- `question.json` — the item (poll text + option schema) and an **ownership attestation** (author,
  `created_at`, license, `original: true`). The asker records it as original data they own; the
  introducing commit is the timestamped anchor.
- `guidance.json` — the machine-readable **mini-CONSTITUTION**: which answers are tolerated.
  ```json
  { "version": 1, "qid": "cd04-q1", "options": ["a","b","c"],
    "scope": { "geo": ["cd04"] }, "originality_required": true, "dedup_key": "nonce" }
  ```
- `guidance.md` — optional prose companion.

Joining a Tell publishes a *reference* to `<qid>`; the canonical question and its guidance stay in
the pile. Guidance is **yours to edit**; the change lands in the git log, `version` advances, and
the next ingestion re-filters. You are master of what enters, not hostage to it. What guidance may
ask for is bounded by [`CONSTITUTION.md`](CONSTITUTION.md) — and, where a pile is matched through an
Atlas, by that Atlas's CONSTITUTION. A pile cannot declare "accept everything" and harvest without
a question and the respondent's consent.

### The acceptance step

`bin/ingest` runs the pipeline per source: **fetch → `bin/verify` → decrypt → `bin/accept`**, and
writes a **signed acceptance ledger** at `state/<source>/ledger.json`. Each ledger entry records a
verdict for one response — referencing the immutable feed block by `seq` + `this_hash`:

```json
{ "seq": 0, "block": "000000.enc", "this_hash": "sha256:…", "qid": "cd04-q1",
  "verdict": "accepted", "reason": "-", "guidance_version": 1 }
```

The ledger carries **verdicts only, no plaintext** — the tank stays encrypted-at-rest while the
governor's decisions are durable and git-reviewable. `bin/accept` checks each decrypted response
against its question's `guidance.json` + the pile CONSTITUTION; verdicts reuse Atlas's rejection
vocabulary:

| verdict | reason | meaning |
| --- | --- | --- |
| `accepted` | `-` | matches the guidance |
| `dropped` | `off-guidance` | option not in the allowed set |
| `dropped` | `geo` | outside the question's scope |
| `dropped` | `duplicate` | `dedup_key` already seen (incl. across Tells, in one run) |
| `dropped` | `malformed` | not a well-formed response |
| `dropped` | `other` | fails another guidance rule (e.g. originality) |

Acceptance needs the identity, so `ingest` is secret-bearing. With no identity it falls back to a
keyless crypto audit (verify only). Editing `guidance.json` and re-running re-filters from the
immutable feed — a personal poll's owner is never stuck with prior verdicts.

## What the pile requires of a source

- **Signed Tell:** blocks ratchet-encrypted to the committed recipient under a signed,
  hash-linked manifest with `ratchet_pub` commitments, delivered as signed commits on
  `feed/<tell>`; the signing key matches the registered `signer`.
- **Direct:** each block `age`-encrypted to the committed recipient on `feed/direct`; no signer
  required — the governor is the gate.

`bin/verify` enforces the cryptographic half; `bin/accept` enforces the governor half. Anything
that fails either is left out of the accepted set (and, for crypto failures, the whole delivery is
rejected).

## Producer-side checklist (lives in the pile repo)

1. **Author** a question under `questions/<qid>/` and its `guidance.json`.
2. **Join** one or more Tells (or publish a direct-QR poll) soliciting `<qid>`.
3. **Ingest** on a cadence (`bin/ingest`) — verify, decrypt, govern, ledger.
4. **Report** from accepted state (`bin/report` — aggregation is yours to define).
5. **Prove / decrypt** when you choose (`bin/prove`, `bin/decrypt`).
