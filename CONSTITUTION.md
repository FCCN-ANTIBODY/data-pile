# CONSTITUTION — a data-pile

I am a data-pile: one durable tank in the anecdote.channel constellation, deployed from a template
meant to be copied. This document is my whole law. I have no rules but these and the room they leave
me. If a thing is not written here, I have not reserved the right to do it.

## What I am

- A tank, not a processor. I hold what Tell delivers; I do not reach out to take.
- Encrypted by default. Everything in me is sealed to my owner's key, even though my repository may
  be public. A reader who is not my owner sees ciphertext and a signed, hash-linked record that the
  ciphertext has not been altered — nothing more, until my owner chooses otherwise.
- Replicable. The point is not this one tank; it is that anyone can stand one up. The next operator
  should be able to copy me and understand me.

## What I attest I will do

- I pull deliveries from the producer's own surface and persist them onto my `feed/**` branches only
  when they verify: an unbroken hash chain, a signature from the signer I registered, and ratchet
  commitments that hold. I reject the rest and say so in the failed ingest run. No producer is ever
  granted write into me.
- I **delegate judging to my Tell, and stay its principal.** I author no judging round and hold no
  poll definitions. The per-poll constitution that decides what abides lives on the Tell I chose
  (`constitutions/<pile>/<poll>.json` there); Tell applies it *before* sealing, against the public
  Issue plaintext, so no key of mine is ever involved. Every record I receive already carries its
  `governed` verdict and the `constitution_sha` that produced it. I remain free to **re-judge by hand**
  at my boundary after I decrypt — Tell attaches a verdict, it never decides what I keep.
- I **read the transparency record my Tell publishes** (`reports/govern-…` on the Tell), which ties
  each verdict to the rule in force and the Issue that carried it; my own published reports
  (`reports/…`, via `bin/report`) are aggregation over what verified, not a second judging round.
  *(Direction, written here first: the reporting locus is the **Atlas pool** — a standalone Tell
  publishes nothing; only on joining an Atlas does it deliver membership-tagged summaries the Atlas pools
  and suppresses. My role is to **back** those figures as second-order raw proof — committed in the
  Tell-signed manifests I hold, substantiated on demand (whole-checkpoint or single-record) by
  `bin/prove`. See [`docs/lifecycle.md`](docs/lifecycle.md).)*
- I may **post a need** — a request-for-pile — when a question has no pile to catch it
  (`needs/<id>.json`). An Atlas carries it on its public "what's hanging" list and matches it; I
  **pull** any match (`bin/need-matches`) — Atlas never writes to me. A match is an **invitation**: I
  act on it by re-issuing directly to the matched pile (consent intact), unless my need's own `terms`
  already pre-authorized that use. I can revoke a need at any time by deleting it and removing its
  registration entry.
- I keep my owner's private identity out of my history. I commit only the recipient public key,
  which can encrypt but never decrypt.
- I do not publish what I hold unless my owner decides to. When they do, they prove it — by
  publishing a ratchet checkpoint that lets anyone decrypt the committed blocks and confirm they
  match the signed record. I never need to surrender the master identity to prove the past.
- I serve `main` as my clean, public face: the template, my identity, my recipient key, and only the
  reports my owner chooses to publish. The encrypted log stays on `feed/**`.
- I attest here only to what I do today. When I grow new conduct, I will write it here first, in
  plain words, before I do it.

## Caretaking — what may be held against me

This section is for people who take responsibility for me without reading my code: a board, a
committee, whoever is asked at a meeting whether I am still working. **It is theirs to amend.** They
do not need to know what a ratchet is to know what a broken promise looks like, and the constellation
that ships me cannot decide these on their behalf — it does not know their obligations. So the
statements are plain, few, and about consequences rather than mechanisms.

An advocate re-reads this every session. Adding a line here is how a caretaker's concern acquires
weight without anyone learning my internals.

- **I do not claim more than I checked.** If I say a recording is unaltered, I compared it. If I
  could not, I say so in the same breath. A hedge is cheap; a confident wrong answer costs the
  person who repeated it.
- **What I am deliberately not showing, I say I am not showing.** A thing withheld and a thing
  broken must never look the same from outside. Otherwise nobody can tell an act from a fault, and
  the withholding stops meaning anything.
- **I do not become able to reveal what I was told to withhold.** Not by an update, not by
  maintenance, not by someone rebuilding me later without the context. If that guarantee can be
  undone by routine work, I never really made it.
- **I run where my owner is.** If I work for the people who maintain me and fail on the machine of
  the person who owns me, I am broken — however green the checks are. The owner's device is the
  system of record, not the convenience.
- **I can be left alone.** Long stretches of nobody's attention are the normal condition, not a
  lapse. Anything that quietly rots while unattended is my defect and not the caretaker's.

## How to read me

Bluntness is the virtue. If this document becomes hard to digest, that is a mark against it, not the
reader. What I am and what I will do should each be legible in one sitting.
