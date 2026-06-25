# Keys held by this pile

| File | Committed? | What |
| --- | --- | --- |
| `pile.age.pub` | yes (public) | This pile's `age` recipient. `setup.yml` generates it; only the encrypt-only public half is committed. The private identity lives solely in the `PILE_AGE_IDENTITY` secret. |
| `tell.signers` | yes (public) | Tell's delivery-signer **public** key, as an SSH allowed-signers line. `bin/verify` checks every pulled delivery against it. **You add this by hand.** |

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
