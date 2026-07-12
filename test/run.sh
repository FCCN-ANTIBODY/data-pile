#!/usr/bin/env bash
# End-to-end test of the data-pile crypto + verification core. Runs fully offline.
# Signature checks run when ssh-keygen is present; otherwise they are SKIPPED (and
# verify is invoked with DP_ALLOW_UNSIGNED=1) so the rest still exercises.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

# identity + recipient
age-keygen -o "$work/id.txt" 2>/dev/null
recip="$(age-keygen -y "$work/id.txt")"

# signing key + signers file (if ssh-keygen available). Kept under $work — never touches tracked keys/.
signkey=""; allow_unsigned=""; signers="$work/tell.signers"
if command -v ssh-keygen >/dev/null 2>&1; then
  ssh-keygen -t ed25519 -N '' -C tell -f "$work/sign" >/dev/null
  printf 'tell %s\n' "$(cat "$work/sign.pub")" > "$signers"
  signkey="$work/sign"
else
  echo "NOTE: ssh-keygen absent — signature checks SKIPPED (DP_ALLOW_UNSIGNED=1)"
  allow_unsigned=1
fi
vfy() { DP_ALLOW_UNSIGNED="${allow_unsigned:-0}" bin/verify --dir "$1" --source tell --signers "$signers"; }

echo "[1] build a 3-block chain"
test/make-fixtures.sh "$work/pile" "$recip" 3 "$signkey" >/dev/null
ok "chain built"

echo "[2] verify passes on a good chain"
vfy "$work/pile" >"$work/v.out" 2>&1 || { cat "$work/v.out"; fail "verify rejected a valid chain"; }
ok "valid chain verifies"

echo "[3] verify fails on a tampered block"
printf 'x' >> "$work/pile/inbox/000001.enc"
if vfy "$work/pile" >/dev/null 2>&1; then fail "verify accepted a tampered block"; fi
ok "tamper detected"
test/make-fixtures.sh "$work/pile" "$recip" 3 "$signkey" >/dev/null  # rebuild clean

if [ -n "$signkey" ]; then
  echo "[3b] verify fails when signed by the wrong key"
  ssh-keygen -t ed25519 -N '' -C tell -f "$work/evil" >/dev/null
  printf 'tell %s\n' "$(cat "$work/evil.pub")" > "$signers"
  if bin/verify --dir "$work/pile" --source tell --signers "$signers" >/dev/null 2>&1; then
    fail "verify accepted a signature from the wrong key"
  fi
  ok "wrong signer rejected"
  printf 'tell %s\n' "$(cat "$work/sign.pub")" > "$signers"  # restore
fi

echo "[4] owner decrypts all blocks with the identity"
DP_IDENTITY_FILE="$work/id.txt" bin/decrypt --dir "$work/pile" --all --out "$work/plain" >/dev/null \
  || fail "owner decrypt failed"
grep -q "seq 2" "$work/plain/2.txt" || fail "decrypted plaintext wrong"
ok "owner decrypt + ratchet-commitment cross-check"

echo "[5] checkpoint proof: publish K_1, key-less party verifies blocks 1.."
DP_IDENTITY_FILE="$work/id.txt" bin/prove --dir "$work/pile" --from 1 >/dev/null
bundle="$work/pile/reports/proof-tell-from-1.json"
cp -r "$work/pile" "$work/pub"; rm -f "$work/pub/inbox/seed.age"   # key-less checkout
bin/prove --dir "$work/pub" --check "$bundle" >/dev/null || fail "public proof did not verify"
ok "checkpoint proves blocks 1.. against the signed manifest"

