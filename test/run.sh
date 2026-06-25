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

# ── governance: the question-constitution decides what is kept ────────────────
echo "[7] bin/govern judges delivered records against questions/<source>/<poll>.json"
gdir="$work/gov"; cdir="$work/content"; mkdir -p "$cdir"
# Seal one tell.digest/v1 block carrying mixed records via the reference producer.
jq -n '{schema:"tell.digest/v1",records:[
  {issue:1,poll:"budget",type:"multichoice",asker:"a",answer:"Cut"},
  {issue:2,poll:"budget",type:"multichoice",asker:"a",answer:"Maybe"},
  {issue:3,poll:"dog-photo",type:"open",asker:"a",answer:"http://x/dog.jpg"},
  {issue:4,poll:"dog-photo",type:"open",asker:"a",answer:""},
  {issue:5,poll:"mystery",type:"open",asker:"a",answer:"hi"} ]}' > "$cdir/0.json"
DP_FIXTURE_CONTENT_DIR="$cdir" test/make-fixtures.sh "$gdir" "$recip" 1 "$signkey" >/dev/null
report="$(PILE_AGE_IDENTITY="$(cat "$work/id.txt")" bin/govern --dir "$gdir" --source tell)"
v() { jq -r --argjson n "$1" '.records[]|select(.issue==$n)|.verdict' "$report"; }
[ "$(v 1)" = accept ] || fail "multichoice option not accepted"
[ "$(v 2)" = reject ] || fail "multichoice write-in (accept_writein:false) not rejected"
[ "$(v 3)" = needs-judgment ] || fail "open answer not flagged needs-judgment"
[ "$(v 4)" = reject ] || fail "empty answer not rejected"
[ "$(v 5)" = held ] || fail "no-constitution poll not held"
[ "$(jq -r '.provenance.manifest_digest' "$report")" = "$(jq -r '.head.digest' "$gdir/inbox/manifest.json")" ] \
  || fail "report provenance does not match the signed feed"
ok "verdicts accept/reject/needs-judgment/held + provenance tied to signed manifest"

echo "[8] live-patch changes the recorded constitution_sha; judge seam is honored"
sha1="$(jq -r '.records[]|select(.issue==3)|.constitution_sha' "$report")"
cp questions/tell/dog-photo.json "$work/dog.bak"
jq '.guidance="patched: studio-lit only"' questions/tell/dog-photo.json > "$work/p.json" && mv "$work/p.json" questions/tell/dog-photo.json
report2="$(PILE_AGE_IDENTITY="$(cat "$work/id.txt")" bin/govern --dir "$gdir" --source tell)"
sha2="$(jq -r '.records[]|select(.issue==3)|.constitution_sha' "$report2")"
cp "$work/dog.bak" questions/tell/dog-photo.json   # restore
[ "$sha1" != "$sha2" ] || fail "constitution_sha did not change after a live patch"
printf '#!/usr/bin/env bash\njq -n %s\n' "'{verdict:\"accept\",reason:\"stub\"}'" > "$work/yes"; chmod +x "$work/yes"
report3="$(DP_JUDGE_CMD="$work/yes" PILE_AGE_IDENTITY="$(cat "$work/id.txt")" bin/govern --dir "$gdir" --source tell)"
[ "$(jq -r '.records[]|select(.issue==3)|.verdict' "$report3")" = accept ] || fail "DP_JUDGE_CMD override not honored"
ok "constitution_sha tracks live patches; DP_JUDGE_CMD plugs in"

# Governance writes to reports/ (publishable) + state/ (gitignored); clean the test ones.
rm -rf reports/govern-*.json state/tell/governed.jsonl

echo "ALL TESTS PASSED"
