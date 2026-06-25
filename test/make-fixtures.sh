#!/usr/bin/env bash
# Build a sample delivered chain — the reference for what Atlas produces per source.
# Emits inbox/{NNNNNN.enc, seed.age, manifest.json} into OUTDIR.
#
# Usage: test/make-fixtures.sh OUTDIR RECIPIENT NBLOCKS [SIGN_KEY]
#   RECIPIENT  age recipient string (age1...)
#   NBLOCKS    number of blocks to generate
#   SIGN_KEY   optional ssh private key to sign the manifest head; if omitted, head.sig=null

here="$(cd "$(dirname "$0")/../bin" && pwd)"
. "$here/lib.sh"

out="$1"; recip="$2"; nblocks="$3"; signkey="${4:-}"
src="atlas"
inbox="$out/inbox"; mkdir -p "$inbox"

k="$(openssl rand -hex 32)"        # K_0
printf '%s' "$k" | age -r "$recip" -o "$inbox/seed.age"

entries="[]"; prev="null"; kk="$k"
i=0
while [ "$i" -lt "$nblocks" ]; do
  seqp="$(printf '%06d' "$i")"
  printf 'digest block seq %s — produced %s\n' "$i" "$(date -u +%FT%TZ)" > "$inbox/$seqp.plain"
  dp_enc "$kk" "$inbox/$seqp.plain" "$inbox/$seqp.enc"
  rm -f "$inbox/$seqp.plain"
  this="sha256:$(dp_sha256_file "$inbox/$seqp.enc")"
  rpub="sha256:$(dp_ratchet_pub "$kk")"
  entries="$(printf '%s' "$entries" | jq \
    --argjson seq "$i" --arg ca "$(date -u +%FT%TZ)" --arg src "$src" \
    --arg block "$seqp.enc" --arg th "$this" --argjson ph "$prev" --arg rp "$rpub" \
    '. + [{seq:$seq, created_at:$ca, source:$src, block:$block, this_hash:$th, prev_hash:$ph, ratchet_pub:$rp}]')"
  prev="\"$this\""
  kk="$(dp_ratchet_next "$kk")"
  i=$((i+1))
done

# Manifest head: digest over canonical entries, signed if a key was provided.
tmp="$(mktemp)"; printf '%s' "$entries" | jq -cS '.' > "$tmp"
digest="$(cat "$tmp" | tr -d '\n' | sha256sum | cut -d' ' -f1)"
sig="null"
if [ -n "$signkey" ] && command -v ssh-keygen >/dev/null 2>&1; then
  s="$(printf '%s' "$digest" | ssh-keygen -Y sign -n data-pile -f "$signkey" 2>/dev/null)"
  sig="$(printf '%s' "$s" | jq -Rs '.')"
fi
jq -n --argjson entries "$entries" --argjson seq "$((nblocks-1))" \
      --arg src "$src" --arg dg "$digest" --argjson sig "$sig" '
  { version:1, source:$src, entries:$entries, head:{seq:$seq, digest:$dg, sig:$sig} }' \
  > "$inbox/manifest.json"
echo "wrote $nblocks-block chain to $inbox (digest $digest, signed=$([ "$sig" = null ] && echo no || echo yes))"