if command -v node >/dev/null 2>&1; then
  # the on-device port (bin/prove.mjs) must agree with the bash bin, both directions
  node bin/prove.mjs --dir "$work/pub" --check "$bundle" >/dev/null || fail "prove.mjs --check did not verify the bash bundle"
  bash_ckey="$(jq -r .checkpoint_key "$bundle")"
  DP_IDENTITY_FILE="$work/id.txt" node bin/prove.mjs --dir "$work/pile" --from 1 >/dev/null || fail "prove.mjs --from failed (age-open)"
  [ "$(jq -r .checkpoint_key "$bundle")" = "$bash_ckey" ] || fail "prove.mjs checkpoint_key differs from bash"
  bin/prove --dir "$work/pub" --check "$bundle" >/dev/null || fail "bash --check did not verify the prove.mjs bundle"
  ok "prove.mjs port agrees with bin/prove (checkpoint bundle, both directions)"
fi

echo "[6] forward-only: checkpoint K_1 must NOT decrypt block 0"
k1="$(jq -r '.checkpoint_key' "$bundle")"
want0="$(jq -r '.entries[0].ratchet_pub' "$work/pub/inbox/manifest.json")"
got0="sha256:$(. bin/lib.sh; dp_ratchet_pub "$k1")"
[ "$want0" != "$got0" ] || fail "checkpoint leaked an earlier block"
ok "earlier blocks stay sealed"

# ── governance moved to Tell ──────────────────────────────────────────────────
# The judge round no longer lives here. Tell applies each pile's delegated constitution
# BEFORE sealing (it reads the public Issue plaintext, no key needed) and ships every
# record already carrying its `governed` verdict. The owner reads those verdicts after
# decrypt and may re-judge by hand at this boundary. See CONSTITUTION.md / CONTRACT.md.

# ── request-for-pile: post a need, pull a match ───────────────────────────────
echo "[7] bin/need emits a valid Atlas registration entry"
nid="$(ls needs/*.json | head -1 | sed 's#needs/##;s#\.json##')"
REPO=acme/civic-node bin/need "$nid" | python3 -c "import sys,yaml; e=yaml.safe_load(sys.stdin)[0]; assert e['id'] and e['asker_repo']=='acme/civic-node', e" \
  || fail "bin/need entry not valid"
ok "need emits registration entry"

echo "[8] bin/need-matches surfaces only this repo's matches, with consent flag"
jq -n --arg n "$nid" '[{need_id:$n,asker_repo:"acme/civic-node",candidate:{atlas_url:"a",tell_url:"t",pile_id:"OURMATCH"},verdict:"accept",reason:"fits",consent_required:true},
                       {need_id:"x",asker_repo:"other/repo",candidate:{atlas_url:"a",tell_url:"t",pile_id:"THEIRMATCH"},verdict:"accept",reason:"fits",consent_required:false}]' > "$work/matches.json"
out="$(REPO=acme/civic-node ATLAS_MATCHES_URL="file://$work/matches.json" bin/need-matches)"
printf '%s' "$out" | grep -q "OURMATCH" || fail "did not surface our match"
printf '%s' "$out" | grep -q "re-issue a QR" || fail "missing consent-invite wording"
printf '%s' "$out" | grep -q "THEIRMATCH" && fail "leaked another repo's match" || true
ok "pull shows our match (consent invite); others' hidden"

echo "[9] bin/pile-new: the pure half (plan/fill) — postures, attestation, custody refusals"
RECIP="age1586sf5fgqv0cxt2xgyyl4p2s6f7x4eaneg28rhkpaj4sm8e5x92qtqwy8l"
pn="$work/pilenew"; mkdir -p "$pn"; cp pile.yml "$pn/"
# Mobile fill: only the recipient crosses; pile.yml + keys/pile.age.pub land; attestation stamped.
bin/pile-new fill --dir "$pn" --id cd04-q1 --scope colorado --recipient "$RECIP" \
  --owner acme --name tank --provisioner "acme/host" \
  --source-url "https://tell.anecdote.channel/piles/cd04-q1/feed/" 2>/dev/null
