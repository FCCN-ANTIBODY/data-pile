// The claim — "crack the glowstick". Two things are worth proving mechanically: that an unclaimed
// pile genuinely cannot hold anything (inert by absence, not by policy), and that the artifact
// leaving the claimant's device cannot contain the identity. Run: node test/claim.test.mjs
import { execFileSync } from "node:child_process";
import { readFileSync, mkdtempSync, writeFileSync, rmSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { claimRequest, SCHEMA } from "../bin/claim-request.mjs";
import { mintAgeIdentity } from "../bin/age-keygen.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
let pass = 0, fail = 0;
const ok = (n, c) => c ? pass++ : (fail++, console.log("  FAIL: " + n));

const REC = "age1586sf5fgqv0cxt2xgyyl4p2s6f7x4eaneg28rhkpaj4sm8e5x92qtqwy8l";

console.log("the outbound claim carries the recipient and nothing else");
const r = claimRequest({ recipient: REC, repoSlug: "acme/tank", origin: "https://acme.github.io/tank", rpId: "acme.github.io", at: "2026-09-02T00:00:00Z" });
ok("carries the recipient", r.body.includes(REC) && r.url.includes(encodeURIComponent(REC)));
ok("names the schema", r.body.includes(SCHEMA));
ok("gives the apply command", r.body.includes("bin/pile-new fill --dir . --recipient " + REC));
ok("targets the repo's issue form", r.url.startsWith("https://github.com/acme/tank/issues/new?"));
ok("falls back to plain text with no repo", claimRequest({ recipient: REC }).url.startsWith("data:text/plain"));

console.log("the identity structurally cannot leave");
// A real minted pair: the identity is not an accepted input, so passing it must be REFUSED
// rather than silently ignored — a caller who confuses the halves needs to be told.
const pair = await mintAgeIdentity();
ok("a freshly minted recipient is accepted", !!claimRequest({ recipient: pair.recipient }).body.includes(pair.recipient));
let threw = false;
try { claimRequest({ recipient: pair.recipient, repoSlug: pair.identity }); } catch { threw = true; }
ok("an identity smuggled into ANY field is refused", threw);
threw = false;
try { claimRequest({ recipient: pair.identity }); } catch { threw = true; }
ok("passing the identity as the recipient is refused", threw);
// Belt and braces: the built artifact never contains the secret prefix under any input.
const built = claimRequest({ recipient: pair.recipient, repoSlug: "a/b", origin: "https://x", rpId: "x" });
ok("no AGE-SECRET-KEY appears in the artifact", !/AGE-SECRET-KEY/i.test(built.body + built.url));

console.log("malformed recipients are refused rather than committed");
for (const bad of ["", "age1short", "not-a-key", "AGE-SECRET-KEY-1ABC", null]) {
  let t = false; try { claimRequest({ recipient: bad }); } catch { t = true; }
  ok("refuses " + JSON.stringify(bad), t);
}

console.log("the page itself phones nowhere");
const page = readFileSync(join(root, "claim.html"), "utf8");
const fetches = [...page.matchAll(/fetch\(\s*["'`]([^"'`]+)/g)].map((m) => m[1]);
ok("its only fetch is its own pile.yml", fetches.length === 1 && fetches[0] === "./pile.yml");
ok("loads no third-party script", !/<script[^>]+src=/.test(page));
ok("imports only vendored modules", [...page.matchAll(/from\s+"([^"]+)"/g)].every((m) => m[1].startsWith("./")));
// The recipient is public, but a page that POSTed anywhere would be a different promise entirely.
ok("submits no form and posts nothing", !/method\s*=\s*["']post/i.test(page) && !/XMLHttpRequest|navigator\.sendBeacon/.test(page));

console.log("an unclaimed pile is inert — by absence, not by policy");
const dir = mkdtempSync(join(tmpdir(), "claim-"));
writeFileSync(join(dir, "pile.yml"), readFileSync(join(root, "pile.yml")));
mkdirSync(join(dir, "keys"), { recursive: true });
writeFileSync(join(dir, "thing.txt"), "would-be evidence\n");
let refused = "";
try {
  execFileSync(join(root, "bin", "drop-pack"), ["--dir", dir, join(dir, "thing.txt")],
    { stdio: ["ignore", "pipe", "pipe"], cwd: root });
} catch (e) { refused = String(e.stderr || ""); }
ok("drop-pack refuses to seal into an unclaimed pile", /no recipient/.test(refused));
ok("and says what is missing", /keys\/pile\.age\.pub|--recipient/.test(refused));
rmSync(dir, { recursive: true, force: true });

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) process.exit(1); else console.log("ALL TESTS PASSED");
