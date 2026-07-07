# Keys held by this pile

| File | Committed? | What |
| --- | --- | --- |
| `pile.age.pub` | yes (public) | This pile's `age` recipient. `setup.yml` generates it; only the encrypt-only public half is committed. The private identity lives solely in the `PILE_AGE_IDENTITY` secret. |
| `tell.signers` | yes (public) | Tell's delivery-signer **public** key, as an SSH allowed-signers line. `bin/verify` checks every pulled delivery against it. **You add this by hand.** |
| `drop.signers` | yes (public) | Accepted senders for the **drop channel** (channel 2, [`docs/transfer.md`](../docs/transfer.md) §B) — SSH allowed-signers lines with principal `drop`. `bin/verify --source drop` checks a drop manifest's head against it under the distinct namespace `data-pile-drop`, so a drop head can never replay as a Tell delivery. **You add each sender by hand** — the same pin-and-confirm-out-of-band handoff as `tell.signers`; a head signed by an unknown key is a *later trust decision*, never trusted by default. |

## Minting without a VPS (the browser alternative)

`setup.yml` runs `age-keygen` on a CI runner and stores the private identity as a repo secret — the
**Computer** posture. The **Mobile** posture needs neither the runner nor the secret: mint the
keypair on the device with
[`anecdote.channel/composer/age-mint.mjs`](https://github.com/FCCN-ANTIBODY/anecdote.channel/blob/main/composer/age-mint.mjs)
(platform WebCrypto; verified byte-interoperable with the real `age` tool), commit **only the
recipient** here as `pile.age.pub` and into `pile.yml` `age_recipient`, and hold the identity where
you are — the trove, gesture-gated. `PILE_AGE_IDENTITY` then never exists as a repo secret at all:
decrypt (`bin/decrypt`) is an owner-side act wherever the identity lives, and a hosted provisioner
(civic-node `OPEN-QUESTIONS.md` §P, rework slice 3) can stand up the whole pile without ever
touching the private half.

## Registering Tell's signer (the entire inbound trust handoff)

There is no GitHub App. Tell signs each digest manifest with an ordinary SSH key;
this pile trusts a delivery only if it verifies against the key you pin here.

1. From the Tell repo, copy `keys/tell.signers` (one line, `tell <type> <base64>`)
   into this directory as `keys/tell.signers`.
2. Copy the fingerprint from Tell's `keys/tell.fpr` into `pile.yml`
   `sources[name=tell].signer`.
3. **Confirm that fingerprint over a second channel** — in person, a signed message,
   a phone call. This is the IRL step that defeats geo/IP spoofing: a local vouches
   for the key a local will trust.

Until `keys/tell.signers` is present, `bin/verify` fails closed (or you must pass
`DP_ALLOW_UNSIGNED=1`, which is only for a constrained dev box — never in production).
