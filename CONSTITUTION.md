# CONSTITUTION — a data-pile

I am a data-pile: one durable tank in the anecdote.channel constellation, deployed from a template
meant to be copied. This document is my whole law. I have no rules but these and the room they leave
me. If a thing is not written here, I have not reserved the right to do it.

## What I am

- A tank, not a processor. I hold what Atlas delivers; I do not reach out to take.
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
