# Transfer: sendable piles, the drop channel, and clear-able spaces

This note specifies how a sealed pile **moves between origins** and how an owner **clears a space**
to receive one. It is the design for the second ingest channel reserved in
[`CONTRACT.md`](../CONTRACT.md) ("Tell-less out-of-band contribution") and tracked as
[`OPEN-QUESTIONS.md` → "G. Tell-less pile ingest"](https://github.com/FCCN-ANTIBODY/civic-node/blob/main/OPEN-QUESTIONS.md#g-tell-less-pile-ingest).

It introduces **no new cryptography**. Every primitive already lives in
[`bin/lib.sh`](../bin/lib.sh) (`dp_sha256_*`, `dp_enc`/`dp_dec`, `dp_iv`, `dp_ratchet_pub`,
`dp_entries_digest`); the integrity model and manifest shape are
[`CONTRACT.md` Layer 2](../CONTRACT.md). What is new is a *second channel* on its own branch and a
*relocation* gesture on top of it.

## A. Why this shape — storage as per-origin islands

Offline storage is **per-origin**, never shared across the domain tree. The browser's same-origin
policy isolates each subdomain's storage totally from the apex and from its siblings (cookies are the
lone domain-scoped exception); the constellation does not fight that wall and does not depend on
cross-origin storage visibility. The apex (`anecdote.channel`) is a **librarian of references and
staged snapshots**, not a storage hub — it holds *pointers* to artifacts, not the originals the
subdomains also hold. (This is the same layering as
[`OPEN-QUESTIONS.md` § N](https://github.com/FCCN-ANTIBODY/civic-node/blob/main/OPEN-QUESTIONS.md):
*legacy is permanent; pointers are disposable — different layers.*)

The consequence for transfer: the unit that moves between islands is a **whole, self-contained,
self-verifying artifact** — never a handle into another origin's storage. A data-pile already *is*
such an artifact: its signed manifest is "the **sole** integrity anchor: it travels with the data, so
it holds no matter how the bytes were transported" ([`CONTRACT.md` Layer 2](../CONTRACT.md)). So a
pile is **sendable** by construction. This note makes the sending and receiving explicit.

## B. Channel 2 — the drop manifest

The Tell feed (channel 1) is a one-way ratchet whose seed only Tell holds, so an out-of-band
contribution cannot extend it. The drop channel is a **parallel, independently anchored** feed:

- **Its own branch — `feed/drop`** (parallel to `feed/tell`), preserving `bin/ingest`'s
  *one source per branch* invariant ([`CONTRACT.md`](../CONTRACT.md) feed protocol). The pile always
  knows which channel added which blocks.
- **No shared seed, no ratchet.** Each block is encrypted under a **random per-block key** `Kb`
  (`aes-256-ctr`, `dp_enc` / IV via `dp_iv` — unchanged from channel 1). `Kb` is itself
  **`age`-wrapped to the pile's committed recipient** `keys/pile.age.pub` and committed as
  `inbox/<seq>.kage`, beside the ciphertext `inbox/<seq>.enc`. There is no `seed.age`, because there
  is no seed.
- **Per-block commitment, not a ratchet commitment.** The manifest entry's commitment field carries
  `sha256("pub:" || Kb)` — computed by the existing `dp_ratchet_pub`, so it is the **same
  `sha256:<64-hex>` shape** the entry schema and `bin/verify` already expect. Semantically it commits
  to *this block's* key only; blocks are independent.
- **Signed by the sender, in a distinct namespace.** The manifest head is signed with the sender's
  SSH key under namespace **`data-pile-drop`** — distinct from `data-pile` (the ratchet feed) and
  `tell-poll` (the QR, see
  [`qr-provenance.md`](https://github.com/FCCN-ANTIBODY/tell.anecdote.channel/blob/main/docs/qr-provenance.md)).
  A signature from one channel can therefore **never replay** into another.
- **Trust without a registry.** The receiver verifies the head against a locally held
  accepted-signers set **`keys/drop.signers`** (the same `allowed_signers` idiom as
  `keys/tell.signers`). A signature that verifies against an *unknown* signer is **recorded for a
  later trust decision** (open intake) rather than trusted — exactly the
  [`qr-provenance.md` § "Trust roots without a registry"](https://github.com/FCCN-ANTIBODY/tell.anecdote.channel/blob/main/docs/qr-provenance.md)
  rule.

### Manifest entry (delta from [`CONTRACT.md` Layer 2](../CONTRACT.md))

The envelope `{ "version", "source", "entries": [ … ], "head": { "seq", "digest", "sig" } }` is
unchanged; `source` is `"drop"`. Each entry:

```json
{
  "seq": 0,
  "created_at": "2026-06-25T00:00:00Z",
  "source": "drop",
  "block": "000000.enc",
  "key": "000000.kage",        // age-wrapped per-block key Kb (NEW; replaces the shared seed.age)
  "this_hash": "sha256:…",     // sha256 of inbox/<seq>.enc — identical meaning to channel 1
  "prev_hash": null,           // this_hash of seq-1; null at genesis — identical
  "ratchet_pub": "sha256:…"    // = sha256("pub:" || Kb): a PER-BLOCK commitment, same shape
}
```

Only the `key` field is added and only the *meaning* of `ratchet_pub` changes (per-block, not
chained). Everything `bin/verify` checks structurally — seq order, `prev_hash` continuity, the
`this_hash` ciphertext hash, the `sha256:<64-hex>` commitment shape, the head digest and signature —
holds without modification. The verifier needs exactly two knobs, both already CLI-shaped:
`--source drop` (→ `keys/drop.signers`) and the namespace `data-pile-drop`.

### Disclosure parity with `bin/prove`

To take a drop block public, the owner reveals its `Kb`; anyone derives nothing else (blocks are
independent — strictly *more* isolated than the ratchet's forward-only disclosure). Verification is
the same shape as channel 1: decrypt `inbox/<seq>.enc` under the revealed `Kb`, confirm the plaintext
re-encrypts/`this_hash`-matches what the **signed** manifest committed. The owner never reveals
`PILE_AGE_IDENTITY`; the two decryption paths stay independent
([`ROADMAP.md`](../ROADMAP.md): "keep the two decryption paths independent").

## C. The sendable whole-pile bundle

"A data-pile is sendable" = export its sealed feed as a portable, self-contained tree and re-import
it elsewhere. Because the signed manifest is transport-agnostic, the bundle needs no live origin:

```
bundle/
  manifest.json        # the existing signed manifest — signature still valid, unchanged
  inbox/<seq>.enc      # the encrypted blocks, verbatim
  inbox/seed.age       # channel-1 ratchet seed  (OR inbox/<seq>.kage for a drop feed)
```

- **Same-owner relocation** (move a pile to a new origin/repo): copy the tree verbatim. The recipient
  runs the **existing** `bin/verify` then `bin/ingest` with `DP_FETCH_URL=file://…/bundle/` — no new
  verifier needed, because the signature already anchors the bytes.
- **Owner-to-owner handoff** (give the tank to a different owner): re-wrap only the key material to
  the destination recipient — `age -d` the seed/`kage` with the sender's identity, then
  `age -r <dest-recipient>` — leaving the signed manifest and ciphertext untouched. The chain still
  verifies; only *who can decrypt* changes.
- **Foreign-signed contributions** ride channel B (the drop verifier with `keys/drop.signers`); a
  same-owner bundle rides the channel-1 verifier. One bundle format, two trust roots.

A pile pushed out to a public subdomain chain (the apex/workspace spawning a node) is just this
bundle delivered to that origin's repo, which then serves and — when the owner chooses — `bin/prove`s
it public. The apex/workspace targets this **artifact contract** only; it needs nothing of the
receiving origin's internals.

## D. Clear-a-space ingress

To receive a relocated pile (or to retire a channel) the live space must be **cleared without
destroying signed legacy**. Reuse channel 1's history-bounding rule verbatim — Tell's
`prune-pile-history` action, which **never invalidates a signature**
([`CONTRACT.md`](../CONTRACT.md): "archive the intact signed chain to
`archive/feed/<source>@<stamp>`, reset the live ref lean, never rewrite signed commits"):

1. **Archive** the live `feed/<source>` → `archive/feed/<source>@<stamp>` (the signed chain stays
   intact and independently verifiable — permanent legacy).
2. **Reset** the live ref to genesis (the disposable pointer).
3. **Re-populate** by importing a bundle (C) or accepting drops (B) onto the now-empty live ref.

"An ingress so individual spaces can be cleared" is therefore: *archive + reset + import*. It honours
the standing invariant — leaks nothing, never rewrites a signature, and keeps `main` the clean face
while `feed/**` carries the log.

## E. What does not change

- `main` stays template + `pile.yml` + public `keys/` + chosen reports; the log lives on `feed/**`.
- Verification stays the gate: the drop channel gets **its own `bin/verify` variant, not a relaxed
  one** ([`ROADMAP.md`](../ROADMAP.md)).
- The pile remains a pure consumer: it ingests and stores ciphertext it can verify; it originates and
  seals nothing. The drop channel adds a *source*, not a sealing key.

## Build surface (when this is implemented)

| Piece | Reuses |
| --- | --- |
| `bin/send` — emit a bundle (C) from the current sealed feed | the feed tree as-is; `age` re-wrap for handoff |
| `bin/verify --source drop` — channel-B verifier | `dp_entries_digest`, the chain walk, `ssh-keygen -Y verify -n data-pile-drop -f keys/drop.signers` |
| `bin/ingest` — accept `file://` / local-bundle sources (D, E) | existing `DP_FETCH_URL` / `DP_STAGE_DIR` overrides |
| a `clear-space` workflow — archive + reset (D) | Tell's `prune-pile-history` composite action |
| `keys/drop.signers` — accepted-signers set for foreign drops | the `allowed_signers` / `keys/tell.signers` idiom |

A worked, illustrative drop manifest is at [`examples/drop-manifest.json`](examples/drop-manifest.json).
