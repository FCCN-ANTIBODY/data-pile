# data-pile

A replicable template for a **data tank**: a durable, **encrypted-at-rest** repo that collects
responses to questions *you own* and **keeps only what your questions permit**. Fork it, deploy it
(a **public** repo is the intended default), and only you can read what it holds — until you choose
to prove it to everyone.

A data-pile's counterpart is **[Tell](https://tell.anecdote.channel)**, not Atlas. You join Tells
to solicit your questions; they deliver responses, each Tell differently encrypted. There is also a
**direct QR path** (no Tell server) where a respondent's browser encrypts straight to your pile. A
pile **never talks to Atlas** — Atlas is, separately, a queue of unmet *needs* that Tells report to.

> **This repo is yours, not a glove.** A data-pile is an *owned* repo: you scope it, own its
> contents, and it runs its own actions on its own budget. The constellation's submodule engines
> (Tell, Atlas, Journal) are the "gloves" a *workspace* grafts in for turnkey behavior — a pile
> needs none of them to function. If someone submodules your pile, that's a watched bookmark.

- **What & why:** [`CONSTITUTION.md`](CONSTITUTION.md) (the law) and [`AGENTS.md`](AGENTS.md) (the why-map).
- **The interface:** [`CONTRACT.md`](CONTRACT.md) — sources, the crypto model, and the governor.

## How it works, in one breath

You author a question under `questions/<qid>/` with `guidance.json` (what answers you'll tolerate).
You join Tells (or post a direct-QR poll) soliciting it. Each source delivers encrypted responses to
its own `feed/<source>` branch. On a cadence your repo **verifies → decrypts → governs**: every
response is checked against the question's guidance + your CONSTITUTION, and the verdict
(accepted, or dropped with a reason) is written to a ledger that holds **no plaintext**. Edit the
guidance and re-run to re-filter — you're master of what enters.

```
a Tell you joined ─(ratchet-encrypted, signed)─▶ feed/<tell> ┐
direct QR (no server) ─(age-encrypted by client)─▶ feed/direct ┘
        │
   bin/ingest:  verify → decrypt → accept(questions/<qid>/guidance.json) → state/<src>/ledger.json
        │
   bin/report · bin/decrypt (owner) · bin/prove (go public)
```

## Deploy

1. **Use this template** to create your own repo (public is the default).
2. Run the **`setup`** workflow once: it generates an `age` keypair, commits the recipient key to
   `keys/pile.age.pub`, stores the private identity as the secret `PILE_AGE_IDENTITY`, and fills
   `pile.yml`.
3. **Author a question:** copy `questions/cd04-q1/` to your own `questions/<qid>/` and edit
   `question.json` + `guidance.json`.
4. **Join a Tell** with the **`join-tell`** workflow (opens a PR on that Tell), or post a direct-QR
   poll that addresses your pile. Record the source in `pile.yml` under `tells:`.
5. From then on, the **`ingest`** workflow verifies, decrypts, and governs deliveries on a cadence.

## Local toolbox (`bin/`)

| Command | Who | What |
| --- | --- | --- |
| `bin/verify` | anyone | Verify a feed: chain, per-block hashes, and (signed Tells) the signature against the registered signer. `--unsigned` for direct ingress. |
| `bin/accept` | owner | The governor: decide one decrypted response against a question's `guidance.json`. |
| `bin/ingest` | cron | Per source: verify → decrypt → accept → write the verdict ledger (`state/<src>/ledger.json`). |
| `bin/decrypt` | owner | `age`-decrypt a block or range (needs `PILE_AGE_IDENTITY`). |
| `bin/report` | owner | Build reports from accepted state. **Aggregation is yours to define.** |
| `bin/prove` | owner | Publish a ratchet checkpoint so others can verify (signed Tell feeds). |

## Privacy posture

- The committed `keys/pile.age.pub` can only encrypt. Your private identity is **never** committed.
- The ledger records verdicts and hashes, never plaintext; the encrypted log stays on `feed/**`.
- Run it private if you want; the encryption is the same. Public is the default because the design
  leaks nothing until you decide to prove it.
