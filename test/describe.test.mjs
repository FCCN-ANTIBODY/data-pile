// Unit: bin/describe.mjs — the ring-one crunch (D7): the descriptor derives ONLY from the public
// surface (shown anchors + signed-manifest counts), empty is a dated statement, unshaped anchor files
// drop, and — when the antidote sibling is present — the crunch's empty shape matches what antidote
// stamps at inception (the two ends of the pile's life agree). Run: node test/describe.test.mjs
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync, existsSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { join, dirname } from "node:path";
import os from "node:os";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
let fails = 0;
const ok = (c, m) => { if (!c) { console.error("FAIL: " + m); fails++; } else console.log("  ok: " + m); };
const node = (bin, args) => execFileSync(process.execPath, [join(root, "bin", bin), ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });

const work = mkdtempSync(join(os.tmpdir(), "describe-"));
try {
  // A stood-up pile with no content yet.
  mkdirSync(join(work, "pile"), { recursive: true });
  writeFileSync(join(work, "pile", "pile.yml"), 'id: "parks-2026"\nscope: "riverbend"\n');

  // 1 — empty is a dated statement.
  const empty = JSON.parse(node("describe.mjs", ["--dir", join(work, "pile"), "--now", "2026-07-25T00:00:00Z", "--out", "-"]));
  ok(empty.schema === "anecdote.describe/v1" && empty.kind === "data-pile" && empty.pile === "parks-2026",
     "a young pile describes itself: describe/v1, kind data-pile");
  ok(empty.as_of === "2026-07-25T00:00:00Z", "the snapshot time is pinned, staleness visible");
  ok(empty.counts.questions === 0 && empty.counts.asks === 0 && empty.counts.sealed_blocks === 0
     && empty.questions.length === 0 && empty.asks.length === 0,
     "'nothing here yet' — zero counts, stated");

  // 2 — anchors surface verbatim: one poll (solicitation) and one ask (citation-required lead).
  node("pile-poll.mjs", ["--dir", join(work, "pile"), "--poll", "north-meadow",
    "--question", "What should the north meadow become?", "--opts", "a dog park,a wetland"]);
  node("pile-ask.mjs", ["--dir", join(work, "pile"), "--ask", "east-bank-flooding",
    "--url", "https://example.org/photo-41.jpg", "--text", "Any account of flooding on the east bank."]);
  writeFileSync(join(work, "pile", "polls", "junk.json"), "{ not json");   // unshaped: dropped, not repaired
  const full = JSON.parse(node("describe.mjs", ["--dir", join(work, "pile"), "--now", "2026-07-25T01:00:00Z", "--out", "-"]));
  ok(full.counts.questions === 1 && full.questions[0].poll === "north-meadow"
     && full.questions[0].options.join("|") === "a dog park|a wetland",
     "the poll anchor is skimmable: question + suggestions");
  ok(full.counts.asks === 1 && full.asks[0].ask === "east-bank-flooding"
     && full.asks[0].to.url === "https://example.org/photo-41.jpg",
     "the ask anchor is skimmable: the lead and its object reference");
  ok(full.counts.sealed_blocks === 0, "no feed yet — sealed count honest");

  // 3 — the sealed tank is COUNTED, never read (needs the fixture tools; skips without them).
  let haveTools = true;
  for (const t of ["age", "age-keygen", "openssl", "jq"]) {
    try { execFileSync("which", [t], { stdio: "ignore" }); } catch { haveTools = false; }
  }
  if (haveTools) {
    execFileSync("age-keygen", ["-o", join(work, "id.txt")], { stdio: "ignore" });
    const recip = execFileSync("age-keygen", ["-y", join(work, "id.txt")], { encoding: "utf8" }).trim();
    execFileSync("bash", [join(root, "test", "make-fixtures.sh"), join(work, "pile"), recip, "2"], { stdio: "ignore" });
    const fed = JSON.parse(node("describe.mjs", ["--dir", join(work, "pile"), "--now", "2026-07-25T02:00:00Z", "--out", "-"]));
    ok(fed.counts.sealed_blocks === 2 && typeof fed.last_delivery === "string",
       "two sealed blocks counted from the signed manifest, last delivery dated — contents never touched");
    ok(!JSON.stringify(fed).includes("digest block seq"), "…and no plaintext of any block appears in the snapshot");
  } else {
    console.log("  note: sealed-count leg skipped (fixture tools unavailable)");
  }

  // 4 — the two ends of the pile's life agree: antidote's inception stamp and this crunch produce the
  // same empty shape (guarded on the sibling checkout).
  const antidote = process.env.ANTIDOTE_REPO || join(root, "..", "antidote");
  if (existsSync(join(antidote, "provision", "pile.mjs"))) {
    const { emptyPileDescriptor } = await import(pathToFileURL(join(antidote, "provision", "pile.mjs")));
    const stamped = emptyPileDescriptor({ id: "parks-2026", now: "2026-07-25T00:00:00Z" });
    const shape = (d) => JSON.stringify({ schema: d.schema, kind: d.kind, keys: Object.keys(d.counts).sort() });
    ok(shape(stamped) === shape(empty),
       "antidote's inception stamp and the crunch agree on the empty shape (schema, kind, count keys)");
  } else {
    console.log("  note: antidote cross-check skipped (no sibling checkout; set ANTIDOTE_REPO)");
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}

if (fails) { console.error(`\n${fails} FAILED`); process.exit(1); }
console.log("\nok: describe — the pile puts forward what it is for, from its public surface alone");
