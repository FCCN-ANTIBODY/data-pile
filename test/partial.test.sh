#!/usr/bin/env bash
# Partial verification — the KEY-LESS public path (bin/verify --partial, verifyFeed partial:true).
# Deliberately needs only openssl + jq + sha256sum: a reader who holds a disclosed excerpt has no
# identity, no age, and no secret of any kind, so the test that covers them must not need one
# either. This is the one suite that runs on a box without `age`.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
. bin/lib.sh
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
inbox="$work/inbox"; mkdir -p "$inbox"

# bin/verify checks that a delivery INCLUDED each wrapped key, not what is inside it (only the
# owner's identity can open one). So a placeholder .kage is a faithful stand-in here, and lets the
# whole suite run without `age`.
echo "[1] build a 6-block drop chain (placeholder .kage: verify checks presence, not content)"
entries="[]"; prev="null"
for i in 0 1 2 3 4 5; do
  p="$(printf '%06d' "$i")"; k="$(openssl rand -hex 32)"
  printf 'block %s payload\n' "$i" > "$work/plain"
  dp_enc "$k" "$work/plain" "$inbox/$p.enc"
  printf 'age-wrapped-key-placeholder\n' > "$inbox/$p.kage"
  entries="$(printf '%s' "$entries" | jq --argjson s "$i" --arg b "$p.enc" --arg kf "$p.kage" \
    --arg th "sha256:$(dp_sha256_file "$inbox/$p.enc")" --argjson ph "$prev" \
    --arg rp "sha256:$(dp_ratchet_pub "$k")" \
    '. + [{seq:$s, source:"drop", block:$b, key:$kf, this_hash:$th, prev_hash:$ph, ratchet_pub:$rp}]')"
  prev="\"sha256:$(dp_sha256_file "$inbox/$p.enc")\""
done
digest="$(printf '%s' "$entries" | jq -cS '.' | tr -d '\n' | sha256sum | cut -d' ' -f1)"
jq -n --argjson e "$entries" --arg dg "$digest" \
  '{version:1, source:"drop", entries:$e, head:{seq:5, digest:$dg, sig:null}}' > "$inbox/manifest.json"
ok "6 blocks sealed"

vfy() { DP_ALLOW_UNSIGNED=1 bin/verify --dir "$work" --source drop "$@"; }

echo "[2] full verify passes while every block is held"
[ "$(vfy 2>/dev/null)" = "verified" ] || fail "full verify rejected a complete chain"
ok "complete chain verifies"

echo "[3] --partial on a complete holding still reports the FULL result"
[ "$(vfy --partial 2>/dev/null)" = "verified" ] || fail "--partial understated a complete holding"
ok "partial mode does not understate"

echo "[4] drop all but seq 0 and 3-4 — the disclosed-excerpt shape"
# A real partial holder has neither the ciphertext nor the wrapped key for what it did not fetch.
for g in 000001 000002 000005; do rm -f "$inbox/$g.enc" "$inbox/$g.kage"; done

echo "[5] verify WITHOUT --partial refuses, and says how to proceed"
# NB: capture, then grep. Under `set -o pipefail` a pipeline from the (intentionally) failing
# verify reports ITS exit status, which would mask the grep result.
if vfy >/dev/null 2>&1; then fail "verify accepted a hole without --partial"; fi
refusal="$(vfy 2>&1 || true)"
case "$refusal" in *--partial*) ;; *) fail "refusal did not name the remedy: $refusal";; esac
ok "absent block still fatal by default"

echo "[6] --partial verifies the smaller claim and names what it did not check"
out="$(vfy --partial 2>"$work/log")" || fail "partial verify rejected a valid partial holding"
[ "$out" = "verified-partial 3/6" ] || fail "wrong sentinel: '$out'"
grep -q "NOT held: seq 1-2,5" "$work/log" || { cat "$work/log"; fail "unchecked seqs not reported"; }
ok "reports 'verified-partial 3/6' and NOT held: seq 1-2,5"

echo "[7] a partial run can never be mistaken for a full one"
[ "$out" != "verified" ] || fail "partial printed the full sentinel"
ok "sentinels are distinct"

echo "[8] tampering with a block you DO hold is still caught under --partial"
printf 'x' >> "$inbox/000003.enc"
if vfy --partial >/dev/null 2>&1; then fail "partial accepted a tampered held block"; fi
ok "tamper in a held block detected"

echo "[9] a broken chain is caught with NO blocks held at all"
rm -f "$inbox"/*.enc "$inbox"/*.kage
vfy --partial >/dev/null 2>&1 || fail "zero-held verify should still pass on a sound chain"
# Break the chain AND recompute head.digest to match — otherwise the digest check fires first
# and this never reaches the linkage check, passing without proving anything.
jq '.entries[3].prev_hash = "sha256:deadbeef"' "$inbox/manifest.json" > "$work/m"
nd="$(jq -cS '.entries' "$work/m" | tr -d '\n' | sha256sum | cut -d' ' -f1)"
jq --arg d "$nd" '.head.digest = $d' "$work/m" > "$inbox/manifest.json"
DP_ALLOW_UNSIGNED=1 bin/verify --dir "$work" --source drop --partial 2>"$work/log" && fail "partial accepted a broken chain"
grep -q "broken chain" "$work/log" || { cat "$work/log"; fail "rejected for the wrong reason"; }
ok "linkage enforced with zero bytes held, digest recomputed"

echo "PASS: partial verification"
