#!/usr/bin/env bash
# Shared helpers for the data-pile toolbox. Source this; don't run it.
#
# Crypto primitives (kept deliberately small, near-zero deps: age, openssl, jq, sha256sum):
#   ratchet:   K_{n+1} = sha256("ratchet:" || K_n)        one-way; forward-only disclosure
#   commit:    ratchet_pub = sha256("pub:" || K_n)        published-safe commitment to K_n
#   block iv:  iv = sha256("iv:" || K_n)[:16]             unique per block (each block has its own key)
#   block enc: aes-256-ctr under K_n                      integrity comes from the signed manifest
#
# All keys are 64-hex-char (32-byte) strings.

set -euo pipefail

dp_sha256_str() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
dp_sha256_file() { sha256sum "$1" | cut -d' ' -f1; }

dp_ratchet_next() { dp_sha256_str "ratchet:$1"; }
dp_ratchet_pub()  { dp_sha256_str "pub:$1"; }
dp_iv()           { dp_sha256_str "iv:$1" | cut -c1-32; }

dp_enc() { # KHEX IN OUT
  openssl enc -aes-256-ctr -K "$1" -iv "$(dp_iv "$1")" -in "$2" -out "$3"
}
dp_dec() { # KHEX IN OUT  (OUT="-" for stdout)
  if [ "$3" = "-" ]; then
    openssl enc -d -aes-256-ctr -K "$1" -iv "$(dp_iv "$1")" -in "$2"
  else
    openssl enc -d -aes-256-ctr -K "$1" -iv "$(dp_iv "$1")" -in "$2" -out "$3"
  fi
}

# Canonical serialization of the manifest entries array -> the digest the head signs.
dp_entries_digest() { # MANIFEST_FILE
  jq -cS '.entries' "$1" | tr -d '\n' | sha256sum | cut -d' ' -f1
}

dp_die() { echo "data-pile: $*" >&2; exit 1; }
dp_log() { echo "data-pile: $*" >&2; }

# --- pile.yml readers (no YAML dep: grep the simple `tells:` shape) ----------------
# A "source" is a Tell you joined: a `- name:` entry under `tells:` with branch/signer.
dp_tells() { awk '$1=="-" && $2=="name:" {print $3}' "$1"; }   # PILE_YML -> names

dp_source_branch() { # SOURCE_NAME PILE_YML
  awk -v s="$1" '
    $1=="-" && $2=="name:" { cur=$3 }
    cur==s && $1=="branch:" { print $2; exit }
  ' "$2"
}
dp_source_signer() { # SOURCE_NAME PILE_YML
  awk -v s="$1" '
    $1=="-" && $2=="name:" { cur=$3 }
    cur==s && $1=="signer:" { gsub(/"/,"",$2); print $2; exit }
  ' "$2"
}
dp_source_unsigned() { # SOURCE_NAME PILE_YML -> "true" if this source is unauthenticated
  awk -v s="$1" '
    $1=="-" && $2=="name:" { cur=$3 }
    cur==s && $1=="unsigned:" { gsub(/"/,"",$2); print $2; exit }
  ' "$2"
}

# --- ratchet derivation (shared by decrypt + ingest) -------------------------------
dp_unwrap_seed() { age -d -i "$2" "$1/seed.age"; }   # INBOX IDFILE -> K_0
dp_derive() { # K0 SEQ -> K_seq
  local k="$1" i=0
  while [ "$i" -lt "$2" ]; do k="$(dp_ratchet_next "$k")"; i=$((i+1)); done
  printf '%s' "$k"
}

# --- the acceptance governor -------------------------------------------------------
# Verdict for one decrypted response against a question's machine-readable guidance.
# Prints "<verdict> <reason>"; reason vocabulary mirrors Atlas's rejected{}:
#   accepted - | dropped malformed|off-guidance|geo|duplicate|other
# SEEN_FILE accumulates "<qid>:<dedup_key>" across the whole run for cross-Tell dedup.
dp_accept_verdict() { # RESP_FILE GUIDANCE_FILE SEEN_FILE
  local resp="$1" g="$2" seen="$3" qid opt geo dkf dk
  jq -e . "$resp" >/dev/null 2>&1 || { echo "dropped malformed"; return; }
  qid="$(jq -r '.qid // empty' "$resp")"; opt="$(jq -r '.option // empty' "$resp")"
  { [ -n "$qid" ] && [ -n "$opt" ]; } || { echo "dropped malformed"; return; }
  jq -e --arg o "$opt" '(.options // []) | index($o)' "$g" >/dev/null 2>&1 \
    || { echo "dropped off-guidance"; return; }
  if jq -e '.scope.geo' "$g" >/dev/null 2>&1; then
    geo="$(jq -r '.geo // empty' "$resp")"
    jq -e --arg x "$geo" '.scope.geo | index($x)' "$g" >/dev/null 2>&1 \
      || { echo "dropped geo"; return; }
  fi
  if [ "$(jq -r '.originality_required // false' "$g")" = "true" ]; then
    [ "$(jq -r '.original // false' "$resp")" = "true" ] || { echo "dropped other"; return; }
  fi
  dkf="$(jq -r '.dedup_key // "dedup_key"' "$g")"
  dk="$(jq -r --arg f "$dkf" '.[$f] // empty' "$resp")"
  if [ -n "$dk" ]; then
    if grep -qxF "$qid:$dk" "$seen" 2>/dev/null; then echo "dropped duplicate"; return; fi
    echo "$qid:$dk" >> "$seen"
  fi
  echo "accepted -"
}
