#!/usr/bin/env node
// data-pile/bin/pile-ask.mjs — reserve an ASK on a stood-up pile, the offline-origin port (pure fs,
// no shell, no jq, no network), the way pile-poll.mjs ports pile-poll. An ask is the OTHER anchor a
// pile can wear: where a poll is an anecdote WITH prefab answers (a solicitation), an ask is an
// anecdote WITHOUT them — "here is a thing; do you need this? citation required." It is the case
// bin/pile-poll's own invariant points at: "For an unsolicited statement, use an anecdote, not a poll."
//
//   pile-poll  -> data-pile.poll-anchor/v1  (prefab options => a SOLICITATION; replies are answers)
//   pile-ask   -> data-pile.ask-anchor/v1   (an object reference, NO options; replies are citations)
//
// The anchor is the SHOWN copy, NOT the governing rule. The governing constitution is OPEN
// ("citation required": admits anything, auto-rejects nothing, but keeps the vouch/origin stamp),
// authored on the Tell at _data/constitutions/<pile>/<ask>.json; `governed_by` records where.
// `qr:null` is the slot minted at signing (declares the ask shareable). See docs/anchored-piles.md.
//
//   pile-ask.mjs --dir PATH --ask ASK
//                [--url URL]        the object being asked about (anecdote `to.url`)
//                [--kind KIND]      object kind (default: url when --url given)
//                [--text TEXT]      the unsolicited statement (anecdote body[0])
//                [--guidance TEXT] [--round R] [--out PATH|-]
//   An ask must point at SOMETHING: give --url or --text (or both). It carries NO prefab answers.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";

const die = (m) => { process.stderr.write("data-pile: " + m + "\n"); process.exit(1); };
const log = (m) => process.stderr.write("data-pile: " + m + "\n");

const [, ...rest] = process.argv.slice(1);
let dir = "", ask = "", url = "", kind = "", text = "", guidance = "", round = "1", out = "";
for (let i = 0; i < rest.length; i++) {
  const a = rest[i];
  if (a === "--dir") dir = rest[++i];
  else if (a === "--ask") ask = rest[++i];
  else if (a === "--url") url = rest[++i];
  else if (a === "--kind") kind = rest[++i];
  else if (a === "--text") text = rest[++i];
  else if (a === "--guidance") guidance = rest[++i];
  else if (a === "--round") round = rest[++i];
  else if (a === "--out") out = rest[++i];
  else if (a === "--opts")
    die("an ask carries no prefab answers — a prefab answer is what makes a payload a SOLICITATION (a poll). Use bin/pile-poll for that.");
  else die("pile-ask: unknown arg: " + a);
}
if (!dir || !ask)
  die("usage: bin/pile-ask.mjs --dir PATH --ask ASK [--url URL] [--kind KIND] [--text TEXT] [--guidance G] [--round R] [--out PATH|-]");
if (!/^[a-z0-9][a-z0-9-]*$/.test(ask)) die("pile-ask: --ask must be a lowercase slug (it is a path segment)");

// THE INVARIANT (inverse of the poll's): an ask points at a thing but never prescribes the answer.
if (!url && !text)
  die("an ask must point at SOMETHING — give --url (the object) or --text (the statement). An ask with neither points at nothing.");

// --dir must be a pile checkout with a filled identity — the ask attaches to a REAL, stood-up tank.
let y;
try { y = readFileSync(join(dir, "pile.yml"), "utf8"); } catch { die(`pile-ask: ${dir} has no pile.yml (run bin/pile-new first?)`); }
const pile = (y.match(/^id: "(.*)"/m) || [])[1] || "";
if (!pile) die(`pile-ask: ${dir}/pile.yml has no id — stand the pile up first (bin/pile-new fill)`);

if (!guidance) guidance = "Cite this, or add what you can — an open ask: anything abides, nothing is auto-rejected.";

// The SHOWN anchor. `intent:"ask"` selects how replies read (citations, not answers). `governed_by`
// names where the OPEN rule lives (the Tell); `qr:null` is the reserved slot minted at signing.
const to = url ? { kind: kind || "url", url } : null;
const roundVal = /^[0-9]+$/.test(round) ? Number(round) : round;
const anchor = {
  schema: "data-pile.ask-anchor/v1", pile, ask, shown: true,
  intent: "ask", to, text, guidance,
  round: roundVal, qr: null,
  governed_by: `tell:_data/constitutions/${pile}/${ask}.json`,
};
const body = JSON.stringify(anchor, null, 2) + "\n";

if (out === "-") { process.stdout.write(body); process.exit(0); }
const dest = out || join(dir, "asks", `${ask}.json`);
mkdirSync(dirname(dest), { recursive: true });
writeFileSync(dest, body);
log(`reserved ask '${ask}' on pile '${pile}' -> ${dest} (shown copy; qr slot reserved)`);
process.stderr.write(`  the RULE lives on the Tell as an OPEN constitution (this anchor is only what's shown):\n    author _data/constitutions/${pile}/${ask}.json (citation required: admits anything, auto-rejects nothing)\n`);
process.stderr.write(`  at SIGNING, mint the QR into the reserved slot (declares the ask shareable).\n`);
