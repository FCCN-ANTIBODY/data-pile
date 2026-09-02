#!/usr/bin/env bash
# The ENGINE posture: data-pile mounted at a site's .pile-engine/ rather than standing alone.
# A journal that is also its own pile mounts it this way, so the tools must operate on the SITE
# — its pile.yml, its keys, its inbox — while living in the engine. Getting this wrong does not
# error; it quietly reads the engine's own template pile.yml and acts on the wrong repository,
# which is why every assertion below names WHICH repo it expects to have been touched.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
. bin/lib.sh
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }

echo "[1] site resolution, all three postures"
[ "$(dp_site "$root")" = "$root" ] || fail "standing alone, the engine IS the pile"
site="$work/journal"; mkdir -p "$site"; ln -s "$root" "$site/.pile-engine"
[ "$(dp_site "$site/.pile-engine")" = "$site" ] || fail "mounted, the pile is the site"
[ "$(DP_SITE=/elsewhere dp_site "$root")" = "/elsewhere" ] || fail "DP_SITE must override"
ok "standalone -> itself; .pile-engine -> the site; DP_SITE -> anywhere"

echo "[1b] a mounting site has NO pile.yml, and fill installs the engine's template"
# The step that existed only in someone's head: a journal becoming a pile has nothing to fill.
[ ! -f "$site/pile.yml" ] || fail "the fixture should start with no pile.yml"
age-keygen -o "$work/id0" 2>/dev/null
"$site/.pile-engine/bin/pile-new" fill --dir "$site" --id autumn-ryan --scope colorado   --recipient "$(age-keygen -y "$work/id0")" >/dev/null 2>&1 || fail "mounted fill failed"
[ -f "$site/pile.yml" ] || fail "fill did not install the template into the site"
grep -q '^id: "autumn-ryan"' "$site/pile.yml" || fail "installed template was not filled in"
[ -f "$site/keys/pile.age.pub" ] || fail "no recipient committed to the site"
# ...and the engine's own pile.yml must not have been edited in the process.
grep -q '^id: ""' "$root/pile.yml" || fail "THE ENGINE'S TEMPLATE WAS WRITTEN INTO"
ok "the site got a filled pile.yml; the engine's template is untouched"

echo "[1c] standing alone, a directory that is not a pile is still refused"
bare="$work/notapile"; mkdir -p "$bare"
if (cd "$root" && bin/pile-new fill --dir "$bare" --id x --scope co       --recipient "$(age-keygen -y "$work/id0")" >/dev/null 2>&1); then
  fail "fill adopted an arbitrary directory"
fi
ok "the safety that stops fill adopting any directory it is pointed at"

echo "[2] a mounted engine seals into the SITE, not into itself"
age-keygen -o "$work/id" 2>/dev/null
mkdir -p "$site/keys"; age-keygen -y "$work/id" > "$site/keys/pile.age.pub"   # re-key for this leg
printf 'evidence\n' > "$site/thing.txt"
# Invoked THROUGH the mount path, which is how a mounting site calls it.
"$site/.pile-engine/bin/drop-pack" --dir "$site" "$site/thing.txt" >/dev/null 2>&1 \
  || fail "mounted drop-pack could not seal into the site"
[ -f "$site/inbox/manifest.json" ] || fail "the site got no inbox"
[ ! -e "$root/inbox/manifest.json" ] || fail "THE ENGINE WAS WRITTEN INTO — the mount leaked"
ok "the site holds the inbox; the engine checkout is untouched"

echo "[3] the recipient came from the SITE's keys, not the engine's"
# The engine ships no keys/pile.age.pub, so a wrong resolution would have failed loudly here —
# but assert the sealed key really is the site's, not merely that something worked.
kf="$(jq -r '.entries[0].key' "$site/inbox/manifest.json")"
age -d -i "$work/id" "$site/inbox/$kf" >/dev/null 2>&1 || fail "site identity cannot open the site's block"
ok "sealed to the site's recipient"

echo "[4] a mounted engine verifies the SITE's chain"
out="$(cd "$site" && DP_ALLOW_UNSIGNED=1 ./.pile-engine/bin/verify --dir . --source drop 2>/dev/null)"
[ "$out" = "verified" ] || fail "mounted verify did not verify the site's chain (got '$out')"
ok "verify resolves the site's signers and pile.yml"

echo "[5] the standalone posture is unchanged"
sa="$work/solo"; mkdir -p "$sa/keys"; cp "$site/keys/pile.age.pub" "$sa/keys/"
printf 'solo\n' > "$sa/thing.txt"
bin/drop-pack --dir "$sa" "$sa/thing.txt" >/dev/null 2>&1 || fail "standalone drop-pack regressed"
[ -f "$sa/inbox/manifest.json" ] || fail "standalone produced no inbox"
ok "a plain fork still behaves exactly as before"

echo "[6] check-custody audits the ENGINE's bins against the SITE's declaration"
# These are two different repositories once mounted; conflating them audits the wrong one.
mkdir -p "$site/.github/workflows"
printf 'env:\n  X: ${{ secrets.SNEAKY }}\n' > "$site/.github/workflows/x.yml"
cp -R keys/custody.yml "$site/keys/custody.yml"
if (cd "$site" && ./.pile-engine/bin/check-custody >/dev/null 2>&1); then
  fail "an undeclared secret read in the SITE's workflow was not caught"
fi
ok "the site's undeclared secret read fails the audit"

echo "PASS: mounted engine posture"
