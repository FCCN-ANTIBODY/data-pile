// test/feed-open.test.mjs — the room's consumer core against the REAL bash producer: make-fixtures.sh
// (age + openssl + jq, the reference for what a Tell delivers) builds a signed chain, and feed-open.mjs
// must agree with it byte-for-byte — digest, signature, chain walk, ratchet, and plaintext equal to
// bin/decrypt's own output. Then the refusals: a tampered block, a broken chain, a wrong identity, and
// a forged signer all refuse with a reason. The ssh leg injects a pinned-signer verifier built on
// anecdote.channel's composer/ssh-sig.mjs when a sibling checkout is present (ANECDOTE_REPO), and
// degrades to the allowUnsigned posture — stated, never silent — when it isn't.
// Run: node test/feed-open.test.mjs   (needs age + openssl + jq, like the bash suite)
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync, mkdtempSync, rmSync, existsSync, writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { join, dirname } from "node:path";
import os from "node:os";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const { verifyFeed, openFeed, canonicalEntries } = await import(pathToFileURL(join(root, "bin", "feed-open.mjs")));

let fails = 0;
const ok = (c, m) => { if (!c) { console.error("FAIL: " + m); fails++; } else console.log("  ok: " + m); };
const sh = (cmd, args, opts = {}) => execFileSync(cmd, args, { encoding: "utf8", ...opts });

for (const tool of ["age", "age-keygen", "openssl", "jq"]) {
  try { sh("which", [tool]); } catch { console.log(`skip: ${tool} not available for the fixture producer`); process.exit(0); }
}

const work = mkdtempSync(join(os.tmpdir(), "feed-open-"));
try {
  // The owner's identity + the producer's chain (the real bash reference).
  sh("age-keygen", ["-o", join(work, "id.txt")], { stdio: ["ignore", "ignore", "ignore"] });
  const identity = readFileSync(join(work, "id.txt"), "utf8").split("\n").find((l) => l.startsWith("AGE-SECRET-KEY-"));
  const recipient = sh("age-keygen", ["-y", join(work, "id.txt")]).trim();

  let signers = null;
  const haveSsh = (() => { try { sh("which", ["ssh-keygen"]); return true; } catch { return false; } })();
  if (haveSsh) {
    sh("ssh-keygen", ["-t", "ed25519", "-N", "", "-C", "tell-signer", "-f", join(work, "sign")], { stdio: ["ignore", "ignore", "ignore"] });
    signers = readFileSync(join(work, "sign.pub"), "utf8").trim();
  }
  sh("bash", [join(root, "test", "make-fixtures.sh"), join(work, "feed"), recipient, "3", ...(haveSsh ? [join(work, "sign")] : [])],
     { stdio: ["ignore", "ignore", "ignore"] });

  const inbox = join(work, "feed", "inbox");
  const manifest = JSON.parse(readFileSync(join(inbox, "manifest.json"), "utf8"));
  const blocks = {};
  for (const f of readdirSync(inbox)) if (f.endsWith(".enc")) blocks[f] = new Uint8Array(readFileSync(join(inbox, f)));
  const seedAge = new Uint8Array(readFileSync(join(inbox, "seed.age")));

  // The digest recipe agrees with jq -cS.
  const jqCanon = sh("jq", ["-cS", ".entries", join(inbox, "manifest.json")]).replace(/\n$/, "");
  ok(canonicalEntries(manifest.entries) === jqCanon, "canonicalEntries == jq -cS .entries, byte for byte");

  // The signature seam: a pinned-signer verifier on anecdote's ssh-sig, when the sibling is present.
  const anecdote = process.env.ANECDOTE_REPO || join(root, "..", "anecdote.channel");
  let verifySignature = null;
  if (haveSsh && existsSync(join(anecdote, "composer", "ssh-sig.mjs"))) {
    const sshSig = await import(pathToFileURL(join(anecdote, "composer", "ssh-sig.mjs")));
    const rawPub = sshSig.rawFromPublic(signers);
    verifySignature = ({ message, armored, namespace }) => sshSig.verify(message, armored, { namespace, rawPub });
  }

  // verify + open, and cross-check the plaintext with bin/decrypt itself.
  const v = await verifyFeed({ manifest, blocks, verifySignature, allowUnsigned: !verifySignature });
  ok(v.ok === true && v.entries === 3, "verifyFeed passes the real producer's chain: " + JSON.stringify(v.signed));
  if (verifySignature) ok(v.signed && v.signed.by, "…with the head signature verified in JS against the pinned signer");
  else console.log("  note: signature leg skipped (" + (haveSsh ? "no anecdote.channel checkout" : "no ssh-keygen") + ") — allowUnsigned stated");

  const opened = await openFeed({ manifest, blocks, seedAge, identity });
  ok(opened.records.length === 3, "openFeed decrypts every block through the ratchet");
  const bashOut = mkdtempSync(join(os.tmpdir(), "feed-open-bash-"));
  sh("bash", [join(root, "bin", "decrypt"), "--dir", join(work, "feed"), "--all", "--out", bashOut],
     { env: { ...process.env, PILE_AGE_IDENTITY: identity }, stdio: ["ignore", "ignore", "ignore"] });
  const same = opened.records.every((r) => r.text === readFileSync(join(bashOut, r.seq + ".txt"), "utf8"));
  ok(same, "every plaintext equals bin/decrypt's own output — the room reads what the owner reads");
  rmSync(bashOut, { recursive: true, force: true });

  // The refusals.
  const flipped = { ...blocks, [manifest.entries[1].block]: (() => { const b = new Uint8Array(blocks[manifest.entries[1].block]); b[0] ^= 1; return b; })() };
  const tam = await verifyFeed({ manifest, blocks: flipped, allowUnsigned: true });
  ok(!tam.ok && /tampered at seq 1/.test(tam.reason), "a flipped ciphertext byte refuses: " + tam.reason);

  const reordered = JSON.parse(JSON.stringify(manifest));
  reordered.entries.reverse();
  const chain = await verifyFeed({ manifest: reordered, blocks, allowUnsigned: true });
  ok(!chain.ok, "a reordered chain refuses: " + chain.reason);

  sh("age-keygen", ["-o", join(work, "other.txt")], { stdio: ["ignore", "ignore", "ignore"] });
  const stranger = readFileSync(join(work, "other.txt"), "utf8").split("\n").find((l) => l.startsWith("AGE-SECRET-KEY-"));
  const wrong = await openFeed({ manifest, blocks, seedAge, identity: stranger }).then(() => null, (e) => e.message);
  ok(wrong !== null, "a stranger's identity cannot unwrap the seed: " + wrong);

  if (verifySignature) {
    const doctored = JSON.parse(JSON.stringify(manifest));
    doctored.entries[0].created_at = "1999-01-01T00:00:00Z";
    doctored.head.digest = (await import("node:crypto")).createHash("sha256").update(canonicalEntries(doctored.entries)).digest("hex");
    const forged = await verifyFeed({ manifest: doctored, blocks, verifySignature });
    ok(!forged.ok && /does NOT verify/.test(forged.reason), "a re-digested (unsigned) history refuses against the signer: " + forged.reason);
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}

if (fails) { console.error(`\n${fails} FAILED`); process.exit(1); }
console.log("\nall feed-open tests passed (the room's consumer core agrees with the bash producer)");
