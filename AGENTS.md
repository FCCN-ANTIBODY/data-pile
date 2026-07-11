# Orientation

This repository is one **data-pile**: a tank meant to be copied — an encrypted mailbox plus a
reader, the durable system of record. It is a pure consumer: it pulls sealed digests from its
Tell's own surface, verifies the signed chain, and persists them onto `feed/**`. Only its owner
can read what it holds — until the owner chooses to prove it, publicly and verifiably.

## Where the truth is, in reading order

1. **Demos before docs.** The constellation's capability index is the demo shelf in
   [`anecdote.channel`](https://github.com/FCCN-ANTIBODY/anecdote.channel) (`composer/*-demo.html`,
   `viewer/`, `git-enough/`, `reducer/demo.mjs` — its `AGENTS.md` carries the table). The
   browser-minted `age` identity, the answered-polls trove, and the offline registration exchange
   this pile depends on are demoed there. Before designing a capability, look for its demo. This
   repo's own executable truth is `test/run.sh` (+ `test/make-fixtures.sh`) and the `bin/` tools.
2. **Open issues are urgent** — a live problem with the current implementation, ahead of the
   deferred backlog. Roadmapping does *not* live in issues; it lives in the documents
   (`ROADMAP.md`, civic-node `VISION.md`), and design writing is moving back into repo files, off
   the public issue surface.
3. **The deferred half lives in one place** — civic-node
   [`OPEN-QUESTIONS.md`](https://github.com/FCCN-ANTIBODY/civic-node/blob/main/OPEN-QUESTIONS.md).
   Record a deferral there rather than threading a caveat through the law or the spec. The drop
   channel and whole-pile transfer are specified (not built) in `docs/transfer.md` (§G there).
4. **The law, then the wire.** `CONSTITUTION.md` binds; `CONTRACT.md` covers the interface with
   Tell (and the provisioner attestation).

## The offline origin is the destination

Capability is migrating off GitHub and down to the operator's device — the anecdote.channel PWA,
where signing happens and where a pile's `age` identity can now be minted without any VPS
(`age-mint.mjs`, byte-interoperable with the real tool; the identity never leaves the device).
The workflows here (`ingest.yml`, `provision.yml`, `setup.yml`) are being **kept as a declarative
definition of the pipeline** — a configuration input an operator or the offline origin can read
and mirror — not as the presumed runtime. Whether or not GitHub holds the secrets to run a
workflow, the offline origin does.

## Invariants — violate these and you're building the wrong system

1. **Neighbors, not a graph.** A pile answers to its owner's key, nobody else.
2. **Verify-from-anyone; trust decides *action*, not *admission*.** The signed manifest is the
   sole integrity anchor and travels with the bytes; `keys/*.signers` decides whose deliveries you
   act on. Nothing is trusted until `bin/verify` passes.
3. **Witness, not judge.** The pile judges nothing as a round; governance happens upstream at Tell
   or owner-side after decrypt. Don't bake an aggregation model into the template — `bin/report`
   is a deliberate stub.
4. **Sign ≠ decrypt — the custody line.** The token creates the tank; only the owner ever holds
   what opens it. A `--provisioner` never touches the identity (`--provisioner` ⊥ `--keygen`,
   enforced; `bin/check-custody` guards the boundary in CI).
5. **Honest defaults fire nothing.** Disclosure (`bin/prove`) is owner-initiated and forward-only;
   the master identity is never surrendered.
6. **Attest before you run.** New conduct is declared in words before it is coded.
7. **Content commitments are `ratchet_pub`/`this_hash`** under the signed `head.digest`. Reuse
   `bin/lib.sh` primitives; don't invent hashing.
8. **No new cryptography without cause.** `age` (X25519), `openssl` aes-ctr, `ssh-keygen -Y`
   (namespaced: `data-pile` for the Tell feed, `data-pile-drop` for the drop channel), `sha256`.
   A new channel is a *source*, not a relaxed verifier.

## Where intuition goes wrong here

- **The tank collects; nothing reaches into it.** The pile **pulls** from Tell's public surface;
  Tell never reads the pile back and never writes into it. The signed manifest — not the
  transport — is what makes a delivery trustworthy, so no producer ever needs a credential here.
- **`main` is the clean face; `feed/**` is the log.** The encrypted append-log never lands on
  `main`; no workflow commits `inbox/**` to `main`.
- **Two decryption paths, on purpose.** The `age` identity (owner-only, everything) and the hash
  ratchet (scoped, publishable) are independent — proving the past must never require revealing
  the master identity.
- **Privacy is the floor.** If a change weakens "leaks nothing until the owner decides," it is
  wrong.

## Built here — reuse, don't rebuild

`bin/pile-new` (one-gesture provision: `--recipient` absent-owner / `--keygen` owns-it),
`bin/ingest` + `bin/verify` (pull + verify a signed feed), `bin/prove` (commit-and-reveal — a
key-less party verifies against the signed manifest; this *is* the public-husk backing),
`bin/report` (documented stub — aggregation is deliberately undecided, owner's to define),
`keys/custody.yml` + `bin/check-custody`.

House test style: bash, `age` + `openssl` + `jq`, `test/run.sh` — ssh-optional by design
(`DP_ALLOW_UNSIGNED` auto-skips the signature leg where `ssh-keygen` is absent). Verify locally;
CI exercises the signature.
