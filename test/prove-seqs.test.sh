#!/usr/bin/env bash
# bin/prove --seqs — disclosing an ARBITRARY set of blocks (an interior quote), not a tail.
# The public half (--check, refusals, parsing) needs only openssl/jq/sha256sum and runs anywhere;
# the OWNER half needs `age` to wrap per-block keys and is skipped, stated, where age is absent —
# the same posture DP_ALLOW_UNSIGNED takes for ssh-keygen.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
. bin/lib.sh
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
# Capture a DELIBERATELY failing command's output. Never pipe one into grep: lib.sh sets
# `set -o pipefail`, so the pipeline would report the command's exit status and mask the match.
says() { set +e; local o; o="$("$@" 2>&1)"; set -e; printf '%s' "$o"; }
refuses() { set +e; "$@" >/dev/null 2>&1; local st=$?; set -e; [ "$st" != "0" ]; }
inbox="$work/inbox"; mkdir -p "$inbox"

echo "[1] build an 8-block drop chain, keeping the plaintext keys aside"
entries="[]"; prev="null"
for i in 0 1 2 3 4 5 6 7; do
  p="$(printf '%06d' "$i")"; k="$(openssl rand -hex 32)"; echo "$k" > "$work/k$i"
  printf 'block %s payload\n' "$i" > "$work/plain"
  dp_enc "$k" "$work/plain" "$inbox/$p.enc"
  printf 'placeholder\n' > "$inbox/$p.kage"
  entries="$(printf '%s' "$entries" | jq --argjson s "$i" --arg b "$p.enc" --arg kf "$p.kage" \
    --arg th "sha256:$(dp_sha256_file "$inbox/$p.enc")" --argjson ph "$prev" \
    --arg rp "sha256:$(dp_ratchet_pub "$k")" \
    '. + [{seq:$s, source:"drop", block:$b, key:$kf, this_hash:$th, prev_hash:$ph, ratchet_pub:$rp}]')"
  prev="\"sha256:$(dp_sha256_file "$inbox/$p.enc")\""
done
jq -n --argjson e "$entries" --arg dg "$(printf '%s' "$entries" | jq -cS '.' | tr -d '\n' | sha256sum | cut -d' ' -f1)" \
  '{version:1, source:"drop", entries:$e, head:{seq:7, digest:$dg, sig:null}}' > "$inbox/manifest.json"
ok "8 blocks sealed"

echo "[2] the spec parser: expansion, dedupe, and round-trip through dp_ranges"
[ "$(dp_expand_seqs '0,30-36,41' | tr '\n' ' ')" = "0 30 31 32 33 34 35 36 41 " ] || fail "expansion wrong"
[ "$(dp_expand_seqs '5,5,4-6' | tr '\n' ' ')" = "4 5 6 " ] || fail "dedupe wrong"
[ "$(dp_ranges "$(dp_expand_seqs '0,30-36,41' | tr '\n' ' ')")" = " 0,30-36,41" ] || fail "round-trip wrong"
ok "0,30-36,41 expands, dedupes, and round-trips"

echo "[3] a malformed spec FAILS rather than disclosing a guess"
for bad in "3-1" "1,abc,5" ""; do
  set +e; out="$(dp_expand_seqs "$bad" 2>/dev/null)"; st=$?; set -e
  [ "$st" = "0" ] && [ -n "$bad" ] && fail "parser accepted '$bad'"
done
ok "descending ranges and non-numeric specs are refused"

echo "[4] --from and --seqs are alternatives, not a pair"
refuses bin/prove --dir "$work" --source drop --from 1 --seqs 2 || fail "accepted both"
case "$(says bin/prove --dir "$work" --source drop --from 1 --seqs 2)" in
  *alternatives*) ;; *) fail "refusal did not explain that they are alternatives";; esac
ok "passing both is refused by name"

echo "[5] --check accepts a hand-built interior bundle and names what it proved"
sel="0 3 4 5"
keys="{}"; for s in $sel; do keys="$(jq -c --arg s "$s" --arg k "$(cat "$work/k$s")" '. + {($s): $k}' <<<"$keys")"; done
jq -n --argjson k "$keys" --arg dg "$(jq -r '.head.digest' "$inbox/manifest.json")" \
  '{source:"drop", seqs:[0,3,4,5], block_keys:$k, manifest_digest:$dg}' > "$work/bundle.json"
[ "$(bin/prove --dir "$work" --check "$work/bundle.json" 2>"$work/log")" = "proven" ] || { cat "$work/log"; fail "--check rejected a valid interior bundle"; }
grep -q "seq 0,3-5" "$work/log" || { cat "$work/log"; fail "--check did not name the proved seqs as ranges"; }
ok "proves seq 0,3-5 and says so"

