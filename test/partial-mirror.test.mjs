// The .mjs mirror of test/partial.test.sh — verifyFeed({partial}) must agree with bin/verify
// --partial, since the player runs this one and the operator runs that one. Builds the fixture
// with bin/lib.sh so both sides are checked against the SAME bytes, then asserts they concur.
// Needs only openssl + jq + sha256sum, like its bash twin. Run: node test/partial-mirror.test.mjs
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { verifyFeed, canonicalEntries } from "../bin/feed-open.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const work = mkdtempSync(join(tmpdir(), "dp-partial-"));
const inbox = join(work, "inbox");
let failed = 0;
const ok = (m) => console.log("  ok: " + m);
const check = (c, m) => { if (c) ok(m); else { console.error("FAIL: " + m); failed++; } };

execFileSync("bash", ["-c", `
  set -euo pipefail; cd "${root}"; . bin/lib.sh
  mkdir -p "${inbox}"; entries="[]"; prev="null"
  for i in 0 1 2 3 4 5; do
    p="$(printf '%06d' "$i")"; k="$(openssl rand -hex 32)"
    printf 'block %s payload\\n' "$i" > "${work}/plain"
    dp_enc "$k" "${work}/plain" "${inbox}/$p.enc"
    printf 'age-wrapped-key-placeholder\\n' > "${inbox}/$p.kage"
    entries="$(printf '%s' "$entries" | jq --argjson s "$i" --arg b "$p.enc" --arg kf "$p.kage" \
      --arg th "sha256:$(dp_sha256_file "${inbox}/$p.enc")" --argjson ph "$prev" \
      --arg rp "sha256:$(dp_ratchet_pub "$k")" \
      '. + [{seq:$s, source:"drop", block:$b, key:$kf, this_hash:$th, prev_hash:$ph, ratchet_pub:$rp}]')"
    prev="\\"sha256:$(dp_sha256_file "${inbox}/$p.enc")\\""
  done
  digest="$(printf '%s' "$entries" | jq -cS '.' | tr -d '\\n' | sha256sum | cut -d' ' -f1)"
  jq -n --argjson e "$entries" --arg dg "$digest" \
    '{version:1, source:"drop", entries:$e, head:{seq:5, digest:$dg, sig:null}}' > "${inbox}/manifest.json"
`]);

const manifest = JSON.parse(readFileSync(join(inbox, "manifest.json")));
const load = () => Object.fromEntries(readdirSync(inbox).filter(f => f.endsWith(".enc"))
  .map(f => [f, new Uint8Array(readFileSync(join(inbox, f)))]));
const V = (blocks, partial) => verifyFeed({ manifest, blocks, source: "drop", allowUnsigned: true, partial });

console.log("[1] complete holding verifies, and reports complete");
let r = await V(load(), false);
check(r.ok && r.complete && r.held.length === 6 && r.notHeld.length === 0, "6/6 held, complete:true");

console.log("[2] partial:true on a complete holding does not understate");
r = await V(load(), true);
check(r.ok && r.complete === true && r.notHeld.length === 0, "complete stays complete under partial");

console.log("[3] drop seq 1,2,5 — the disclosed-excerpt shape");
for (const g of ["000001", "000002", "000005"]) {
  rmSync(join(inbox, g + ".enc")); rmSync(join(inbox, g + ".kage"));
}

console.log("[4] absent block is STILL fatal without partial, and names the remedy");
r = await V(load(), false);
check(!r.ok && /partial:true/.test(r.reason), "refuses and points at partial:true");

console.log("[5] partial verifies the smaller claim and names what went unchecked");
r = await V(load(), true);
check(r.ok && r.complete === false, "ok:true but complete:false");
check(JSON.stringify(r.held) === "[0,3,4]", "held = [0,3,4]");
check(JSON.stringify(r.notHeld) === "[1,2,5]", "notHeld = [1,2,5]");

console.log("[6] the bash twin agrees, on the same bytes");
const bash = execFileSync("bash", ["-c",
  `cd "${root}" && DP_ALLOW_UNSIGNED=1 bin/verify --dir "${work}" --source drop --partial 2>/dev/null`
]).toString().trim();
check(bash === `verified-partial ${r.held.length}/${manifest.entries.length}`,
  `bin/verify says "${bash}", verifyFeed says ${r.held.length}/${manifest.entries.length}`);

console.log("[7] tampering with a HELD block is still caught under partial");
const t = load(); t["000003.enc"] = new Uint8Array([...t["000003.enc"], 120]);
r = await V(t, true);
check(!r.ok && /tampered/.test(r.reason), "tamper in a held block detected");

console.log("[8] chain linkage enforced with ZERO bytes held");
r = await V({}, true);
check(r.ok && r.held.length === 0 && r.notHeld.length === 6, "sound chain verifies holding nothing");
// Break the chain AND recompute head.digest to match, which is what a forger who controls an
// unsigned manifest would do. Without this the digest check fires first and the linkage check
// is never reached — so the naive version of this test passes without proving anything.
const broken = JSON.parse(JSON.stringify(manifest));
broken.entries[3].prev_hash = "sha256:" + "de".repeat(32);
broken.head.digest = Buffer.from(await crypto.subtle.digest(
  "SHA-256", new TextEncoder().encode(canonicalEntries(broken.entries)))).toString("hex");
r = await verifyFeed({ manifest: broken, blocks: {}, source: "drop", allowUnsigned: true, partial: true });
check(!r.ok && /broken chain/.test(r.reason), "broken chain caught holding nothing, digest recomputed");

rmSync(work, { recursive: true, force: true });
if (failed) { console.error(`\n${failed} check(s) failed`); process.exit(1); }
console.log("PASS: partial verification mirror");
