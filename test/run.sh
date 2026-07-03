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
[ "$(cat "$pn/keys/pile.age.pub")" = "$RECIP" ] || fail "keys/pile.age.pub is not the supplied recipient"
# Idempotent: a second fill does not double-stamp.
bin/pile-new fill --dir "$pn" --id cd04-q1 --scope colorado --recipient "$RECIP" --provisioner "acme/host" 2>/dev/null
[ "$(grep -c '^provisioner:' "$pn/pile.yml")" = 1 ] || fail "attestation double-stamped on re-fill"
# Computer fill: keygen mints locally, recipient lands, identity never in the checkout.
pk="$work/pilenew-kg"; mkdir -p "$pk"; cp pile.yml "$pk/"
bin/pile-new fill --dir "$pk" --id fc-q2 --scope colorado --keygen 2>/dev/null
grep -q '^age_recipient: "age1' "$pk/pile.yml" || fail "keygen fill did not set a recipient"
grep -rq 'AGE-SECRET-KEY' "$pk" && fail "keygen fill leaked an identity into the checkout" || true
# Custody refusals: no posture; both postures; provisioner+keygen (the rule); bad recipient; bad id.
bin/pile-new plan --id a --scope s 2>/dev/null && fail "accepted no identity posture" || true
bin/pile-new plan --id a --scope s --keygen --recipient "$RECIP" 2>/dev/null && fail "accepted both postures" || true
bin/pile-new plan --id a --scope s --keygen --provisioner x/y 2>/dev/null && fail "a provisioner was allowed to keygen" || true
bin/pile-new plan --id a --scope s --recipient age1nope 2>/dev/null && fail "accepted a malformed recipient" || true
bin/pile-new plan --id UPPER --scope s --recipient "$RECIP" 2>/dev/null && fail "accepted a non-slug id" || true
# The plan narrates the posture (the operator sees the custody before anything happens).
bin/pile-new plan --id a --scope s --recipient "$RECIP" 2>/dev/null | grep -q "no identity exists host-side" \
  || fail "plan did not narrate the Mobile custody"
ok "pile-new: fill fills, attestation stamps once, provisioner-never-keygens enforced, malformed refused"

echo "ALL TESTS PASSED"

echo "[10] custody: the declared boundary holds (keys/custody.yml x bin/check-custody)"
bin/check-custody >/dev/null 2>&1 || fail "check-custody failed on the repo as-is"
mkdir -p "$work/badwf"; printf 'env:\n  X: ${{ secrets.SNEAKY }}\n' > "$work/badwf/x.yml"
WORKFLOWS_DIR="$work/badwf" bin/check-custody >/dev/null 2>&1 && fail "checker passed an undeclared secret-read" || true
ok "workflows read only declared secrets; an undeclared read fails the build"
