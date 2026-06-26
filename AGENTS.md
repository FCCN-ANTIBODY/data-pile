# Orientation

This repository is one **data-pile**: a tank meant to be copied. The README covers *what* this is
and *how* to run it; `CONTRACT.md` covers the interface with Atlas. This file is the why-shaped map —
the ideas underneath that a README won't lead with.

## The thrust

- **A tank holds; it does not reach.** The pile's counterpart is **Tell**, not Atlas. Tells you
  joined (and the direct-QR path) write `feed/**`; the pile verifies, governs, and stores. Keep the
  direction straight: the pile never pulls, and **it never talks to an Atlas** at all — Atlas is a
  separate, out-of-band queue of unmet needs that Tells report to.
- **Encrypted by default, provable on demand.** Privacy is the floor, not a feature flag. The whole
  apparatus exists so a *public* repo can hold *private* data that the owner can later prove is real
  without surrendering future secrecy. If a change weakens "leaks nothing until the owner decides,"
  it is wrong.
- **Replicable by design.** Would the next operator be able to fork this and understand it? Decisions
  pass through that lens.
- **Owned, not gloved.** A data-pile is *yours* — you fork it, scope it, own its contents, and it
  runs its own actions on its own budget. It is **not** a constellation "glove" (the submodule
  engines like Tell/Atlas/Journal that a workspace grafts in for turnkey behavior). If another repo
  submodules a data-pile, that is a **watched bookmark**, not a way to run it — the pile depends on
  no engine to function.

## The shape of the code

- **`main` is the clean face; `feed/**` is the log.** The encrypted append-log never lands on `main`.
  Don't add workflows that commit `inbox/**` to `main`, and don't make the site build (if any) depend
  on feed contents.
- **Two decryption paths, on purpose.** The `age` identity (owner-only, everything) and the hash
  ratchet (scoped, publishable). They are independent; keep them independent. Proving the past must
  never require revealing the master identity.
- **Two gates, in order.** Crypto first: nothing is trusted until `bin/verify` passes (chain,
  per-block hashes, and — for signed Tells — the signature against the registered signer). Then the
  **governor**: `bin/accept` keeps only responses a question's `guidance.json` permits, recording
  verdicts (no plaintext) to a ledger. Reports build on the *accepted* set, never raw feed contents.
- **questions/ are law for incoming data, and the owner owns them.** Guidance edits are git-logged
  and re-filter on the next run. Never let a CONSTITUTION or guidance harvest without a question +
  consent, and never write plaintext or the encrypted log onto `main`.

## Working here

- **Mirror the constellation's idioms.** Signed branches + a registry anchor come straight from
  Atlas's `pile/**` pattern, reversed onto `feed/**`. Prefer the patterns already in the sibling
  repos over new machinery, and keep dependencies near zero (`age`, `git`, a JSON tool).
- **Report aggregation is deliberately undecided.** `bin/report` ships as a documented stub. Don't
  bake in an aggregation model the project hasn't chosen yet.