grep -q '^id: "cd04-q1"' "$pn/pile.yml" || fail "pile-new fill did not set id"
grep -q '^age_recipient: "age1586' "$pn/pile.yml" || fail "pile-new fill did not set the recipient"
grep -q '^repo_url: "https://github.com/acme/tank"' "$pn/pile.yml" || fail "pile-new fill did not set repo_url"
grep -q '^    url: "https://tell' "$pn/pile.yml" || fail "pile-new fill did not set sources[0].url"
grep -q '^provisioner: "acme/host"' "$pn/pile.yml" || fail "pile-new fill did not stamp the attestation"
grep -q '^provisioner_spec: "data-pile/pile-new/v1"' "$pn/pile.yml" || fail "pile-new fill did not stamp WHAT the manager speaks (spec-or-attested)"
[ "$(cat "$pn/keys/pile.age.pub")" = "$RECIP" ] || fail "keys/pile.age.pub is not the supplied recipient"
# Idempotent: a second fill does not double-stamp.
bin/pile-new fill --dir "$pn" --id cd04-q1 --scope colorado --recipient "$RECIP" --provisioner "acme/host" 2>/dev/null
[ "$(grep -c '^provisioner:' "$pn/pile.yml")" = 1 ] || fail "attestation double-stamped on re-fill"
[ "$(grep -c '^provisioner_spec:' "$pn/pile.yml")" = 1 ] || fail "spec attestation double-stamped on re-fill"
# Computer fill: keygen mints locally, recipient lands, identity never in the checkout.
pk="$work/pilenew-kg"; mkdir -p "$pk"; cp pile.yml "$pk/"
bin/pile-new fill --dir "$pk" --id fc-q2 --scope colorado --keygen 2>/dev/null
grep -q '^age_recipient: "age1' "$pk/pile.yml" || fail "keygen fill did not set a recipient"
grep -rq 'AGE-SECRET-KEY' "$pk" && fail "keygen fill leaked an identity into the checkout" || true

if command -v node >/dev/null 2>&1; then
  # the on-device port (bin/pile-new.mjs) must fill byte-identically to bash for a fixed recipient,
  # and its --keygen must mint on-device (age battery) without leaking the identity into the checkout.
  pnm="$work/pilenew-mjs"; mkdir -p "$pnm"; cp pile.yml "$pnm/"
  node bin/pile-new.mjs fill --dir "$pnm" --id cd04-q1 --scope colorado --recipient "$RECIP" \
    --owner acme --name tank --provisioner "acme/host" \
    --source-url "https://tell.anecdote.channel/piles/cd04-q1/feed/" 2>/dev/null
  # fresh bash fill into its own dir for an apples-to-apples byte compare (the $pn above was re-filled)
  pnb="$work/pilenew-bash"; mkdir -p "$pnb"; cp pile.yml "$pnb/"
  bin/pile-new fill --dir "$pnb" --id cd04-q1 --scope colorado --recipient "$RECIP" \
    --owner acme --name tank --provisioner "acme/host" \
    --source-url "https://tell.anecdote.channel/piles/cd04-q1/feed/" 2>/dev/null
  diff "$pnb/pile.yml" "$pnm/pile.yml" >/dev/null || fail "pile-new.mjs fill differs from bash pile.yml"
  diff "$pnb/keys/pile.age.pub" "$pnm/keys/pile.age.pub" >/dev/null || fail "pile-new.mjs keys differ from bash"
  pkm="$work/pilenew-mjs-kg"; mkdir -p "$pkm"; cp pile.yml "$pkm/"
  node bin/pile-new.mjs fill --dir "$pkm" --id fc-q2 --scope colorado --keygen 2>/dev/null
  grep -q '^age_recipient: "age1' "$pkm/pile.yml" || fail "pile-new.mjs --keygen did not set a recipient"
  grep -rq 'AGE-SECRET-KEY' "$pkm" && fail "pile-new.mjs --keygen leaked an identity into the checkout" || true
  ok "pile-new.mjs port fills byte-identically to bash + mints identity on-device (age battery), no leak"
