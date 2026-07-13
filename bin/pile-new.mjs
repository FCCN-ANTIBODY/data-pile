#!/usr/bin/env node
// data-pile/bin/pile-new.mjs — the on-device port of bin/pile-new's PURE half (plan + fill). Stand up a new
// data-pile without shell and without GitHub: mint the pile's identity ON THE DEVICE (age-keygen.mjs, the
// age battery — no age-keygen binary, no host-side identity ever) and fill a checkout's pile.yml + keys/.
// The networked `create` (gh api generate + gh secret) stays out of here on purpose — the offline origin
// gets a host-agnostic checkout it hands to git-enough for ANY host (see the fork/copy/clone scenarios).
//
//   pile-new.mjs plan  --id ID --scope SCOPE (--recipient age1… | --keygen) [opts]
//   pile-new.mjs fill  --dir PATH (same args; offline — writes pile.yml + keys/pile.age.pub)
//
// --keygen mints here and holds the identity to PILE_NEW_IDENTITY_OUT (default <dir>/.pile-identity),
// never printed; the recipient (public) goes into pile.yml + keys/pile.age.pub. --provisioner is
// INCOMPATIBLE with --keygen (a provisioner never touches an identity).
//
// fillPile() is the PURE, fs-free core of `fill`: a checkout on disk is one caller, the offline origin
// (git-enough buildRepo over an in-memory file-set) is the other. Both get byte-identical bytes.
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { mintAgeIdentity } from "./age-keygen.mjs";

// Pure, fs-free core of fill. Given the template's pile.yml TEXT and the pile's parameters (recipient
// REQUIRED — minting is the caller's job, being async and secret-bearing), return the filled pile.yml
// text and the keys/pile.age.pub content. Same string transforms as the on-disk fill, so a pile stood up
// from an in-memory file-set (offline origin) is byte-for-byte the one bash/the CLI writes to a checkout.
// Idempotent: a second fill does not double-stamp the provisioner attestation.
export function fillPile(pileYaml, { id, scope, recipient, owner = "", name = "", sourceUrl = "", signer = "", provisioner = "" } = {}) {
  const nm = name || id;
  const repoSlug = (owner ? owner + "/" : "") + nm;
  let y = pileYaml;
  y = y.replace(/^id: .*$/m, `id: "${id}"`);
  y = y.replace(/^scope: .*$/m, `scope: "${scope}"`);
  y = y.replace(/^age_recipient: .*$/m, `age_recipient: "${recipient}"`);
  if (repoSlug && owner) y = y.replace(/^repo_url: .*$/m, `repo_url: "https://github.com/${repoSlug}"`);
  if (sourceUrl) y = y.replace(/^ {4}url: .*$/m, `    url: "${sourceUrl}"`);        // first occurrence
  if (signer) y = y.replace(/^ {4}signer: .*$/m, `    signer: "${signer}"`);         // first occurrence
  if (provisioner && !/^provisioner:/m.test(y)) {
    y += `\n# ATTESTATION (CONTRACT.md -> "The provisioner attestation", spec-or-attested): this pile was
# stood up by a provisioner, not hand-built by its owner. Anything talking to a managed pile can
# read who managed it and what they speak. The provisioner held the CREATE credential only --
# never the age identity.
provisioner: "${provisioner}"
provisioner_spec: "data-pile/pile-new/v1"
`;
  }
  return { pileYaml: y, keyPub: recipient + "\n" };
}

const die = (m) => { process.stderr.write("data-pile: " + m + "\n"); process.exit(1); };
const log = (m) => process.stderr.write("data-pile: " + m + "\n");

// The CLI's argument surface — parsed into a plain object so plan()/fill() read fields, never globals.
function parseArgs(argv) {
  const a = {
    cmd: argv[0], id: "", scope: "", recipient: "", keygen: false, owner: "", name: "", dir: "",
    template: "FCCN-ANTIBODY/data-pile", sourceUrl: "", signer: "", provisioner: "", priv: false,
  };
  const rest = argv.slice(1);
  for (let i = 0; i < rest.length; i++) {
    const x = rest[i];
    if (x === "--id") a.id = rest[++i];
    else if (x === "--scope") a.scope = rest[++i];
    else if (x === "--recipient") a.recipient = rest[++i];
    else if (x === "--keygen") a.keygen = true;
    else if (x === "--owner") a.owner = rest[++i];
    else if (x === "--name") a.name = rest[++i];
    else if (x === "--dir") a.dir = rest[++i];
    else if (x === "--template") a.template = rest[++i];
    else if (x === "--source-url") a.sourceUrl = rest[++i];
    else if (x === "--signer") a.signer = rest[++i];
    else if (x === "--provisioner") a.provisioner = rest[++i];
    else if (x === "--private") a.priv = true;
    else die("pile-new: unknown arg: " + x);
  }
  return a;
}

