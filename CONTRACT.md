# The inbound digest contract

This document defines the interface between **Atlas** (the producer of digests) and a
**data-pile** (the durable tank that receives them). It is the inbound mirror of
[`atlas.anecdote.channel/CONTRACT.md`](https://github.com/FCCN-ANTIBODY/atlas.anecdote.channel/blob/main/CONTRACT.md),
which covers only the *outbound, coarse, public* map a pile places onto Atlas. This covers the
*inbound, full-fidelity, encrypted* channel: Atlas → pile.

A data-pile is a replicable template. You fork it, deploy it (a **public** repo is the intended
default), and it becomes a tank: an append-only, hash-linked, **encrypted-at-rest** log of digests
Atlas delivers. Everything is private by default even though the repo is public, because only the
pile owner holds the key that decrypts it. Later, the owner can publish keys to **prove** the data
is real and is the exact version Atlas delivered — and can build reports from it.

Atlas never reads the tank back. The pile owner does. Atlas only writes.

## The crypto model

Privacy by default, tamper-evidence always, and provable public disclosure when the owner chooses —
built from a hash ratchet, symmetric encryption, an `age`-wrapped seed, and a signed hash chain.
Nothing secret is ever committed to the public repo.

The unifying idea: a **forward hash ratchet** does the encryption *and* enables disclosure. A seed
`K_0` is drawn once; `K_{seq+1} = sha256("ratchet:" || K_seq)`. Each digest block `seq` is
symmetric-encrypted under `K_seq`, so each digest is independently keyed and the key advances every
delivery (the "new key each digest" rotation). Because the ratchet is one-way, revealing `K_n`
discloses blocks `seq ≥ n` and **never** the blocks before it.

### Layer 1 — encryption at rest (ratchet + `age`-wrapped seed)

- At setup the pile generates an [`age`](https://github.com/FiloSottile/age) keypair. The
  **recipient public key** is committed at `keys/pile.age.pub`. It can only encrypt, so it is safe
  in a public repo. The **private identity is never committed** — it lives with the owner as the
  GitHub secret `PILE_AGE_IDENTITY` and/or offline.
- Atlas symmetric-encrypts each block under its ratchet key `K_seq`
  (`aes-256-ctr`, IV = `sha256("iv:" || K_seq)[:16]`). The ciphertext is committed as
  `inbox/<seq>.enc`. Ciphertext integrity comes from the signed manifest (Layer 2), not from an
  AEAD tag.
- At genesis Atlas delivers the seed `K_0` **`age`-encrypted to the committed recipient** as
  `inbox/seed.age`. The owner is the only party who can unwrap it; from `K_0` they derive every
  `K_seq` and decrypt the whole tank.
- Result: only the owner can read the tank, even though the world can clone it.

### Layer 2 — integrity (signed, hash-linked manifest)

`inbox/manifest.json` is an append-only chain. Each entry:

```json
{
  "seq": 0,
  "created_at": "2026-06-25T00:00:00Z",
  "source": "atlas",
  "block": "000000.enc",
  "this_hash": "sha256:…",   // sha256 of the ciphertext block file
  "prev_hash": null,          // this_hash of seq-1; null at genesis
  "ratchet_pub": "sha256:…"   // public commitment to this block's ratchet key (Layer 3)
}
```

The manifest is `{ "version", "source", "entries": [ … ], "head": { "seq", "digest", "sig" } }`,
where `digest = sha256(canonical_json(entries))` and `sig` is a signature over that digest.

- The manifest **head is signed** by Atlas's delivery key, reusing the SSH/commit-signing trust
  anchor the Atlas `signer` fingerprint already establishes (the same fingerprint the pile
  registered with Atlas at handshake). `bin/verify` recomputes `digest` and checks `sig` against the
  registered signer (`keys/<source>.signers`, an SSH allowed-signers file whose fingerprint must
  equal `pile.yml`'s `signer`). The signed head is the single "header" from which a verifier walks
  and validates the entire chain.
- Dropping or altering any past block changes `digest` (and breaks `prev_hash` continuity), failing
  verification.
- Each delivery is **also a signed git commit** on the source's feed branch, so the branch history
  is a second, redundant signed audit log.

### Layer 3 — disclosure (the same ratchet)

The ratchet that encrypts blocks also governs disclosure. The manifest stores only
`ratchet_pub = sha256("pub:" || K_seq)` — a commitment, never the key.

- To take the tank (or part of it) public, the owner runs `bin/prove` and publishes a **checkpoint
  key** `K_n`. Anyone can then derive `K_n, K_{n+1}, …`, decrypt every committed block from
  `seq = n` onward, and confirm each plaintext hashes to what the **signed** manifest already
  committed — proving the published data is exactly what Atlas delivered.
- Publishing genesis `K_0` proves the whole history. Publishing a later checkpoint proves only from
  that point forward (scoped disclosure).
- The owner never has to reveal `PILE_AGE_IDENTITY` — which would also expose all future
  deliveries — to prove the past. The ratchet gives forward-only disclosure.

## The feed branch protocol

- **One branch per source**, prefixed `feed/<source>` (e.g. `feed/atlas`). Multiple Atlas
  instances or other producers each own a distinct branch, so the pile always knows which channel
  added which blocks. `bin/ingest` folds blocks in tagged by source.
- Per digest, Atlas:
  1. appends `inbox/<seq>.enc` (the block, symmetric-encrypted under `K_seq`; at genesis also
     `inbox/seed.age`, the `age`-wrapped ratchet seed for the owner),
  2. updates and re-signs `inbox/manifest.json`,
  3. commits with a **signed** commit, pushes to `feed/<source>`,
  4. opens or appends a notify **Issue** (`digest seq N delivered`).
- `main` carries only the template, `pile.yml`, `keys/pile.age.pub`, and any reports the owner
  chooses to publish — **never the encrypted log**. The log lives on `feed/**`. This keeps `main`
  clean and any site build narrow (mirrors Atlas's "a placement never triggers a rebuild").
- **History bounding** reuses Atlas's `prune-pile-history.yml` approach: archive the intact signed
  chain to `archive/feed/<source>@<stamp>`, reset the live ref lean, never rewrite signed commits.

## The handshake (owner-initiated)

1. **Deploy.** Fork the template (public). `setup.yml` generates the `age` keypair, commits
   `keys/pile.age.pub`, stores `PILE_AGE_IDENTITY` as a repo secret, and fills `pile.yml`.
2. **Owner → PR on Atlas.** `handshake.yml` opens a registration PR adding the pile's entry to
   `atlas.anecdote.channel/_data/piles.yml` (id, scope, the `feed/atlas` expectation, the `signer`
   fingerprint, the age recipient fingerprint, the repo URL). This PR is the consent signal.
3. **Atlas reciprocates.** When Atlas accepts the registration it opens an Issue on the pile —
   *"you weren't aggregated yet → now provisioning"* — establishing the channel.
4. **Privileged write.** Atlas needs write to the pile's `feed/**` and Issues, including on private
   piles. This is granted at handshake by installing the **Atlas GitHub App** (per-repo, revocable,
   scoped to `feed/**` + issues). Atlas does not get `main`.
5. **Delivery begins.** Atlas pushes encrypted digests to `feed/atlas` and notifies via Issues.

## What the pile requires of Atlas

The pile depends only on this. How Atlas stages digests internally (e.g. batching) is Atlas's
concern.

- Each block MUST be `age`-encrypted to the pile's committed recipient.
- Each block MUST be hashed into the signed `manifest.json` chain and carry a `ratchet_pub`
  commitment.
- Each delivery MUST arrive as a signed git commit on `feed/<source>` plus a notify Issue.
- The signing key MUST match the `signer` fingerprint the pile registered with Atlas.

`bin/verify` rejects anything that violates the above; failures are surfaced on the notify Issue.

## Producer-side checklist (lives in the pile repo)

1. **Verify** every delivery (`bin/verify`) — chain continuity, signature against the registered
   signer, and ratchet commitments.
2. **Ingest** verified blocks into owner-side state (`bin/ingest`).
3. **Decrypt** when you want to read (`bin/decrypt`, needs `PILE_AGE_IDENTITY`).
4. **Report** from verified state (`bin/report` — aggregation is yours to define).
5. **Prove** if and when you take it public (`bin/prove` — publish a ratchet checkpoint).