fi
# Custody refusals: no posture; both postures; provisioner+keygen (the rule); bad recipient; bad id.
bin/pile-new plan --id a --scope s 2>/dev/null && fail "accepted no identity posture" || true
bin/pile-new plan --id a --scope s --keygen --recipient "$RECIP" 2>/dev/null && fail "accepted both postures" || true
bin/pile-new plan --id a --scope s --keygen --provisioner x/y 2>/dev/null && fail "a provisioner was allowed to keygen" || true
bin/pile-new plan --id a --scope s --recipient age1nope 2>/dev/null && fail "accepted a malformed recipient" || true
bin/pile-new plan --id UPPER --scope s --recipient "$RECIP" 2>/dev/null && fail "accepted a non-slug id" || true
bin/pile-new plan --id "$(printf 'x%.0s' $(seq 64))" --scope s --recipient "$RECIP" 2>/dev/null \
  && fail "accepted an id too long for a DNS label (the Floor alias rule)" || true
# The plan narrates the posture (the operator sees the custody before anything happens).
bin/pile-new plan --id a --scope s --recipient "$RECIP" 2>/dev/null | grep -q "no identity exists host-side" \
  || fail "plan did not narrate the Mobile custody"
ok "pile-new: fill fills, attestation stamps once, provisioner-never-keygens enforced, malformed refused"

echo "[9b] bin/pile-poll: reserve a poll on the stood-up pile — SHOWN anchor, qr slot reserved (JS leads)"
pp="$work/pilepoll"; mkdir -p "$pp"; cp pile.yml "$pp/"
bin/pile-new fill --dir "$pp" --id cd04-q1 --scope colorado --recipient "$RECIP" 2>/dev/null
if command -v node >/dev/null 2>&1; then
  # The offline origin is the LEAD: pile-poll.mjs writes the anchor on-device (pure fs, no jq/shell).
  node bin/pile-poll.mjs --dir "$pp" --poll budget --question "Cut or keep the library budget?" --opts "Cut, Keep" 2>/dev/null
  a="$pp/polls/budget.json"
  [ -f "$a" ] || fail "pile-poll.mjs did not write the pile-side poll anchor"
  [ "$(jq -r '.schema' "$a")" = "data-pile.poll-anchor/v1" ] || fail "anchor schema wrong"
  [ "$(jq -r '.shown' "$a")" = true ] || fail "anchor is not marked as the SHOWN copy"
  [ "$(jq -r '.qr' "$a")" = null ] || fail "the QR slot is not reserved (should be null until signing)"
  [ "$(jq -r '.options|length' "$a")" = 2 ] || fail "anchor dropped the prefab answers"
  [ "$(jq -r '.governed_by' "$a")" = "tell:_data/constitutions/cd04-q1/budget.json" ] || fail "anchor does not point at the Tell-side governing constitution"
  # The bash mirror must agree BYTE-FOR-BYTE (the pile-new.mjs<->bash discipline).
  node bin/pile-poll.mjs --dir "$pp" --poll budget --question "Cut or keep the library budget?" --opts "Cut, Keep" --out - 2>/dev/null > "$work/pp.js"
  bin/pile-poll        --dir "$pp" --poll budget --question "Cut or keep the library budget?" --opts "Cut, Keep" --out - 2>/dev/null > "$work/pp.sh"
  diff "$work/pp.js" "$work/pp.sh" >/dev/null || fail "pile-poll bash mirror differs from the pile-poll.mjs lead"
  # THE INVARIANT (shared with tell bin/poll): a poll solicits; a multichoice with no prefab answer is refused.
  node bin/pile-poll.mjs --dir "$pp" --poll void --question q --type multichoice --out - >/dev/null 2>&1 && fail "pile-poll.mjs authored a multichoice poll with no prefab answer" || true
  node bin/pile-poll.mjs --dir "$pp" --poll bad  --question q --type open --opts "A,B" --out - >/dev/null 2>&1 && fail "pile-poll.mjs authored an open poll with prefab options" || true
  # Custody-of-shape: refuses a dir with no stood-up pile.
  node bin/pile-poll.mjs --dir "$work/nopile" --poll x --question q --opts A --out - >/dev/null 2>&1 && fail "pile-poll.mjs attached to a non-pile dir" || true
  ok "pile-poll.mjs reserves the SHOWN anchor (qr slot null, governed_by -> Tell); bash mirror byte-identical; invariant enforced"