function validate(a) {
  if (!["plan", "fill"].includes(a.cmd)) die("usage: bin/pile-new.mjs plan|fill (see header; `create` stays networked/bash)");
  if (!a.id || !a.scope) die("pile-new: --id and --scope are required");
  if (!/^[a-z0-9][a-z0-9-]*$/.test(a.id)) die("pile-new: --id must be a lowercase slug");
  if (a.id.length > 63) die("pile-new: --id must fit a DNS label (63 chars max) — it doubles as the pile's Floor hostname");
  if (!a.name) a.name = a.id;
  if (a.keygen && a.recipient) die("pile-new: --keygen and --recipient are exclusive");
  if (!a.keygen && !a.recipient) die("pile-new: choose --recipient (Mobile: mint on-device, age-mint.mjs) or --keygen (Computer)");
  if (a.provisioner && a.keygen) die("pile-new: a provisioner never touches an identity — mint on the OWNER's device and pass --recipient");
  if (a.recipient && !/^age1[ac-hj-np-z02-9]{58}$/.test(a.recipient)) die("pile-new: --recipient is not an age recipient (age1…, 62 chars, bech32)");
  a.repoSlug = (a.owner ? a.owner + "/" : "") + a.name;
}

function plan(a) {
  process.stdout.write(
`pile-new plan
  repo        ${a.repoSlug || "<owner>/" + a.name}  (from template ${a.template}${a.priv ? ", private" : ""})
  pile.yml    id=${a.id} scope=${a.scope}${a.sourceUrl ? " sources[0].url=" + a.sourceUrl : ""}${a.signer ? " sources[0].signer=" + a.signer : ""}
  identity    ${a.keygen
      ? "COMPUTER: age-keygen on this machine -> new repo secret PILE_AGE_IDENTITY (never printed)"
      : `MOBILE: recipient supplied (${a.recipient.slice(0, 12)}...) — no identity exists host-side`}
  attestation ${a.provisioner ? `provisioner: ${a.provisioner} (stamped into pile.yml)` : "none (self-service)"}
  next        dispatch the new repo's handshake workflow (or paste the printed entry onto the Tell)
`);
}

async function fill(a) {
  if (!a.dir) die("pile-new fill: --dir is required");
  const pilePath = join(a.dir, "pile.yml");
  let y;
  try { y = readFileSync(pilePath, "utf8"); } catch { die(`pile-new fill: ${a.dir} has no pile.yml (not a data-pile checkout?)`); }

  let recip = a.recipient;
  if (a.keygen) {
    const minted = await mintAgeIdentity();                       // ON-DEVICE — the age battery, no binary
    recip = minted.recipient;
    // Hold the identity OUTSIDE the checkout (custody rule: the private identity never lands in the repo),
    // mirroring bash's mktemp handoff. The offline origin moves it to its held-store; create installs a secret.
    const out = process.env.PILE_NEW_IDENTITY_OUT || join(mkdtempSync(join(tmpdir(), "pile-id-")), "identity.txt");
    writeFileSync(out, minted.identity + "\n", { mode: 0o600 });   // held, never printed
    log(`minted identity on-device -> held at ${out} (recipient ${recip.slice(0, 12)}...; identity never printed, never in the checkout)`);
  }

  const filled = fillPile(y, { id: a.id, scope: a.scope, recipient: recip, owner: a.owner, name: a.name, sourceUrl: a.sourceUrl, signer: a.signer, provisioner: a.provisioner });
  writeFileSync(pilePath, filled.pileYaml);
  mkdirSync(join(a.dir, "keys"), { recursive: true });
  writeFileSync(join(a.dir, "keys", "pile.age.pub"), filled.keyPub);
  log(`filled ${a.dir} (id=${a.id} scope=${a.scope} recipient=${recip.slice(0, 12)}...)`);
}

async function main() {
  const a = parseArgs(process.argv.slice(2));
  validate(a);
  if (a.cmd === "plan") plan(a);
  else await fill(a);
}

// Run only as a script; stays importable (fillPile) without executing the CLI.
if (import.meta.url === `file://${process.argv[1]}`) main().catch((e) => die(e.message));
