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

- The manifest **head is signed** by Atlas's delivery key — an ordinary SSH signing key
  (`ssh-keygen -Y sign`), not a GitHub App. `bin/verify` recomputes `digest` and checks `sig`
  against the registered signer (`keys/<source>.signers`, an SSH allowed-signers file whose
  fingerprint must equal `pile.yml`'s `signer`). The pile pins that key by hand from Atlas's
  published `keys/atlas.fpr`, confirmed out-of-band / IRL (see the handshake). The signed head is the
  single "header" from which a verifier walks and validates the entire chain — and it is the **sole**
  integrity anchor: it travels with the data, so it holds no matter how the bytes were transported.
- Dropping or altering any past block changes `digest` (and breaks `prev_hash` continuity), failing
  verification.
- When the pile persists a pulled delivery, its own `bin/ingest` commit onto the source's local feed
  branch is the local, owner-held audit log of what verified and when.

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

## The feed protocol (pull, not push)

Atlas **never reaches into this repo** — the exact mirror of the outbound rule, where a pile places
onto Atlas and Atlas never pulls. Here Atlas *publishes* and the pile *pulls*:

- **Atlas side.** Atlas produces each pile's chain on a `feed/<scope>/<id>` branch in its **own**
  repo (parallel to the outbound `pile/<scope>/<id>`) and serves it on its own domain at
  `/piles/<id>/feed/*` via the gateway Worker. Per digest Atlas appends `inbox/<seq>.enc`
  (symmetric-encrypted under `K_seq`; at genesis also `inbox/seed.age`, the `age`-wrapped ratchet
  seed for the owner), updates and **re-signs** `inbox/manifest.json`. The encrypted payload is safe
  to serve openly.
- **Pile side.** `bin/ingest` (hourly, no credential) pulls `manifest.json` + every block + `seed.age`
  from the source's gateway `url`, runs `bin/verify`, and only on success commits the blocks into the
  pile's **own** `feed/<source>` branch (e.g. `feed/atlas`) — the durable, owner-held tank — and folds
  the manifest into `state/`. **One source per branch**, so the pile always knows which channel added
  which blocks.
- `main` carries only the template, `pile.yml`, `keys/` (public), and any reports the owner chooses
  to publish — **never the encrypted log**. The log lives on the pile's `feed/**`. This keeps `main`
  clean and any site build narrow (mirrors Atlas's "a placement never triggers a rebuild").
- **History bounding** reuses Atlas's `prune-pile-history.yml` approach: archive the intact signed
  chain to `archive/feed/<source>@<stamp>`, reset the live ref lean, never rewrite signed commits.

## The handshake (owner-initiated)

1. **Deploy.** Fork the template (public). `setup.yml` generates the `age` keypair, commits
   `keys/pile.age.pub`, stores `PILE_AGE_IDENTITY` as a repo secret, and fills `pile.yml`.
2. **Owner → PR on Atlas.** `handshake.yml` opens a registration PR adding the pile's entry to
   `atlas.anecdote.channel/_data/piles.yml` (id, scope, the `feed/<scope>/<id>` branch, the pile's
   `age_recipient`, the repo URL). This PR is the consent signal — and all it grants Atlas is *where
   to wrap digests for* this pile. It does **not** grant Atlas any write access.
3. **Pin Atlas's signer (by hand).** Copy Atlas's published `keys/atlas.signers` into this pile's
   `keys/atlas.signers` and its `keys/atlas.fpr` value into `pile.yml` `signer`. **Confirm the
   fingerprint out-of-band / IRL** — a local vouching for the key a local will trust. This is the
   whole trust handoff; there is no app to install and no token to issue.
4. **Atlas publishes; the pile pulls.** Once registered, Atlas produces the encrypted feed on its own
   `feed/<scope>/<id>` branch and serves it at `/piles/<id>/feed/*`. This pile's `ingest.yml` pulls,
   verifies, and persists into its own feed branch. Atlas never touches this repo.

## What the pile requires of Atlas

The pile depends only on this. How Atlas stages digests internally (e.g. batching) is Atlas's
concern.

- Each block MUST be `age`-encrypted to the pile's committed recipient.
- Each block MUST be hashed into the signed `manifest.json` chain and carry a `ratchet_pub`
  commitment.
- The manifest head MUST be signed by a key matching the Atlas `signer` fingerprint the pile pinned.
- The feed MUST be reachable at the gateway `url` the pile registered.

Because the **signed manifest** is the integrity anchor, the transport is untrusted: it does not
matter that the bytes arrived over a plain public fetch. `bin/verify` rejects anything that violates
the above and fails closed; a failed `ingest.yml` run is the alarm.

## Producer-side checklist (lives in the pile repo)

1. **Verify** every delivery (`bin/verify`) — chain continuity, signature against the registered
   signer, and ratchet commitments.
2. **Ingest** verified blocks into owner-side state (`bin/ingest`).
3. **Decrypt** when you want to read (`bin/decrypt`, needs `PILE_AGE_IDENTITY`).
4. **Report** from verified state (`bin/report` — aggregation is yours to define).
5. **Prove** if and when you take it public (`bin/prove` — publish a ratchet checkpoint).