else
  bin/pile-poll --dir "$pp" --poll budget --question "Cut or keep the library budget?" --opts "Cut, Keep" 2>/dev/null
  [ "$(jq -r '.qr' "$pp/polls/budget.json")" = null ] || fail "the QR slot is not reserved"
  ok "pile-poll (bash) reserves the SHOWN anchor (node absent — JS lead not cross-checked here)"
fi

# ── the drop channel (channel 2, docs/transfer.md §B) ─────────────────────────
dropkey=""; dsigners="$work/drop.signers"
if [ -n "$signkey" ]; then
  ssh-keygen -t ed25519 -N '' -C drop -f "$work/dropsign" >/dev/null
  printf 'drop %s\n' "$(cat "$work/dropsign.pub")" > "$dsigners"
  dropkey="$work/dropsign"
fi
dvfy() { DP_ALLOW_UNSIGNED="${allow_unsigned:-0}" bin/verify --dir "$1" --source drop --signers "$dsigners"; }

echo "[10] drop-pack: arbitrary artifacts ride as opaque blocks, chain verifies"
printf '{"schema":"anecdote.ballot/v1","pile":"cd04-q1","poll":"budget","answer":"Keep","ts":"2026-07-04T18:00:00Z","sig":{"alg":"ed25519"}}\n' > "$work/a.json"
head -c 1024 /dev/urandom > "$work/b.bin"   # payload-agnostic: a raw binary blob
bin/drop-pack --dir "$work/dpile" --recipient "$recip" ${dropkey:+--sign "$dropkey"} "$work/a.json" "$work/b.bin" >/dev/null
dvfy "$work/dpile" >"$work/dv.out" 2>&1 || { cat "$work/dv.out"; fail "verify rejected a valid drop chain"; }
[ -f "$work/dpile/inbox/000000.kage" ] && [ -f "$work/dpile/inbox/000001.kage" ] || fail "per-block kage files missing"
[ -f "$work/dpile/inbox/seed.age" ] && fail "a drop feed grew a seed" || true
ok "two artifacts packed; per-block keys wrapped; chain verifies as source 'drop'"

echo "[11] drop append chains onto the existing head"
printf 'later artifact\n' > "$work/c.txt"
bin/drop-pack --dir "$work/dpile" --recipient "$recip" ${dropkey:+--sign "$dropkey"} "$work/c.txt" >/dev/null
[ "$(jq '.entries|length' "$work/dpile/inbox/manifest.json")" = 3 ] || fail "append did not extend the chain"
[ "$(jq -r '.entries[2].prev_hash' "$work/dpile/inbox/manifest.json")" = "$(jq -r '.entries[1].this_hash' "$work/dpile/inbox/manifest.json")" ] \
  || fail "appended entry does not chain"
dvfy "$work/dpile" >/dev/null 2>&1 || fail "verify rejected the extended drop chain"
ok "append preserves prev_hash continuity; chain still verifies"

echo "[12] owner decrypts drop blocks byte-for-byte (no seed involved)"
DP_IDENTITY_FILE="$work/id.txt" bin/decrypt --dir "$work/dpile" --all --out "$work/dplain" >/dev/null \
  || fail "owner decrypt of drop feed failed"
cmp -s "$work/a.json" "$work/dplain/0.txt" || fail "artifact 0 did not round-trip"
cmp -s "$work/b.bin" "$work/dplain/1.txt" || fail "binary artifact did not round-trip"
cmp -s "$work/c.txt" "$work/dplain/2.txt" || fail "appended artifact did not round-trip"
ok "opaque payloads round-trip exactly; per-block commitment cross-checked"

