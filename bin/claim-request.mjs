// data-pile/bin/claim-request.mjs — the outbound half of the claim (claim.html).
//
// Builds the pre-filled request a claimant submits to hand a pile its public recipient.
//
// THE IDENTITY IS NOT A PARAMETER HERE, AND THAT IS THE POINT. This module cannot leak the
// secret key because it is never given one: the custody line (invariant #4 — sign is not
// decrypt; a provisioner never touches an identity) is enforced by the SHAPE of the function
// rather than by remembering not to interpolate the wrong variable. test/claim.test.mjs proves
// it by handing an identity to every input and checking none of it reaches the output.
//
// Pure: no DOM, no network, no clock unless the caller omits `at`. Node + browser.

export const SCHEMA = "data-pile.claim/v1";

const AGE_RECIPIENT = /^age1[ac-hj-np-z02-9]{58}$/;

export function claimRequest({ recipient, repoSlug = "", origin = "", rpId = "", at = null } = {}) {
  // Refuse to build a request around anything that is not a recipient. A malformed value here
  // would be committed into pile.yml by hand later, where it fails much less legibly.
  if (!AGE_RECIPIENT.test(String(recipient || ""))) {
    throw new Error("claim-request: not an age recipient (age1…): " + String(recipient).slice(0, 24));
  }
  // A secret key must never arrive here even by mistake — the caller passing the wrong half is
  // exactly the slip this whole module is shaped to make impossible.
  if (/AGE-SECRET-KEY-1/i.test(JSON.stringify(arguments[0]))) {
    throw new Error("claim-request: an identity was passed in; only the recipient may leave the device");
  }

  const when = at || new Date().toISOString();
  const title = "Claim: age recipient for this pile";
  const body = [
    "This pile was claimed from its own claim page. The identity was minted on the claimant's",
    "device and never left it. Only the public recipient is below — it seals TO this pile and",
    "cannot open it.",
    "",
    "    " + recipient,
    "",
    "To apply it:",
    "",
    "    bin/pile-new fill --dir . --recipient " + recipient,
    "",
    "---",
    "schema: " + SCHEMA,
    "origin: " + origin,
    "passkey scoped to: " + rpId,
    "claimed at: " + when,
  ].join("\n");

  const url = repoSlug
    ? "https://github.com/" + repoSlug + "/issues/new?title=" + encodeURIComponent(title) +
      "&body=" + encodeURIComponent(body)
    : "data:text/plain;charset=utf-8," + encodeURIComponent(body);

  return { title, body, url, recipient, at: when };
}
