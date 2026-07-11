#!/usr/bin/env node
// data-pile/bin/prove.mjs — the on-device port of bin/prove (bash). Same disclosure contract, no shell:
// jq dissolves into JSON, sha256sum/openssl become WebCrypto, and the owner's `age -d` becomes age-open.mjs
// (the vendored age battery). Byte-compatible with the bash bin — the ratchet, the ratchet_pub commitment,
// and the AES-256-CTR block layout are identical, so a bundle either produces verifies under the other's
// --check (proven in test/prove.test.mjs against the real bash bin).
//
//   prove.mjs --check FILE [--dir DIR]           PUBLIC: verify a proof bundle against the signed manifest
//   prove.mjs --from N [--dir DIR] [--source S]   OWNER:  derive a checkpoint/keys bundle (needs the identity)
//
// The crypto (data-pile/bin/lib.sh):
//   ratchet:     K_{n+1} = sha256("ratchet:" || K_n)     commit: ratchet_pub = sha256("pub:" || K_n)
//   block:       AES-256-CTR, key = K (hex), iv = sha256("iv:" || K)[0:16]
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { decrypt as ageOpen } from "./age-open.mjs";

const enc = new TextEncoder(), dec = new TextDecoder();
const subtle = globalThis.crypto.subtle;
const die = (m) => { process.stderr.write("data-pile: " + m + "\n"); process.exit(1); };
const log = (m) => process.stderr.write("data-pile: " + m + "\n");
const hex = (b) => [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
const unhex = (s) => Uint8Array.from(s.match(/../g).map((h) => parseInt(h, 16)));
const readJSON = (p) => JSON.parse(readFileSync(p, "utf8"));

// ---- the lib.sh crypto, in WebCrypto ---------------------------------------------------------------
async function sha256Str(s) { return hex(new Uint8Array(await subtle.digest("SHA-256", enc.encode(s)))); }
const ratchetNext = (k) => sha256Str("ratchet:" + k);
const ratchetPub = (k) => sha256Str("pub:" + k);
const ivOf = async (k) => (await sha256Str("iv:" + k)).slice(0, 32);
async function decBlock(khex, data) {
  const key = await subtle.importKey("raw", unhex(khex), { name: "AES-CTR" }, false, ["decrypt"]);
  return new Uint8Array(await subtle.decrypt({ name: "AES-CTR", counter: unhex(await ivOf(khex)), length: 128 }, key, data));
}

// ---- args ------------------------------------------------------------------------------------------
const args = process.argv.slice(2);
let dir = ".", source = "tell", from = "", check = "";
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--dir") dir = args[++i];
  else if (args[i] === "--source") source = args[++i];
  else if (args[i] === "--from") from = args[++i];
  else if (args[i] === "--check") check = args[++i];
  else die("unknown arg: " + args[i]);
}
const inbox = join(dir, "inbox"), manifestPath = join(inbox, "manifest.json");
let manifest;
try { manifest = readJSON(manifestPath); } catch { die("no manifest at " + manifestPath); }

// ---- --check (public) ------------------------------------------------------------------------------
if (check) {
  let bundle; try { bundle = readJSON(check); } catch { die("no proof bundle at " + check); }
  const cpFrom = bundle.from_seq;

  if (bundle.block_keys) {                                          // drop-feed: independent per-block keys
    const seqs = Object.keys(bundle.block_keys).map(Number).sort((a, b) => a - b);
    for (const s of seqs) {
      const kb = bundle.block_keys[String(s)];
      if (manifest.entries[s].ratchet_pub !== "sha256:" + (await ratchetPub(kb))) die(`revealed key fails at seq ${s} (commitment mismatch)`);
      await decBlock(kb, new Uint8Array(readFileSync(join(inbox, manifest.entries[s].block))));  // must be readable
    }
    log(`OK: proof verifies ${seqs.length} drop block(s) against the signed manifest`);
    console.log("proven"); process.exit(0);
  }

  let kk = bundle.checkpoint_key;                                   // ratchet checkpoint
  const n = manifest.entries.length;
  for (let s = cpFrom; s < n; s++) {
    if (manifest.entries[s].ratchet_pub !== "sha256:" + (await ratchetPub(kk))) die(`checkpoint fails at seq ${s} (ratchet_pub mismatch)`);
    await decBlock(kk, new Uint8Array(readFileSync(join(inbox, manifest.entries[s].block))));
    kk = await ratchetNext(kk);
  }
  log(`OK: proof verifies blocks ${cpFrom}..${n - 1} against the signed manifest`);
  console.log("proven"); process.exit(0);
}

// ---- --from (owner) --------------------------------------------------------------------------------
if (!from) die("specify --from N or --check FILE");
from = Number(from);
const identity = readIdentity();
mkdirSync(join(dir, "reports"), { recursive: true });
const bundlePath = join(dir, "reports", `proof-${source}-from-${from}.json`);

if (manifest.entries[from] && typeof manifest.entries[from].key === "string" && manifest.entries[from].key.length > 0) {
  // drop feed: reveal each block's own Kb (age-wrapped) for seq >= from
  const n = manifest.entries.length, blockKeys = {};
  for (let s = from; s < n; s++) {
    const kf = manifest.entries[s].key;
    if (!kf) die(`mixed feed: entry ${s} has no key file`);
    blockKeys[String(s)] = dec.decode(await ageOpen(identity, new Uint8Array(readFileSync(join(inbox, kf))))).trim();
  }
  writeFileSync(bundlePath, JSON.stringify({
    source, from_seq: from, block_keys: blockKeys, manifest_digest: manifest.head.digest,
    note: "Publish this to prove the named drop blocks. Anyone: bin/prove --check this-file. Blocks are independent; unnamed blocks stay sealed.",
  }, null, 2) + "\n");
  log(`wrote ${bundlePath} (publishing it discloses blocks ${from}.. ; each key opens ONLY its own block)`);
  console.log(bundlePath); process.exit(0);
}

// ratchet feed: unwrap the seed, walk the ratchet forward to the checkpoint
let k;
try { k = dec.decode(await ageOpen(identity, new Uint8Array(readFileSync(join(inbox, "seed.age"))))).trim(); }
catch (e) { die("could not unwrap seed.age (wrong identity?): " + e.message); }
for (let i = 0; i < from; i++) k = await ratchetNext(k);
writeFileSync(bundlePath, JSON.stringify({
  source, from_seq: from, checkpoint_key: k, manifest_digest: manifest.head.digest,
  note: "Publish this to prove blocks seq>=from_seq. Anyone: bin/prove --check this-file.",
}, null, 2) + "\n");
log(`wrote ${bundlePath} (publishing it discloses blocks ${from}.. ; earlier blocks stay sealed)`);
console.log(bundlePath);

function readIdentity() {
  if (process.env.DP_IDENTITY_FILE) return readFileSync(process.env.DP_IDENTITY_FILE, "utf8").match(/AGE-SECRET-KEY-1[0-9A-Z]+/i)[0];
  if (process.env.PILE_AGE_IDENTITY) return process.env.PILE_AGE_IDENTITY.trim();
  die("no identity (set PILE_AGE_IDENTITY or DP_IDENTITY_FILE)");
}
