#!/usr/bin/env node
// data-pile/bin/pile-poll.mjs — the on-device port of bin/pile-poll. Reserve a POLL on a stood-up pile
// from the offline origin: no shell, no jq, no network — pure fs, the way pile-new.mjs ports pile-new's
// pure half. "A poll is a data pile with the question attached" (tell.anecdote.channel/docs/
// solicitation.md): pile-new.mjs fills the tank, this attaches the poll's SHOWN anchor to it —
// polls/<poll>.json carrying what a respondent is shown (question, type, options, guidance), with the
// QR slot RESERVED (qr:null) until signing. Minting the QR declares the poll shareable, so it is
// deferred; git-enough pushes the checkout to any host once the offline origin is ready.
//
// The anchor is the SHOWN copy, NOT the governing rule. The Tell governs from its own registry
// (_data/constitutions/<pile>/<poll>.json, authored by tell bin/poll); `governed_by` records where.
// Layering is tell/docs/per-poll-registry.md — Layer 1 governs, the QR is Layer 2.
//
//   pile-poll.mjs --dir PATH --poll POLL --question Q
//                 [--type multichoice|open]  default: multichoice if --opts given, else open
//                 [--opts "A,B,C"]           the prefab answers — their PRESENCE makes it a solicitation
//                 [--guidance TEXT] [--accept-writein] [--round R] [--out PATH|-]
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";

const die = (m) => { process.stderr.write("data-pile: " + m + "\n"); process.exit(1); };
const log = (m) => process.stderr.write("data-pile: " + m + "\n");

const [, ...rest] = process.argv.slice(1);
let dir = "", poll = "", question = "", type = "", opts = "", guidance = "", acceptWritein = false, round = "1", out = "";
for (let i = 0; i < rest.length; i++) {
  const a = rest[i];
  if (a === "--dir") dir = rest[++i];
  else if (a === "--poll") poll = rest[++i];
  else if (a === "--question") question = rest[++i];
  else if (a === "--type") type = rest[++i];
  else if (a === "--opts") opts = rest[++i];
  else if (a === "--guidance") guidance = rest[++i];
  else if (a === "--accept-writein") acceptWritein = true;
  else if (a === "--round") round = rest[++i];
  else if (a === "--out") out = rest[++i];
  else die("pile-poll: unknown arg: " + a);
}
if (!dir || !poll || !question)
  die("usage: bin/pile-poll.mjs --dir PATH --poll POLL --question Q [--type multichoice|open] [--opts CSV] [--guidance G] [--accept-writein] [--round R] [--out PATH|-]");
if (!/^[a-z0-9][a-z0-9-]*$/.test(poll)) die("pile-poll: --poll must be a lowercase slug (it is a path segment)");

// --dir must be a pile checkout with a filled identity — the poll attaches to a REAL, stood-up tank.
let y;
try { y = readFileSync(join(dir, "pile.yml"), "utf8"); } catch { die(`pile-poll: ${dir} has no pile.yml (run bin/pile-new first?)`); }
const pile = (y.match(/^id: "(.*)"/m) || [])[1] || "";
if (!pile) die(`pile-poll: ${dir}/pile.yml has no id — stand the pile up first (bin/pile-new fill)`);

// Default the type from whether prefab answers were supplied: options => a solicitation.
if (!type) type = opts ? "multichoice" : "open";
const options = opts ? opts.split(",").map((o) => o.trim()).filter((o) => o.length) : [];

let aw;
if (type === "multichoice") {
  // THE INVARIANT (shared with tell bin/poll): a poll solicits, and the signal is a prefab answer.
  if (options.length < 1)
    die("a multichoice poll needs at least one prefab answer — a prefab answer is what makes a payload a SOLICITATION (solicitation.md). For an unsolicited statement, use an anecdote, not a poll.");
  aw = acceptWritein;
} else if (type === "open") {
  if (options.length) die(`an open poll carries no prefab options (got ${options.length}) — use --type multichoice for a fixed-answer poll`);
  aw = true;
} else {
  die("pile-poll: unknown --type: " + type + " (expected multichoice|open)");
}

if (!guidance) {
  guidance = type === "multichoice"
    ? "One of the listed options." + (aw ? "" : " Write-ins are not counted for this poll.")
    : "An open answer; the judge decides what abides.";
}

// The SHOWN anchor. `governed_by` names where the RULE lives (the Tell); `qr:null` is the reserved slot
// minted at signing. `shown:true` marks this the display copy, never the governing constitution.
const roundVal = /^[0-9]+$/.test(round) ? Number(round) : round;
const anchor = {
  schema: "data-pile.poll-anchor/v1", pile, poll, shown: true,
  type, text: question, options, accept_writein: aw, guidance,
  round: roundVal, qr: null,
  governed_by: `tell:_data/constitutions/${pile}/${poll}.json`,
};
const text = JSON.stringify(anchor, null, 2) + "\n";

if (out === "-") { process.stdout.write(text); process.exit(0); }
const dest = out || join(dir, "polls", `${poll}.json`);
mkdirSync(dirname(dest), { recursive: true });
writeFileSync(dest, text);
log(`reserved poll '${poll}' on pile '${pile}' -> ${dest} (shown copy; qr slot reserved)`);
process.stderr.write(`  the RULE is authored on the Tell (this anchor is only what's shown):\n    tell bin/poll --pile ${pile} --poll ${poll} --type ${type} --question "${question}"${opts ? ` --opts "${opts}"` : ""}\n`);
process.stderr.write(`  at SIGNING, mint the QR into the reserved slot (declares the poll shareable):\n    tell bin/qr --pile ${pile} --poll ${poll} --round ${round}${opts ? ` --opts "${opts}"` : ""} --signkey <key>\n`);
