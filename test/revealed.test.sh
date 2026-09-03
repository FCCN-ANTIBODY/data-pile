#!/usr/bin/env bash
# The disclosure ledger: what has gone out, what must never, and what is newly going out.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
. bin/lib.sh
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
says() { set +e; local o; o="$("$@" 2>&1)"; set -e; printf '%s' "$o"; }
refuses() { set +e; "$@" >/dev/null 2>&1; local st=$?; set -e; [ "$st" != "0" ]; }

echo "[1] seal a 12-block pile and disclose 2-4"
age-keygen -o "$work/id" 2>/dev/null; mkdir -p "$work/keys"
age-keygen -y "$work/id" > "$work/keys/pile.age.pub"
for i in $(seq 0 11); do printf 'block %s\n' "$i" > "$work/b$i"; done
bin/drop-pack --dir "$work" $(for i in $(seq 0 11); do echo "$work/b$i"; done) >/dev/null 2>&1
DP_IDENTITY_FILE="$work/id" bin/prove --dir "$work" --source drop --seqs 2-4 >/dev/null 2>&1
ok "12 blocks sealed, 2-4 disclosed"

echo "[2] the ledger records it WITHOUT keys"
L="$work/reports/revealed.json"
[ -f "$L" ] || fail "no ledger written"
[ "$(jq -r '.events[0].seqs' "$L")" = "2-4" ] || fail "ledger did not record the range"
# The precise check, not a pattern: no key from the bundle may appear in the ledger. (A naive
# /[0-9a-f]{64}/ scan fails on `manifest_digest`, which is a PUBLIC digest and belongs there.)
B="$work/reports/proof-drop-seqs-2-4.json"
for k in $(jq -r '.block_keys[]' "$B"); do
  grep -q "$k" "$L" && fail "THE LEDGER CONTAINS A BLOCK KEY"
done
[ "$(jq -r '.block_keys | length' "$B")" = "3" ] || fail "the bundle should carry 3 keys"
ok "records seq 2-4; none of the bundle's 3 keys appear in it"

echo "[3] it reports what is out and what is still sealed"
out="$(says bin/revealed --dir "$work")"
case "$out" in *"disclosed : 3"*) ;; *) fail "wrong disclosed count: $out";; esac
case "$out" in *"seq 0-1,5-11"*) ;; *) fail "wrong sealed set: $out";; esac
ok "3 disclosed, seq 0-1,5-11 still sealed"

echo "[4] a second disclosure names only what is NEW"
msg="$(says env DP_IDENTITY_FILE=$work/id bin/prove --dir "$work" --source drop --seqs 3-6)"
case "$msg" in *"NEW: seq 5-6"*) ;; *) fail "did not name the newly-disclosed blocks: $msg";; esac
ok "3-4 were already out; only 5-6 announced as new"

echo "[5] re-disclosing nothing new says so"
msg="$(says env DP_IDENTITY_FILE=$work/id bin/prove --dir "$work" --source drop --seqs 3-4)"
case "$msg" in *"nothing new"*) ;; *) fail "should have reported nothing new: $msg";; esac
ok "a repeat disclosure is announced as a repeat"

echo "[6] withholding needs a reason"
refuses bin/revealed --dir "$work" --withhold 9-10 || fail "accepted a withhold with no reason"
case "$(says bin/revealed --dir "$work" --withhold 9-10)" in
  *reason*) ;; *) fail "refusal did not say a reason is required";; esac
ok "an unexplained redaction is refused"

echo "[7] you cannot withhold what is already public"
refuses bin/revealed --dir "$work" --withhold 3 --reason "too late" || fail "allowed withholding a disclosed block"
case "$(says bin/revealed --dir "$work" --withhold 3 --reason 'too late')" in
  *"already disclosed"*) ;; *) fail "wrong reason";; esac
ok "marking an already-public block would be a promise the pile cannot keep"

echo "[8] a withheld block is REFUSED, not warned about"
bin/revealed --dir "$work" --withhold 9-10 --reason "bystander, editor direction" >/dev/null 2>&1
refuses env DP_IDENTITY_FILE="$work/id" bin/prove --dir "$work" --source drop --seqs 8-11 \
  || fail "disclosed a withheld block"
