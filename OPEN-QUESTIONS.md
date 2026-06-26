# Open questions (data-pile)

Deliberately-deferred design problems on the pile side. Set aside, not forgotten. Each
notes what it **blocks**. The QR/identity/expiry questions live on the producer; see
`tell.anecdote.channel/OPEN-QUESTIONS.md`.

## 1. Tell-less out-of-band contribution (a second, non-ratcheted ingest)

`keys/pile.age.pub` is public and encrypt-only, so anyone *could* `age`-encrypt a payload to
this pile without any Tell in the loop. What is missing is a path to **ingest** such a drop:
the live feed is a one-way ratchet whose seed only Tell holds, so an out-of-band contribution
cannot extend that chain.

- **Blocks:** accepting data when no Tell fronts the pile; archival imports; a contributor
  handing the owner sealed data directly.
- **Sketch (unbuilt):** a separate `feed/drop` channel — `age`-to-recipient blocks under their
  own signed, hash-linked manifest (no ratchet, since there is no shared seed), verified by a
  `bin/verify` variant. Storage *and* encryption solved out of band, **not** by borrowing
  Tell's key. See `CONTRACT.md` → "What the pile is — and is not."

## 2. Re-judging at the boundary — how mechanical?

Judging now happens on Tell before sealing; every record arrives carrying its `governed`
verdict and `constitution_sha`. The pile owner may **re-judge by hand** after `bin/decrypt`,
but there is no tool here for it (the old `bin/govern`/`bin/judge` round was removed with the
judging responsibility).

- **Blocks:** a pile owner who wants to systematically override Tell's verdicts (vs. eyeballing
  decrypted records).
- **Open:** whether the pile needs a thin local re-judge helper at all, or whether reading the
  delivered verdicts is enough. Left minimal on purpose — the constitution lives on Tell now.

## 3. Registration idiom unification (`bin/register`)

`handshake.yml` (PR → Tell's `_data/piles.yml`) and `bin/need` + `need.yml` (PR → Atlas's
`_data/needs.yml`) are the same PR-append shape twice. A single `bin/register` parameterized by
target registry would unify them. Functional today; idiom debt only. Deferred because it
refactors working PR-opening code that needs `gh` + live repos to exercise safely. Tracked also
in `tell.anecdote.channel/OPEN-QUESTIONS.md`.
