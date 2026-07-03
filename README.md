# data-pile

A replicable template for a **data tank**: a durable, append-only, encrypted-at-rest log that
[Tell](https://github.com/FCCN-ANTIBODY/tell.anecdote.channel) feeds with digests of what has
happened since its last delivery. Fork it, deploy it (a **public** repo is the intended default),
and only you can read what it holds — until you choose to prove it to everyone.

- **What & why:** [`CONSTITUTION.md`](CONSTITUTION.md) (the law) and the why-shaped map in
  [`AGENTS.md`](AGENTS.md).
- **The interface with Tell:** [`CONTRACT.md`](CONTRACT.md) — the crypto model, the feed-branch
  protocol, and the handshake.
- **Where it's going:** [`ROADMAP.md`](ROADMAP.md). What's deferred for the whole constellation lives
  in one place, the workspace's
  [`OPEN-QUESTIONS.md`](https://github.com/FCCN-ANTIBODY/civic-node/blob/main/OPEN-QUESTIONS.md).
- **The whole poll lifecycle, step by step** — where this template fits, from copying it through the
  owner decoding the answers:
  [`civic-node/docs/PIPELINE.md`](https://github.com/FCCN-ANTIBODY/civic-node/blob/main/docs/PIPELINE.md).

## How it works, in one breath

Tell encrypts each digest to your committed `age` public key, hash-links it into a signed
manifest, and publishes it on **its own** domain. Your repo **pulls** it, verifies it, and stores it
— Tell never reaches into your repo. You can decrypt it (you hold the key); the public cannot. If
you ever want to go public, you publish a ratchet checkpoint and anyone can decrypt the committed
blocks and confirm they match the signed record — proving the data is real and unaltered.

```
Tell ──(age-encrypt + sign + hash-link)──▶ /piles/<id>/feed/*  (Tell's own domain)
                                                  │  your repo PULLS (no credential)
                              bin/ingest → bin/verify → your feed/tell branch + state/
                                                  │
                              bin/decrypt (owner) · bin/report · bin/prove (go public)
```

## Deploy

1. **Use this template** to create your own repo (public is the default).
2. Run the **`setup`** workflow once. It generates an `age` keypair, commits the recipient key to
   `keys/pile.age.pub`, stores the private identity as the repo secret `PILE_AGE_IDENTITY`, and
   fills in `pile.yml`.
3. Run the **`handshake`** workflow. It opens a registration PR on Tell with your `age_recipient`
   and feed branch — no write access to your repo is requested. Then pin Tell's published signer
   key into `keys/tell.signers` + `pile.yml` by hand (confirm the fingerprint out-of-band — see
   `keys/README.md`).
4. From then on, Tell publishes your encrypted feed at `/piles/<id>/feed/*`. The **`ingest`**
   workflow pulls, verifies, and folds it into your own `feed/tell` branch on a cadence.

A pile today is **self-service only** — the template, the `setup` workflow (with its hand-minted
`SETUP_TOKEN`), the handshake, the hand-pinned signer. Hosted or rented provisioning — someone
standing a pile up *for* you — does not exist yet; it is the gate on the whole GitHub-side rework,
tracked at civic-node
[`OPEN-QUESTIONS.md` §P](https://github.com/FCCN-ANTIBODY/civic-node/blob/main/OPEN-QUESTIONS.md) and
shaped in [`docs/TENANCY.md`](https://github.com/FCCN-ANTIBODY/civic-node/blob/main/docs/TENANCY.md).
A third party that manages piles must speak this repo's spec — or have its homebrew **attested in the
pile's metadata** when anything talks to it.

## Local toolbox (`bin/`)

| Command | Who | What |
| --- | --- | --- |
| `bin/verify` | anyone | Verify the chain, the signature against the registered signer, and ratchet commitments. |
| `bin/ingest` | cron | Pull each source's feed from its Tell gateway `url`, verify, persist into your own `feed/*` branch + `state/`. |
| `bin/decrypt` | owner | `age`-decrypt a block or range (needs `PILE_AGE_IDENTITY`). |
| `bin/report` | owner | Build reports from verified state. **Aggregation is yours to define.** |
| `bin/prove` | owner | Publish a ratchet checkpoint (or the identity) so others can verify. |

**Judging happens at your Tell, not here.** Tell applies the per-poll constitution you delegate to it
*before* it seals a digest — it judges the public Issue plaintext, so no key is involved — and every
record arrives carrying its `governed` verdict (`accept` / `reject` / `needs-judgment` / `held`) and
the `constitution_sha` that produced it. After `bin/decrypt` you read those verdicts and may
**re-judge by hand** at your boundary. The pile holds no judging round and no poll definitions; those
live in `constitutions/` on your Tell.

## Privacy posture

- The committed `keys/pile.age.pub` can only encrypt. Your private identity is **never** committed.
- Run it private if you want; the encryption is the same. Public is the default because the design
  is built so a public tank still leaks nothing until you decide to prove it.
