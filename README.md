# data-pile

A replicable template for a **data tank**: a durable, append-only, encrypted-at-rest log that
[Atlas](https://github.com/FCCN-ANTIBODY/atlas.anecdote.channel) feeds with digests of what has
happened since its last delivery. Fork it, deploy it (a **public** repo is the intended default),
and only you can read what it holds — until you choose to prove it to everyone.

- **What & why:** [`CONSTITUTION.md`](CONSTITUTION.md) (the law) and the why-shaped map in
  [`AGENTS.md`](AGENTS.md).
- **The interface with Atlas:** [`CONTRACT.md`](CONTRACT.md) — the crypto model, the feed-branch
  protocol, and the handshake.

## How it works, in one breath

Atlas encrypts each digest to your committed `age` public key, hash-links it into a signed
manifest, and publishes it on **its own** domain. Your repo **pulls** it, verifies it, and stores it
— Atlas never reaches into your repo. You can decrypt it (you hold the key); the public cannot. If
you ever want to go public, you publish a ratchet checkpoint and anyone can decrypt the committed
blocks and confirm they match the signed record — proving the data is real and unaltered.

```
Atlas ──(age-encrypt + sign + hash-link)──▶ /piles/<id>/feed/*  (Atlas's own domain)
                                                  │  your repo PULLS (no credential)
                              bin/ingest → bin/verify → your feed/atlas branch + state/
                                                  │
                              bin/decrypt (owner) · bin/report · bin/prove (go public)
```

## Deploy

1. **Use this template** to create your own repo (public is the default).
2. Run the **`setup`** workflow once. It generates an `age` keypair, commits the recipient key to
   `keys/pile.age.pub`, stores the private identity as the repo secret `PILE_AGE_IDENTITY`, and
   fills in `pile.yml`.
3. Run the **`handshake`** workflow. It opens a registration PR on Atlas with your `age_recipient`
   and feed branch — no write access to your repo is requested. Then pin Atlas's published signer
   key into `keys/atlas.signers` + `pile.yml` by hand (confirm the fingerprint out-of-band — see
   `keys/README.md`).
4. From then on, Atlas publishes your encrypted feed at `/piles/<id>/feed/*`. The **`ingest`**
   workflow pulls, verifies, and folds it into your own `feed/atlas` branch on a cadence.

## Local toolbox (`bin/`)

| Command | Who | What |
| --- | --- | --- |
| `bin/verify` | anyone | Verify the chain, the signature against the registered signer, and ratchet commitments. |
| `bin/ingest` | cron | Pull each source's feed from its Atlas gateway `url`, verify, persist into your own `feed/*` branch + `state/`. |
| `bin/decrypt` | owner | `age`-decrypt a block or range (needs `PILE_AGE_IDENTITY`). |
| `bin/report` | owner | Build reports from verified state. **Aggregation is yours to define.** |
| `bin/prove` | owner | Publish a ratchet checkpoint (or the identity) so others can verify. |

## Privacy posture

- The committed `keys/pile.age.pub` can only encrypt. Your private identity is **never** committed.
- Run it private if you want; the encryption is the same. Public is the default because the design
  is built so a public tank still leaks nothing until you decide to prove it.