echo "[13] tampered block and tampered key both fail closed"
printf 'x' >> "$work/dpile/inbox/000001.enc"
dvfy "$work/dpile" >/dev/null 2>&1 && fail "verify accepted a tampered drop block" || true
rm -rf "$work/dpile"; bin/drop-pack --dir "$work/dpile" --recipient "$recip" ${dropkey:+--sign "$dropkey"} "$work/a.json" "$work/b.bin" >/dev/null
mv "$work/dpile/inbox/000001.kage" "$work/dpile/inbox/000001.kage.bak"
printf '%s' "wrong" | age -r "$recip" -o "$work/dpile/inbox/000001.kage"
DP_IDENTITY_FILE="$work/id.txt" bin/decrypt --dir "$work/dpile" --seq 1 >/dev/null 2>&1 \
  && fail "decrypt accepted a key that fails its commitment" || true
mv "$work/dpile/inbox/000001.kage.bak" "$work/dpile/inbox/000001.kage"
ok "tampered ciphertext rejected at verify; substituted key rejected at the commitment"

if [ -n "$dropkey" ]; then
  echo "[13b] namespace separation: a drop head never replays as a Tell delivery"
  # Same key, principal renamed to 'tell' — ONLY the namespace differs, and that must be enough.
  printf 'tell %s\n' "$(cat "$work/dropsign.pub")" > "$work/cross.signers"
  bin/verify --dir "$work/dpile" --source tell --signers "$work/cross.signers" >/dev/null 2>&1 \
    && fail "a data-pile-drop signature verified under the data-pile namespace" || true
  ok "cross-channel replay refused (data-pile vs data-pile-drop)"
fi

echo "[14] drop disclosure: reveal per-block keys, key-less party verifies; unnamed blocks stay sealed"
DP_IDENTITY_FILE="$work/id.txt" bin/prove --dir "$work/dpile" --source drop --from 1 >/dev/null
dbundle="$work/dpile/reports/proof-drop-from-1.json"
jq -e '.block_keys | has("1")' "$dbundle" >/dev/null || fail "drop proof bundle carries no block_keys"
jq -e '.block_keys | has("0") | not' "$dbundle" >/dev/null || fail "drop proof leaked an earlier block's key"
cp -r "$work/dpile" "$work/dpub"; rm -f "$work/dpub/inbox/"*.kage   # key-less checkout
bin/prove --dir "$work/dpub" --check "$dbundle" >/dev/null || fail "public drop proof did not verify"
ok "block_keys bundle proves named blocks only; each key opens only its own block"

if command -v node >/dev/null 2>&1; then
  # the on-device port must agree on the drop (block_keys) bundle too, both directions
  node bin/prove.mjs --dir "$work/dpub" --check "$dbundle" >/dev/null || fail "prove.mjs drop --check did not verify the bash bundle"
  DP_IDENTITY_FILE="$work/id.txt" node bin/prove.mjs --dir "$work/dpile" --source drop --from 1 >/dev/null || fail "prove.mjs drop --from failed (age-open per-block keys)"
  bin/prove --dir "$work/dpub" --check "$dbundle" >/dev/null || fail "bash --check did not verify the prove.mjs drop bundle"
  ok "prove.mjs drop port agrees with bin/prove (block_keys, both directions)"
fi

echo "ALL TESTS PASSED"

echo "[15] custody: the declared boundary holds (keys/custody.yml x bin/check-custody)"
bin/check-custody >/dev/null 2>&1 || fail "check-custody failed on the repo as-is"
mkdir -p "$work/badwf"; printf 'env:\n  X: ${{ secrets.SNEAKY }}\n' > "$work/badwf/x.yml"
WORKFLOWS_DIR="$work/badwf" bin/check-custody >/dev/null 2>&1 && fail "checker passed an undeclared secret-read" || true
ok "workflows read only declared secrets; an undeclared read fails the build"
