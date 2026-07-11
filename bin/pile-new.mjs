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
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { mintAgeIdentity } from "./age-keygen.mjs";

const die = (m) => { process.stderr.write("data-pile: " + m + "\n"); process.exit(1); };
const log = (m) => process.stderr.write("data-pile: " + m + "\n");

const [cmd, ...rest] = process.argv.slice(2);
let id = "", scope = "", recipient = "", keygen = false, owner = "", name = "", dir = "";
let template = "FCCN-ANTIBODY/data-pile", sourceUrl = "", signer = "", provisioner = "", priv = false;
for (let i = 0; i < rest.length; i++) {
  const a = rest[i];
  if (a === "--id") id = rest[++i];
  else if (a === "--scope") scope = rest[++i];
  else if (a === "--recipient") recipient = rest[++i];
  else if (a === "--keygen") keygen = true;
  else if (a === "--owner") owner = rest[++i];
  else if (a === "--name") name = rest[++i];
  else if (a === "--dir") dir = rest[++i];
  else if (a === "--template") template = rest[++i];
  else if (a === "--source-url") sourceUrl = rest[++i];
  else if (a === "--signer") signer = rest[++i];
  else if (a === "--provisioner") provisioner = rest[++i];
  else if (a === "--private") priv = true;
  else die("pile-new: unknown arg: " + a);
}

if (!["plan", "fill"].includes(cmd)) die("usage: bin/pile-new.mjs plan|fill (see header; `create` stays networked/bash)");
if (!id || !scope) die("pile-new: --id and --scope are required");
if (!/^[a-z0-9][a-z0-9-]*$/.test(id)) die("pile-new: --id must be a lowercase slug");
if (id.length > 63) die("pile-new: --id must fit a DNS label (63 chars max) — it doubles as the pile's Floor hostname");
if (!name) name = id;
if (keygen && recipient) die("pile-new: --keygen and --recipient are exclusive");
if (!keygen && !recipient) die("pile-new: choose --recipient (Mobile: mint on-device, age-mint.mjs) or --keygen (Computer)");
if (provisioner && keygen) die("pile-new: a provisioner never touches an identity — mint on the OWNER's device and pass --recipient");
if (recipient && !/^age1[ac-hj-np-z02-9]{58}$/.test(recipient)) die("pile-new: --recipient is not an age recipient (age1…, 62 chars, bech32)");
const repoSlug = (owner ? owner + "/" : "") + name;

function plan() {
  process.stdout.write(
`pile-new plan
  repo        ${repoSlug || "<owner>/" + name}  (from template ${template}${priv ? ", private" : ""})
  pile.yml    id=${id} scope=${scope}${sourceUrl ? " sources[0].url=" + sourceUrl : ""}${signer ? " sources[0].signer=" + signer : ""}
  identity    ${keygen
      ? "COMPUTER: age-keygen on this machine -> new repo secret PILE_AGE_IDENTITY (never printed)"
      : `MOBILE: recipient supplied (${recipient.slice(0, 12)}...) — no identity exists host-side`}
  attestation ${provisioner ? `provisioner: ${provisioner} (stamped into pile.yml)` : "none (self-service)"}
  next        dispatch the new repo's handshake workflow (or paste the printed entry onto the Tell)
`);
}

// mutate a pile.yml line (first match only for the indented sources fields, mirroring bash's `0,/re/s`)
const setLine = (text, re, line) => text.replace(re, line);

async function fill() {
  if (!dir) die("pile-new fill: --dir is required");
  const pilePath = join(dir, "pile.yml");
  let y;
  try { y = readFileSync(pilePath, "utf8"); } catch { die(`pile-new fill: ${dir} has no pile.yml (not a data-pile checkout?)`); }

  let recip = recipient;
  if (keygen) {
    const minted = await mintAgeIdentity();                       // ON-DEVICE — the age battery, no binary
    recip = minted.recipient;
    // Hold the identity OUTSIDE the checkout (custody rule: the private identity never lands in the repo),
    // mirroring bash's mktemp handoff. The offline origin moves it to its held-store; create installs a secret.
    const out = process.env.PILE_NEW_IDENTITY_OUT || join(mkdtempSync(join(tmpdir(), "pile-id-")), "identity.txt");
    writeFileSync(out, minted.identity + "\n", { mode: 0o600 });   // held, never printed
    log(`minted identity on-device -> held at ${out} (recipient ${recip.slice(0, 12)}...; identity never printed, never in the checkout)`);
  }

  y = setLine(y, /^id: .*$/m, `id: "${id}"`);
  y = setLine(y, /^scope: .*$/m, `scope: "${scope}"`);
  y = setLine(y, /^age_recipient: .*$/m, `age_recipient: "${recip}"`);
  if (repoSlug && owner) y = setLine(y, /^repo_url: .*$/m, `repo_url: "https://github.com/${repoSlug}"`);
  if (sourceUrl) y = setLine(y, /^ {4}url: .*$/m, `    url: "${sourceUrl}"`);        // first occurrence
  if (signer) y = setLine(y, /^ {4}signer: .*$/m, `    signer: "${signer}"`);        // first occurrence

  if (provisioner && !/^provisioner:/m.test(y)) {
    y += `\n# ATTESTATION (CONTRACT.md -> "The provisioner attestation", spec-or-attested): this pile was
# stood up by a provisioner, not hand-built by its owner. Anything talking to a managed pile can
# read who managed it and what they speak. The provisioner held the CREATE credential only --
# never the age identity.
provisioner: "${provisioner}"
provisioner_spec: "data-pile/pile-new/v1"
`;
  }
  writeFileSync(pilePath, y);
  mkdirSync(join(dir, "keys"), { recursive: true });
  writeFileSync(join(dir, "keys", "pile.age.pub"), recip + "\n");
  log(`filled ${dir} (id=${id} scope=${scope} recipient=${recip.slice(0, 12)}...)`);
}

if (cmd === "plan") plan();
else await fill();
