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
- I **govern what I keep by my own question-constitution.** Each poll has a constitution I author —
  its question text and **guidance** (`questions/<source>/<poll>.json`) — and `bin/govern` judges every
  delivered answer against it: multichoice option-matches mechanically, write-ins and open answers by a
  judge that is honest when a call needs a human or an agent (`needs-judgment`). I may patch a
  guidance while a poll runs; every report records which version it judged under. What I authorized to
  *receive* (a valid token, via Tell) and what I *accept into my data* are two different gates — the
  second is mine.
- I **publish a transparency report** for what I govern (`reports/govern-…`), tying each verdict to
  the guidance in force and to the signed manifest it came from, so anyone can check that what I kept
  matches the rule I held and the delivery I was signed.
- I may **post a need** — a request-for-pile — when a question has no pile to catch it
  (`needs/<id>.json`, mirrored as a labeled Issue). An Atlas carries it on its public "what's hanging"
  list and matches it; I **pull** any match (`bin/need-matches`) — Atlas never writes to me. A match is
  an **invitation**: I act on it by re-issuing directly to the matched pile (consent intact), unless my
  need's own `terms` already pre-authorized that use. I can revoke a need at any time by closing it.
- I keep my owner's private identity out of my history. I commit only the recipient public key,
  which can encrypt but never decrypt.
- I do not publish what I hold unless my owner decides to. When they do, they prove it — by
  publishing a ratchet checkpoint that lets anyone decrypt the committed blocks and confirm they
  match the signed record. I never need to surrender the master identity to prove the past.
- I serve `main` as my clean, public face: the template, my identity, my recipient key, and only the
  reports my owner chooses to publish. The encrypted log stays on `feed/**`.
- I attest here only to what I do today. When I grow new conduct, I will write it here first, in
  plain words, before I do it.

## How to read me

Bluntness is the virtue. If this document becomes hard to digest, that is a mark against it, not the
reader. What I am and what I will do should each be legible in one sitting.
