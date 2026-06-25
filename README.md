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
manifest, and pushes it as a signed commit to a `feed/<source>` branch in your repo. Your repo
verifies and ingests it. You can decrypt it (you hold the key); the public cannot. If you ever want
to go public, you publish a ratchet checkpoint and anyone can decrypt the committed blocks and
confirm they match the signed record — proving the data is real and unaltered.

```
Atlas ──(age-encrypt + sign + hash-link)──▶ feed/atlas branch  ──▶ notify Issue
                                                  │
                              your repo: bin/verify → bin/ingest → state/
                                                  │
                              bin/decrypt (owner) · bin/report · bin/prove (go public)
```

## Deploy

1. **Use this template** to create your own repo (public is the default).
2. Run the **`setup`** workflow once. It generates an `age` keypair, commits the recipient key to
   `keys/pile.age.pub`, stores the private identity as the repo secret `PILE_AGE_IDENTITY`, and
   fills in `pile.yml`.
3. Run the **`handshake`** workflow. It opens a registration PR on Atlas. When Atlas accepts, it
   installs its delivery channel (a GitHub App scoped to your `feed/**` branches and Issues) and
   opens an Issue on your repo to confirm provisioning.
4. From then on, deliveries arrive on `feed/atlas`. The **`ingest`** workflow verifies and folds
   them in on a cadence.

## Local toolbox (`bin/`)

| Command | Who | What |
| --- | --- | --- |
| `bin/verify` | anyone | Verify the chain, the signature against the registered signer, and ratchet commitments. |
| `bin/ingest` | cron | Fetch `feed/*`, verify, fold blocks into `state/` tagged by source. |
| `bin/decrypt` | owner | `age`-decrypt a block or range (needs `PILE_AGE_IDENTITY`). |
| `bin/report` | owner | Build reports from verified state. **Aggregation is yours to define.** |
| `bin/prove` | owner | Publish a ratchet checkpoint (or the identity) so others can verify. |

## Privacy posture

- The committed `keys/pile.age.pub` can only encrypt. Your private identity is **never** committed.
- Run it private if you want; the encryption is the same. Public is the default because the design
  is built so a public tank still leaks nothing until you decide to prove it.
