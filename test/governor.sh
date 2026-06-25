#!/usr/bin/env bash
# Tests the acceptance governor: per-response verdicts, re-filter on guidance edit, the
# ingest pipeline + ledger (no plaintext), direct (unsigned) ingress, and cross-Tell dedup.
# Runs fully offline; signature checks are bypassed here (covered by test/run.sh).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
. bin/lib.sh
work="$(mktemp -d)"
cleanup() { rm -rf "$work" state/atlas state/direct;
  git worktree remove --force "$work/wt" 2>/dev/null || true
  git branch -D feed/atlas feed/direct >/dev/null 2>&1 || true; }
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "  ok: $*"; }

age-keygen -o "$work/id.txt" 2>/dev/null
recip="$(age-keygen -y "$work/id.txt")"

# ---- bin/accept: verdict logic against a temp guidance (v1) ----
gv1="$work/guidance.json"
cat > "$gv1" <<'JSON'
{ "version":1, "qid":"cd04-q1", "options":["a","b","c"],
  "scope":{"geo":["cd04"]}, "originality_required":true, "dedup_key":"nonce" }
JSON
mk() { printf '%s' "$2" > "$work/$1"; }
mk good.json   '{"qid":"cd04-q1","option":"a","geo":"cd04","original":true,"nonce":"n1"}'
mk offg.json   '{"qid":"cd04-q1","option":"z","geo":"cd04","original":true,"nonce":"n2"}'
mk geo.json    '{"qid":"cd04-q1","option":"b","geo":"cd99","original":true,"nonce":"n3"}'
mk noorig.json '{"qid":"cd04-q1","option":"b","geo":"cd04","original":false,"nonce":"n4"}'
mk bad.txt     'not json at all'

echo "[1] verdicts"
[ "$(bin/accept --resp "$work/good.json"   --guidance "$gv1")" = "accepted -" ]      || fail "good not accepted"
[ "$(bin/accept --resp "$work/offg.json"   --guidance "$gv1")" = "dropped off-guidance" ] || fail "offg"
[ "$(bin/accept --resp "$work/geo.json"    --guidance "$gv1")" = "dropped geo" ]     || fail "geo"
[ "$(bin/accept --resp "$work/noorig.json" --guidance "$gv1")" = "dropped other" ]   || fail "originality"
[ "$(bin/accept --resp "$work/bad.txt"     --guidance "$gv1")" = "dropped malformed" ] || fail "malformed"
ok "accepted / off-guidance / geo / originality / malformed"

echo "[2] re-filter: edit guidance to forbid option a, bump version -> verdict flips"
gv2="$work/guidance2.json"
jq '.version=2 | .options=["b","c"]' "$gv1" > "$gv2"
[ "$(bin/accept --resp "$work/good.json" --guidance "$gv2")" = "dropped off-guidance" ] || fail "re-filter"
[ "$(jq .version "$gv2")" = "2" ] || fail "version did not advance"
ok "guidance edit re-filters (v1 accept -> v2 off-guidance), version advances"

echo "[3] dedup within a seen-set"
seen="$work/seen"; : > "$seen"
[ "$(bin/accept --resp "$work/good.json" --guidance "$gv1" --seen "$seen")" = "accepted -" ] || fail "first"
[ "$(bin/accept --resp "$work/good.json" --guidance "$gv1" --seen "$seen")" = "dropped duplicate" ] || fail "dup"
ok "same dedup_key seen twice -> duplicate"

# ---- ingest pipeline + ledger, over real questions/cd04-q1/guidance.json ----
# payloads: 0 accepted, 1 off-guidance, 2 geo, 3 originality(other), 4 malformed
pa="$work/pa"; mkdir -p "$pa"
cp "$work/good.json" "$pa/0.json"; cp "$work/offg.json" "$pa/1.json"
cp "$work/geo.json" "$pa/2.json"; cp "$work/noorig.json" "$pa/3.json"; cp "$work/bad.txt" "$pa/4.json"
# direct: 0 accepted (new nonce), 1 duplicate of atlas n1 (cross-Tell)
pd="$work/pd"; mkdir -p "$pd"
printf '%s' '{"qid":"cd04-q1","option":"c","geo":"cd04","original":true,"nonce":"n5"}' > "$pd/0.json"
cp "$work/good.json" "$pd/1.json"

DP_SRC=atlas  DP_PAYLOAD_DIR="$pa" test/make-fixtures.sh "$work/a" "$recip" 5 "" >/dev/null
DP_SRC=direct DP_DIRECT=1 DP_PAYLOAD_DIR="$pd" test/make-fixtures.sh "$work/d" "$recip" 2 "" >/dev/null

# stage each inbox onto its feed branch via a throwaway worktree
git worktree add -q --detach "$work/wt"
stage() { # BRANCH SRCDIR
  ( cd "$work/wt" && git checkout -q --orphan "$1" && (git rm -rq --cached . 2>/dev/null || true) \
    && rm -rf ./* 2>/dev/null; mkdir -p inbox && cp "$2"/inbox/* inbox/ \
    && git add inbox && git commit -qm "feed $1" ); }
stage feed/atlas  "$work/a"
stage feed/direct "$work/d"
git worktree remove --force "$work/wt"

echo "[4] ingest governs both feeds; ledger carries verdicts, no plaintext"
DP_FETCH_REMOTE=. DP_ALLOW_UNSIGNED=1 DP_IDENTITY_FILE="$work/id.txt" bin/ingest >/dev/null
L=state/atlas/ledger.json
[ "$(jq -r '.entries[0].verdict' "$L")" = "accepted" ]            || fail "a0 accepted"
[ "$(jq -r '.entries[1].reason'  "$L")" = "off-guidance" ]        || fail "a1 off-guidance"
[ "$(jq -r '.entries[2].reason'  "$L")" = "geo" ]                 || fail "a2 geo"
[ "$(jq -r '.entries[3].reason'  "$L")" = "other" ]              || fail "a3 originality"
[ "$(jq -r '.entries[4].reason'  "$L")" = "malformed" ]           || fail "a4 malformed"
[ "$(jq -r '.entries[0].guidance_version' "$L")" = "1" ]          || fail "guidance_version recorded"
grep -q '"option"' "$L" && fail "plaintext leaked into ledger" || ok "no plaintext in ledger"
ok "atlas ledger verdicts correct"

echo "[5] direct (unsigned) ingress governed; cross-Tell dedup"
D=state/direct/ledger.json
[ "$(jq -r '.unsigned' "$D")" = "true" ]                          || fail "direct not marked unsigned"
[ "$(jq -r '.entries[0].verdict' "$D")" = "accepted" ]            || fail "d0 accepted"
[ "$(jq -r '.entries[1].reason'  "$D")" = "duplicate" ]           || fail "cross-Tell dedup (n1 already seen on atlas)"
ok "direct accepted + cross-Tell duplicate dropped"

echo "ALL GOVERNOR TESTS PASSED"