echo "[6] a bundle whose key does not match its published commitment is refused"
jq '.block_keys["3"] = "'"$(openssl rand -hex 32)"'"' "$work/bundle.json" > "$work/forged.json"
refuses bin/prove --dir "$work" --check "$work/forged.json" || fail "accepted a forged key"
case "$(says bin/prove --dir "$work" --check "$work/forged.json")" in
  *"commitment mismatch"*) ;; *) fail "wrong refusal reason";; esac
ok "commitment mismatch caught"

echo "[7] blocks outside the set stay sealed — the disclosure does not leak sideways"
for s in 1 2 6 7; do
  jq -e --arg s "$s" '.block_keys | has($s)' "$work/bundle.json" >/dev/null 2>&1 && fail "seq $s leaked into the bundle"
done
ok "seq 1,2,6-7 absent from the bundle"

echo "[8] --seqs refuses a RATCHET feed, where interior-only cannot be honoured"
mkdir -p "$work/r/inbox"; cp "$inbox"/*.enc "$work/r/inbox/"
jq 'del(.entries[].key)' "$inbox/manifest.json" > "$work/r/inbox/manifest.json"
case "$(says env DP_IDENTITY_FILE=/dev/null bin/prove --dir "$work/r" --source drop --seqs 3)" in
  *"ratchet feed"*) ;; *) fail "did not explain why --seqs cannot apply to a ratchet feed";; esac
ok "refused with the reason, and points at --from"

echo "[9] out-of-range seqs are refused against the real feed length"
case "$(says env DP_IDENTITY_FILE=/dev/null bin/prove --dir "$work" --source drop --seqs 99)" in
  *"has 8 block"*) ;; *) fail "did not bound-check against the manifest";; esac
ok "seq 99 refused against an 8-block feed"

if command -v age >/dev/null 2>&1; then
  echo "[10] OWNER: --seqs unwraps only the named keys and writes a bundle"
  age-keygen -o "$work/id.txt" 2>/dev/null; recip="$(age-keygen -y "$work/id.txt")"
  for i in 0 1 2 3 4 5 6 7; do cat "$work/k$i" | tr -d '\n' | age -r "$recip" -o "$inbox/$(printf '%06d' "$i").kage"; done
  b="$(DP_IDENTITY_FILE="$work/id.txt" bin/prove --dir "$work" --source drop --seqs 0,3-5 2>"$work/olog")"
  [ "$(jq -r '.seqs | @csv' "$b")" = "0,3,4,5" ] || fail "bundle names the wrong seqs"
  grep -q "DISCLOSES 4 of 8" "$work/olog" || { cat "$work/olog"; fail "did not state the disclosure size"; }
  [ "$(bin/prove --dir "$work" --check "$b")" = "proven" ] || fail "own bundle did not verify"
  ok "owner bundle for 0,3-5 verifies under --check"
else
  echo "[10] OWNER leg SKIPPED — age absent (per-block keys cannot be wrapped here)"
fi

if command -v node >/dev/null 2>&1; then
  echo "[11] the .mjs mirror agrees with the bash bin, on the same bytes"
  [ "$(node bin/prove.mjs --dir "$work" --check "$work/bundle.json" 2>/dev/null)" = "proven" ] \
    || fail "prove.mjs rejected a bundle the bash bin proved"
  refuses node bin/prove.mjs --dir "$work" --check "$work/forged.json" || fail "prove.mjs accepted a forged key"
  # Same refusals, same reasons — a mirror that diverges on WHY is a mirror that has rotted.
  for probe in "ratchet feed:--dir|$work/r|--seqs|3" "has 8 block:--dir|$work|--seqs|99" "alternatives:--dir|$work|--from|1|--seqs|2"; do
    want="${probe%%:*}"; IFS='|' read -r -a argv <<< "${probe#*:}"
    case "$(says bin/prove --source drop "${argv[@]}")" in *"$want"*) ;; *) fail "bash lost the '$want' refusal";; esac
    case "$(says env DP_IDENTITY_FILE=/dev/null node bin/prove.mjs --source drop "${argv[@]}")" in
      *"$want"*) ;; *) fail "prove.mjs does not refuse with '$want' where bash does";; esac
  done
  ok "--check agrees; all three refusals carry the same reason in both"
else
  echo "[11] mirror check SKIPPED (node absent)"
fi

echo "PASS: prove --seqs"
