# Keys held by this pile

| File | Committed? | What |
| --- | --- | --- |
| `pile.age.pub` | yes (public) | This pile's `age` recipient. `setup.yml` generates it; only the encrypt-only public half is committed. The private identity lives solely in the `PILE_AGE_IDENTITY` secret. |
| `atlas.signers` | yes (public) | Atlas's delivery-signer **public** key, as an SSH allowed-signers line. `bin/verify` checks every pulled delivery against it. **You add this by hand.** |

## Registering Atlas's signer (the entire inbound trust handoff)

There is no GitHub App. Atlas signs each digest manifest with an ordinary SSH key;
this pile trusts a delivery only if it verifies against the key you pin here.

1. From the Atlas repo, copy `keys/atlas.signers` (one line, `atlas <type> <base64>`)
   into this directory as `keys/atlas.signers`.
2. Copy the fingerprint from Atlas's `keys/atlas.fpr` into `pile.yml`
   `sources[name=atlas].signer`.
3. **Confirm that fingerprint over a second channel** — in person, a signed message,
   a phone call. This is the IRL step that defeats geo/IP spoofing: a local vouches
   for the key a local will trust.

Until `keys/atlas.signers` is present, `bin/verify` fails closed (or you must pass
`DP_ALLOW_UNSIGNED=1`, which is only for a constrained dev box — never in production).
