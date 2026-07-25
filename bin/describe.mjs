#!/usr/bin/env node
// data-pile/bin/describe.mjs — CRUNCH THE PILE'S SELF-DESCRIPTION: the dated descriptor snapshot this
// pile's bottle serves over the `describe` op (anecdote.channel docs/decisions.md D7,
// composer/describe-op.mjs). The skimmable answer to "what is this pile for, and is anything in it?" —
// what a picker, a shelf, or the journal's chooser reads without connecting deeper.
//
// RING ONE ONLY, by design (the D7 custody split): everything here derives from the pile's PUBLIC
// surface — the SHOWN anchors (polls/*.json questions, asks/*.json leads — docs/anchored-piles.md) and
// the signed manifest's counts. Nothing requiring DECRYPTION rides: answer contents and distributions
// are owner-side work, and publishing them is a disclosure act in the bin/prove family — a later,
// deliberate layer, never this tool. Nothing runs in the background: the owner re-crunches when they
// choose, and `as_of` makes the chosen staleness visible. An empty pile crunches to zero counts —
// "nothing here yet, as of <when>" is a statement, not an absence.
//
//   bin/describe.mjs [--dir PATH] [--now ISO] [--out PATH|-]
//     --dir   pile checkout (default .)
//     --now   pin the snapshot time (deterministic builds/tests; default: now)
//     --out   write path (default <dir>/reports/describe.json), or - for stdout
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";

const die = (m) => { process.stderr.write("data-pile: " + m + "\n"); process.exit(1); };
const log = (m) => process.stderr.write("data-pile: " + m + "\n");

let dir = ".", now = "", out = "";
const rest = process.argv.slice(2);
for (let i = 0; i < rest.length; i++) {
  const a = rest[i];
  if (a === "--dir") dir = rest[++i];
  else if (a === "--now") now = rest[++i];
  else if (a === "--out") out = rest[++i];
  else die("describe: unknown arg: " + a);
}

let y;
try { y = readFileSync(join(dir, "pile.yml"), "utf8"); } catch { die(`describe: ${dir} has no pile.yml (not a pile checkout)`); }
const pile = (y.match(/^id: "(.*)"/m) || [])[1] || "";
if (!pile) die(`describe: ${dir}/pile.yml has no id — stand the pile up first (bin/pile-new fill)`);

// The SHOWN anchors — the pile's skimmable content, verbatim from the public surface. Unshaped files
// are dropped, not repaired (the floor-vault rule).
const anchors = (sub, schema) => {
  let names = [];
  try { names = readdirSync(join(dir, sub)).filter((f) => f.endsWith(".json")).sort(); } catch { return []; }
  const outList = [];
  for (const f of names) {
    try {
      const a = JSON.parse(readFileSync(join(dir, sub, f), "utf8"));
      if (a && a.schema === schema) outList.push(a);
    } catch { /* unshaped — dropped */ }
  }
  return outList;
};
const polls = anchors("polls", "data-pile.poll-anchor/v1");
const asks = anchors("asks", "data-pile.ask-anchor/v1");

// The sealed tank, counted from the signed manifest — how much arrived, never what it says.
let sealed = 0, lastDelivery = null;
try {
  const manifest = JSON.parse(readFileSync(join(dir, "inbox", "manifest.json"), "utf8"));
  if (Array.isArray(manifest.entries)) {
    sealed = manifest.entries.length;
    const last = manifest.entries[manifest.entries.length - 1];
    lastDelivery = (last && last.created_at) || null;
  }
} catch { /* no feed yet — a young pile */ }

const descriptor = {
  schema: "anecdote.describe/v1",
  as_of: now || new Date().toISOString(),
  kind: "data-pile",
  pile,
  questions: polls.map((p) => ({ poll: p.poll, text: p.text, type: p.type, options: p.options || [] })),
  asks: asks.map((a) => ({ ask: a.ask, text: a.text || "", to: a.to || null })),
  counts: { questions: polls.length, asks: asks.length, sealed_blocks: sealed },
  ...(lastDelivery ? { last_delivery: lastDelivery } : {}),
};

const body = JSON.stringify(descriptor, null, 2) + "\n";
if (out === "-") { process.stdout.write(body); process.exit(0); }
const dest = out || join(dir, "reports", "describe.json");
mkdirSync(dirname(dest), { recursive: true });
writeFileSync(dest, body);
log(`crunched ${pile}'s descriptor -> ${dest} (${polls.length} question(s), ${asks.length} ask(s), ${sealed} sealed block(s), as of ${descriptor.as_of})`);