case "$(says env DP_IDENTITY_FILE=$work/id bin/prove --dir "$work" --source drop --seqs 8-11)" in
  *WITHHELD*) ;; *) fail "refusal did not name the mark";; esac
[ ! -f "$work/reports/proof-drop-seqs-8-11.json" ] || fail "a bundle was written despite the refusal"
ok "refused before writing anything; the keys never left"

echo "[9] the refusal does not block the rest of the payload"
DP_IDENTITY_FILE="$work/id" bin/prove --dir "$work" --source drop --seqs 8,11 >/dev/null 2>&1 \
  || fail "could not disclose around the withheld region"
ok "8 and 11 disclose fine with 9-10 held back"

# The seq sets are compared NUMERICALLY. A comm-based implementation needs LEXICAL order, where
# 10 sorts before 2 — and BSD comm tolerates the mismatch while GNU comm refuses, so the bug
# passes on a mac and fails in CI. Pin the multi-digit cases explicitly rather than trusting a
# range to happen to cross the boundary.
echo "[10] multi-digit seqs compare numerically, not lexically"
[ "$(dp_set_minus "$(seq 0 11)" "2 3")" = "0 1 4 5 6 7 8 9 10 11 " ] || fail "set-minus mis-ordered past 9"
[ "$(dp_set_and "8 9 10 11" "10 11 12")" = "10 11 " ] || fail "set-and mis-matched past 9"
# 11 is already out (step 9); 1 never has been. If the two were conflated, disclosing 1 would
# report "nothing new" — which is the exact silent wrong answer a lexical comparison gives.
msg="$(says env DP_IDENTITY_FILE=$work/id bin/prove --dir "$work" --source drop --seqs 1)"
case "$msg" in *"NEW: seq 1"*) ;; *) fail "seq 1 was confused with 11: $msg";; esac
out="$(says bin/revealed --dir "$work")"
case "$out" in *"seq 0,7,9-10"*) ;; *) fail "sealed set wrong with multi-digit members: $out";; esac
ok "1 and 11 are distinct; the sealed set spans single and double digits"

echo "[11] the NEGATIVE claim — the one a subject actually cares about"
# "These were disclosed" is weak: the keys are public and say so themselves. "This has NEVER been
# disclosed" is the claim worth making, and it is only as good as the ledger being whole.
out="$(says bin/revealed --dir "$work" --never 0)"
case "$out" in *"never-disclosed seq 0"*) ;; *) fail "seq 0 was never disclosed: $out";; esac
case "$out" in *"against ledger head"*) ;; *) fail "the claim must state what it rests on";; esac
refuses bin/revealed --dir "$work" --never 2 || fail "seq 2 HAS been disclosed"
case "$(says bin/revealed --dir "$work" --never 2)" in
  *"NOT never-disclosed"*) ;; *) fail "wrong refusal";; esac
ok "asserts never-disclosed, cites the head it rests on, refuses when false"

echo "[12] a reveal must say what it is for"
refuses bin/revealed --dir "$work" --record 7 || fail "accepted a reveal with no reason"
case "$(says bin/revealed --dir "$work" --record 7)" in
  *reason*) ;; *) fail "refusal did not ask for a reason";; esac
[ -n "$(jq -r '.events[0].reason // empty' "$L")" ] || fail "prove did not record a reason"
ok "a disclosure you cannot explain is one you did not need"

echo "[13] the events are chained — a dropped row is visible"
bin/revealed --dir "$work" --check >/dev/null 2>&1 || fail "a well-formed chain should verify"
cp "$L" "$work/ledger.bak"
jq 'del(.events[0])' "$L" > "$work/t" && mv "$work/t" "$L"
refuses bin/revealed --dir "$work" --check || fail "dropping an event went unnoticed"
case "$(says bin/revealed --dir "$work" --check)" in
  *"chain BROKEN"*) ;; *) fail "wrong complaint";; esac
# Editing in place, rather than deleting, must also show.
cp "$work/ledger.bak" "$L"
jq '.events[0].seqs = "2-6"' "$L" > "$work/t" && mv "$work/t" "$L"
refuses bin/revealed --dir "$work" --check || fail "widening a past event went unnoticed"
cp "$work/ledger.bak" "$L"
ok "removing or editing a past disclosure breaks the chain visibly"

echo "PASS: the disclosure ledger"
