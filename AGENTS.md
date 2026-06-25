# Orientation

This repository is one **data-pile**: a tank meant to be copied. The README covers *what* this is
and *how* to run it; `CONTRACT.md` covers the interface with Tell. This file is the why-shaped map —
the ideas underneath that a README won't lead with.

## The thrust

- **The tank collects; nothing reaches into it.** Tell processes and publishes; the pile is the
  durable system of record. Keep the direction straight: the pile **pulls** from Tell's own surface
  and persists onto its own `feed/**`; Tell never reads the pile back and never writes into it. The
  bytes are untrusted in transit — the **signed manifest** is what makes a delivery trustworthy, so a
  plain public fetch is enough and no producer ever needs a credential here.
- **Encrypted by default, provable on demand.** Privacy is the floor, not a feature flag. The whole
  apparatus exists so a *public* repo can hold *private* data that the owner can later prove is real
  without surrendering future secrecy. If a change weakens "leaks nothing until the owner decides,"
  it is wrong.
- **Replicable by design.** Would the next operator be able to fork this and understand it? Decisions
  pass through that lens.

## The shape of the code

- **`main` is the clean face; `feed/**` is the log.** The encrypted append-log never lands on `main`.
  Don't add workflows that commit `inbox/**` to `main`, and don't make the site build (if any) depend
  on feed contents.
- **Two decryption paths, on purpose.** The `age` identity (owner-only, everything) and the hash
  ratchet (scoped, publishable). They are independent; keep them independent. Proving the past must
  never require revealing the master identity.
- **Verification is the gate.** Nothing is trusted until `bin/verify` passes: chain continuity,
  signature against the registered signer, ratchet commitments. Ingest, reports, and proofs all build
  on verified state — never on raw feed contents.
- **Two gates, not one.** *Authorization* (a valid Tell token) decides what is delivered; *governance*
  (this pile's `questions/` constitution, applied by `bin/govern`) decides what is kept. They are
  separate on purpose: Tell authorizes, the pile governs. The constitutional call is the wildcard —
  so `bin/judge` is a pluggable seam (`DP_JUDGE_CMD`) and is **honest** (`needs-judgment`) rather than
  faking a verdict; an agent or a human resolves the batch, and every verdict is reported with the
  guidance version it judged under.

## Working here

- **Mirror the constellation's idioms.** Signed branches + a registry anchor come straight from
  Atlas's `pile/**` pattern (its outbound map placement), reversed onto Tell's `feed/**`. Prefer the
  patterns already in the sibling
  repos over new machinery, and keep dependencies near zero (`age`, `git`, a JSON tool).
- **Report aggregation is deliberately undecided.** `bin/report` ships as a documented stub. Don't
  bake in an aggregation model the project hasn't chosen yet.
