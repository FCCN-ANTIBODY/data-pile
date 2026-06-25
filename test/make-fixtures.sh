#!/usr/bin/env bash
# Build a sample delivered feed — the reference for what a Tell produces per source.
# Emits inbox/{<seq>.{enc|age}, [seed.age], manifest.json} into OUTDIR.
#
# Usage: test/make-fixtures.sh OUTDIR RECIPIENT NBLOCKS [SIGN_KEY]
#   RECIPIENT  age recipient string (age1...)
#   NBLOCKS    number of blocks to generate
#   SIGN_KEY   optional ssh private key to sign the manifest head; omitted -> head.sig=null
#
# Env knobs:
#   DP_SRC=<name>        source/Tell name in the manifest (default: atlas)
#   DP_PAYLOAD_DIR=DIR   per-block plaintext from DIR/<i>.json (default: generic text)
#   DP_DIRECT=1          direct mode: age-to-recipient blocks (*.age), no seed, no ratchet,
#                        unsigned manifest (ratchet_pub:null, sig:null) — the QR ingress shape.

here="$(cd "$(dirname "$0")/../bin" && pwd)"
. "$here/lib.sh"

out="$1"; recip="$2"; nblocks="$3"; signkey="${4:-}"
src="${DP_SRC:-atlas}"
inbox="$out/inbox"; mkdir -p "$inbox"

direct="${DP_DIRECT:-0}"
k="$(openssl rand -hex 32)"        # K_0 (ratchet mode only)
[ "$direct" = "1" ] || printf '%s' "$k" | age -r "$recip" -o "$inbox/seed.age"

plaintext_for() { # SEQ OUTFILE
  if [ -n "${DP_PAYLOAD_DIR:-}" ] && [ -f "$DP_PAYLOAD_DIR/$1.json" ]; then
    cp "$DP_PAYLOAD_DIR/$1.json" "$2"
  else
    printf 'digest block seq %s — produced %s\n' "$1" "$(date -u +%FT%TZ)" > "$2"
  fi
}

entries="[]"; prev="null"; kk="$k"
i=0
while [ "$i" -lt "$nblocks" ]; do
  seqp="$(printf '%06d' "$i")"
  plaintext_for "$i" "$inbox/$seqp.plain"
  if [ "$direct" = "1" ]; then
    block="$seqp.age"; age -r "$recip" -o "$inbox/$block" "$inbox/$seqp.plain"; rpub="null"
  else
    block="$seqp.enc"; dp_enc "$kk" "$inbox/$seqp.plain" "$inbox/$block"; rpub="\"sha256:$(dp_ratchet_pub "$kk")\""
  fi
  rm -f "$inbox/$seqp.plain"
  this="sha256:$(dp_sha256_file "$inbox/$block")"
  entries="$(printf '%s' "$entries" | jq \
    --argjson seq "$i" --arg ca "$(date -u +%FT%TZ)" --arg src "$src" \
    --arg block "$block" --arg th "$this" --argjson ph "$prev" --argjson rp "$rpub" \
    '. + [{seq:$seq, created_at:$ca, source:$src, block:$block, this_hash:$th, prev_hash:$ph, ratchet_pub:$rp}]')"
  prev="\"$this\""
  kk="$(dp_ratchet_next "$kk")"
  i=$((i+1))
done

# Manifest head: digest over canonical entries, signed if a key was provided (not in direct mode).
tmp="$(mktemp)"; printf '%s' "$entries" | jq -cS '.' > "$tmp"
digest="$(cat "$tmp" | tr -d '\n' | sha256sum | cut -d' ' -f1)"
sig="null"
if [ "$direct" != "1" ] && [ -n "$signkey" ] && command -v ssh-keygen >/dev/null 2>&1; then
  # Sign the digest; store the armored signature base64-encoded so JSON round-trips it
  # byte-for-byte (SSH signatures are newline-sensitive).
  printf '%s' "$digest" | ssh-keygen -Y sign -n data-pile -f "$signkey" 2>/dev/null > "$tmp.sig"
  sig="$(base64 -w0 < "$tmp.sig" | jq -R '.')"
fi
jq -n --argjson entries "$entries" --argjson seq "$((nblocks-1))" \
      --arg src "$src" --arg dg "$digest" --argjson sig "$sig" '
  { version:1, source:$src, entries:$entries, head:{seq:$seq, digest:$dg, sig:$sig} }' \
  > "$inbox/manifest.json"
echo "wrote $nblocks-block $([ "$direct" = 1 ] && echo direct || echo ratchet) feed to $inbox (src $src, signed=$([ "$sig" = null ] && echo no || echo yes))"
