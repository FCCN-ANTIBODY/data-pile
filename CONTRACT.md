# The inbound digest contract

This document defines the interface between **Tell** (the producer of digests) and a
**data-pile** (the durable tank that receives them) — the *inbound, full-fidelity, encrypted*
channel: Tell → pile. Tell's side of it is specified in
[`tell.anecdote.channel/CONTRACT.md`](https://github.com/FCCN-ANTIBODY/tell.anecdote.channel/blob/main/CONTRACT.md).
A separate, *outbound, coarse, public* map a pile may also place onto **Atlas** (the public index)
is specified in
[`atlas.anecdote.channel/CONTRACT.md`](https://github.com/FCCN-ANTIBODY/atlas.anecdote.channel/blob/main/CONTRACT.md).

A data-pile is a replicable template. You fork it, deploy it (a **public** repo is the intended
default), and it becomes a tank: an append-only, hash-linked, **encrypted-at-rest** log of digests
Tell delivers. Everything is private by default even though the repo is public, because only the
pile owner holds the key that decrypts it. Later, the owner can publish keys to **prove** the data
is real and is the exact version Tell delivered — and can build reports from it.

Tell never reads the tank back. The pile owner does. Tell only writes.

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
- Tell symmetric-encrypts each block under its ratchet key `K_seq`
  (`aes-256-ctr`, IV = `sha256("iv:" || K_seq)[:16]`). The ciphertext is committed as
  `inbox/<seq>.enc`. Ciphertext integrity comes from the signed manifest (Layer 2), not from an
  AEAD tag.
- At genesis Tell delivers the seed `K_0` **`age`-encrypted to the committed recipient** as
  `inbox/seed.age`. The owner is the only party who can unwrap it; from `K_0` they derive every
  `K_seq` and decrypt the whole tank.
- Result: only the owner can read the tank, even though the world can clone it.

### Layer 2 — integrity (signed, hash-linked manifest)

`inbox/manifest.json` is an append-only chain. Each entry:

```json
{
  "seq": 0,
  "created_at": "2026-06-25T00:00:00Z",
  "source": "tell",
  "block": "000000.enc",
  "this_hash": "sha256:…",   // sha256 of the ciphertext block file
  "prev_hash": null,          // this_hash of seq-1; null at genesis
  "ratchet_pub": "sha256:…"   // public commitment to this block's ratchet key (Layer 3)
}
```

The manifest is `{ "version", "source", "entries": [ … ], "head": { "seq", "digest", "sig" } }`,
where `digest = sha256(canonical_json(entries))` and `sig` is a signature over that digest.

- The manifest **head is signed** by Tell's delivery key — an ordinary SSH signing key
  (`ssh-keygen -Y sign`), not a GitHub App. `bin/verify` recomputes `digest` and checks `sig`
  against the registered signer (`keys/<source>.signers`, an SSH allowed-signers file whose
  fingerprint must equal `pile.yml`'s `signer`). The pile pins that key by hand from Tell's
  published `keys/tell.fpr`, confirmed out-of-band / IRL (see the handshake). The signed head is the
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
  committed — proving the published data is exactly what Tell delivered.
- Publishing genesis `K_0` proves the whole history. Publishing a later checkpoint proves only from
  that point forward (scoped disclosure).
- The owner never has to reveal `PILE_AGE_IDENTITY` — which would also expose all future
  deliveries — to prove the past. The ratchet gives forward-only disclosure.

## The feed protocol (pull, not push)

Tell **never reaches into this repo** — the exact mirror of the outbound rule, where a pile places
onto Tell and Tell never pulls. Here Tell *publishes* and the pile *pulls*:

- **Tell side.** Tell produces each pile's chain on a `feed/<scope>/<id>` branch in its **own**
  repo (parallel to the outbound `pile/<scope>/<id>`) and serves it on its own domain at
  `/piles/<id>/feed/*` via the gateway Worker. Per digest Tell appends `inbox/<seq>.enc`
  (symmetric-encrypted under `K_seq`; at genesis also `inbox/seed.age`, the `age`-wrapped ratchet
  seed for the owner), updates and **re-signs** `inbox/manifest.json`. The encrypted payload is safe
  to serve openly.
- **Pile side.** `bin/ingest` (hourly, no credential) pulls `manifest.json` + every block + `seed.age`
  from the source's gateway `url`, runs `bin/verify`, and only on success commits the blocks into the
  pile's **own** `feed/<source>` branch (e.g. `feed/tell`) — the durable, owner-held tank — and folds
  the manifest into `state/`. **One source per branch**, so the pile always knows which channel added
  which blocks.
- `main` carries only the template, `pile.yml`, `keys/` (public), and any reports the owner chooses
  to publish — **never the encrypted log**. The log lives on the pile's `feed/**`. This keeps `main`
  clean and any site build narrow (mirrors Tell's "a placement never triggers a rebuild").
- **History bounding** reuses Tell's `prune-pile-history.yml` approach: archive the intact signed
  chain to `archive/feed/<source>@<stamp>`, reset the live ref lean, never rewrite signed commits.

## What the pile is — and is not

The pile is a **pure consumer**: an encrypted mailbox plus a reader. It **collects nothing** (no
Issue intake, no QR, no poll definitions — those live on Tell), it **judges nothing as a round**
(Tell attaches the delegated verdict before sealing; the owner may re-judge by hand), and it holds
**no key that seals** — only its *public* `age` recipient (`keys/pile.age.pub`, encrypt-only) and,
as a repo secret, the *private* identity that **decrypts**. Everything inbound is already ciphertext
produced by Tell; the pile verifies and stores it. Keep it that way: anything that would have the
pile ingest, encrypt, or originate data belongs on a Tell, not here.

> **Second channel (specified, not yet built): Tell-less out-of-band contribution.** This document
> governs **channel 1** — the inbound Tell ratchet feed. Because `keys/pile.age.pub` is public, a
> contributor *could* encrypt a payload to the pile directly, without any Tell. What is missing is an
> ingest path for it: today's chain is a one-way ratchet whose seed only Tell holds, so an
> out-of-band drop needs a separate, non-ratcheted **`feed/drop`** channel (age-to-recipient,
> independently anchored, signed in its own namespace). That deliberate second ingest mode — plus the
> sendable whole-pile bundle and the archive-and-reset *clear-space* gesture — is now specified in
> [`docs/transfer.md`](docs/transfer.md); it solves storage and encryption out of band, *not* by
> borrowing Tell's key. Tracked as
> [`OPEN-QUESTIONS.md` → "G. Tell-less pile ingest"](https://github.com/FCCN-ANTIBODY/civic-node/blob/main/OPEN-QUESTIONS.md#g-tell-less-pile-ingest).

## The handshake (owner-initiated)

1. **Deploy.** Fork the template (public). `setup.yml` generates the `age` keypair, commits
   `keys/pile.age.pub`, stores `PILE_AGE_IDENTITY` as a repo secret, and fills `pile.yml`.
2. **Owner → PR on Tell.** `handshake.yml` opens a registration PR adding the pile's entry to
   `tell.anecdote.channel/_data/piles.yml` (id, scope, the `feed/<scope>/<id>` branch, the pile's
   `age_recipient`, the repo URL). This PR is the consent signal — and all it grants Tell is *where
   to wrap digests for* this pile. It does **not** grant Tell any write access.
3. **Pin Tell's signer (by hand).** Copy Tell's published `keys/tell.signers` into this pile's
   `keys/tell.signers` and its `keys/tell.fpr` value into `pile.yml` `signer`. **Confirm the
   fingerprint out-of-band / IRL** — a local vouching for the key a local will trust. This is the
   whole trust handoff; there is no app to install and no token to issue.
4. **Tell publishes; the pile pulls.** Once registered, Tell produces the encrypted feed on its own
   `feed/<scope>/<id>` branch and serves it at `/piles/<id>/feed/*`. This pile's `ingest.yml` pulls,
   verifies, and persists into its own feed branch. Tell never touches this repo.

## What the pile requires of Tell

The pile depends only on this. How Tell stages digests internally (e.g. batching) is Tell's
concern.

- Each block MUST be `age`-encrypted to the pile's committed recipient.
- Each block MUST be hashed into the signed `manifest.json` chain and carry a `ratchet_pub`
  commitment.
- The manifest head MUST be signed by a key matching the Tell `signer` fingerprint the pile pinned.
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
