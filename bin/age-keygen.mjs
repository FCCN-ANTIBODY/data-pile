// data-pile/bin/age-keygen.mjs — ON-DEVICE age keygen (the mapped age-keygen gap for pile provisioning).
// A trimmed slice of anecdote.channel/composer/age-mint.mjs: mint an age X25519 identity in WebCrypto and
// derive its recipient, with NO gesture/attest surface and no `age-keygen` binary — so an offline origin
// can stand up a pile's identity on the device, host-side never. Encoding is bech32 (BIP-173), the format
// age keys wear; the curve is platform WebCrypto (X25519, Baseline since 2025). Interops with the real
// age-keygen (its -y agrees with recipientOf). Node + browser.
//   mintAgeIdentity() -> { identity: "AGE-SECRET-KEY-1…", recipient: "age1…" }
//   recipientOf(identity) -> "age1…"

const RECIPIENT_HRP = "age";
const IDENTITY_HRP = "age-secret-key-";
const CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

// ---- bech32 (BIP-173) — encoding only, no crypto ---------------------------------------------------
function polymod(values) {
  const GEN = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  let chk = 1;
  for (const v of values) { const b = chk >>> 25; chk = ((chk & 0x1ffffff) << 5) ^ v; for (let i = 0; i < 5; i++) if ((b >> i) & 1) chk ^= GEN[i]; }
  return chk >>> 0;
}
const hrpExpand = (hrp) => { const o = []; for (let i = 0; i < hrp.length; i++) o.push(hrp.charCodeAt(i) >> 5); o.push(0); for (let i = 0; i < hrp.length; i++) o.push(hrp.charCodeAt(i) & 31); return o; };
function convertBits(data, from, to, pad) {
  let acc = 0, bits = 0; const out = []; const maxv = (1 << to) - 1;
  for (const v of data) { acc = (acc << from) | v; bits += from; while (bits >= to) { bits -= to; out.push((acc >> bits) & maxv); } }
  if (pad && bits) out.push((acc << (to - bits)) & maxv);
  return out;
}
function bech32Encode(hrp, bytes) {
  const data = convertBits([...bytes], 8, 5, true);
  const values = [...hrpExpand(hrp), ...data];
  const polym = polymod([...values, 0, 0, 0, 0, 0, 0]) ^ 1;
  const chk = []; for (let i = 0; i < 6; i++) chk.push((polym >> (5 * (5 - i))) & 31);
  return hrp + "1" + [...data, ...chk].map((d) => CHARSET[d]).join("");
}
function bech32Decode(str) {
  const s = str.toLowerCase(); const pos = s.lastIndexOf("1");
  const hrp = s.slice(0, pos); const data = [];
  for (const c of s.slice(pos + 1)) { const d = CHARSET.indexOf(c); if (d === -1) throw new Error("age-keygen: bad bech32 char"); data.push(d); }
  if (polymod([...hrpExpand(hrp), ...data]) !== 1) throw new Error("age-keygen: bech32 checksum");
  const bytes = convertBits(data.slice(0, -6), 5, 8, false);
  return { hrp, bytes: Uint8Array.from(bytes) };
}
export const encodeRecipient = (pub) => bech32Encode(RECIPIENT_HRP, pub);
export const encodeIdentity = (scalar) => bech32Encode(IDENTITY_HRP, scalar).toUpperCase();
export function parseIdentity(str) { const { hrp, bytes } = bech32Decode(str); if (hrp !== IDENTITY_HRP) throw new Error("age-keygen: not an identity"); return bytes; }

// ---- minting & deriving (platform WebCrypto X25519) ------------------------------------------------
const subtle = () => (globalThis.crypto && globalThis.crypto.subtle) || (() => { throw new Error("age-keygen: no WebCrypto"); })();
const PKCS8_PREFIX = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20]);
const BASEPOINT = (() => { const b = new Uint8Array(32); b[0] = 9; return b; })();
const fromB64url = (s) => { const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (s.length % 4)) % 4); return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)); };

export async function mintAgeIdentity() {
  const pair = await subtle().generateKey({ name: "X25519" }, true, ["deriveBits"]);
  const jwk = await subtle().exportKey("jwk", pair.privateKey);
  const pub = new Uint8Array(await subtle().exportKey("raw", pair.publicKey));
  return { identity: encodeIdentity(fromB64url(jwk.d)), recipient: encodeRecipient(pub) };
}

export async function recipientOf(identity) {
  const scalar = parseIdentity(identity);
  const pkcs8 = new Uint8Array(PKCS8_PREFIX.length + 32); pkcs8.set(PKCS8_PREFIX, 0); pkcs8.set(scalar, PKCS8_PREFIX.length);
  const priv = await subtle().importKey("pkcs8", pkcs8, { name: "X25519" }, false, ["deriveBits"]);
  const base = await subtle().importKey("raw", BASEPOINT, { name: "X25519" }, false, []);
  const pub = new Uint8Array(await subtle().deriveBits({ name: "X25519", public: base }, priv, 256));
  return encodeRecipient(pub);
}
