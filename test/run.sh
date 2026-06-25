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
signkey=""; allow_unsigned=""; signers="$work/atlas.signers"
if command -v ssh-keygen >/dev/null 2>&1; then
  ssh-keygen -t ed25519 -N '' -C atlas -f "$work/sign" >/dev/null
  printf 'atlas %s\n' "$(cat "$work/sign.pub")" > "$signers"
  signkey="$work/sign"
else
  echo "NOTE: ssh-keygen absent — signature checks SKIPPED (DP_ALLOW_UNSIGNED=1)"
  allow_unsigned=1
fi
vfy() { DP_ALLOW_UNSIGNED="${allow_unsigned:-0}" bin/verify --dir "$1" --source atlas --signers "$signers"; }

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
  ssh-keygen -t ed25519 -N '' -C atlas -f "$work/evil" >/dev/null
  printf 'atlas %s\n' "$(cat "$work/evil.pub")" > "$signers"
  if bin/verify --dir "$work/pile" --source atlas --signers "$signers" >/dev/null 2>&1; then
    fail "verify accepted a signature from the wrong key"
  fi
  ok "wrong signer rejected"
  printf 'atlas %s\n' "$(cat "$work/sign.pub")" > "$signers"  # restore
fi

echo "[4] owner decrypts all blocks with the identity"
DP_IDENTITY_FILE="$work/id.txt" bin/decrypt --dir "$work/pile" --all --out "$work/plain" >/dev/null \
  || fail "owner decrypt failed"
grep -q "seq 2" "$work/plain/2.txt" || fail "decrypted plaintext wrong"
ok "owner decrypt + ratchet-commitment cross-check"

echo "[5] checkpoint proof: publish K_1, key-less party verifies blocks 1.."
DP_IDENTITY_FILE="$work/id.txt" bin/prove --dir "$work/pile" --from 1 >/dev/null
bundle="$work/pile/reports/proof-atlas-from-1.json"
cp -r "$work/pile" "$work/pub"; rm -f "$work/pub/inbox/seed.age"   # key-less checkout
bin/prove --dir "$work/pub" --check "$bundle" >/dev/null || fail "public proof did not verify"
ok "checkpoint proves blocks 1.. against the signed manifest"

echo "[6] forward-only: checkpoint K_1 must NOT decrypt block 0"
k1="$(jq -r '.checkpoint_key' "$bundle")"
want0="$(jq -r '.entries[0].ratchet_pub' "$work/pub/inbox/manifest.json")"
got0="sha256:$(. bin/lib.sh; dp_ratchet_pub "$k1")"
[ "$want0" != "$got0" ] || fail "checkpoint leaked an earlier block"
ok "earlier blocks stay sealed"

echo "ALL TESTS PASSED"
