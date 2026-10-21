// Password hashing with PBKDF2-SHA256 (WebCrypto: the same code runs in the
// Worker and in Node for tools/hash.mjs).
//
// Rounds cost CPU: 100,000 (the most Workers allow) is ~50 ms, far over the
// free plan's 10 ms per request, so the default is lower. Set
// PBKDF2_ITERATIONS in wrangler.toml to raise it (e.g. on the paid plan);
// each account stores its count and is re-hashed at its next login.

export const ITERATIONS = 15_000;

export function iterations(env) {
  const n = parseInt(env?.PBKDF2_ITERATIONS || "", 10);
  return n >= 10_000 && n <= 100_000 ? n : ITERATIONS;
}

export function randomHex(bytes) {
  return toHex(crypto.getRandomValues(new Uint8Array(bytes)));
}

export async function hashPassword(password, saltHex, iterations = ITERATIONS) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt: fromHex(saltHex), iterations }, key, 256);
  return toHex(new Uint8Array(bits));
}

export async function sha256Hex(text) {
  return toHex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))));
}

// Compares two hex strings without returning early, so the time taken says
// nothing about how much of a guess was right.
export function sameHex(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function toHex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function fromHex(hex) {
  return new Uint8Array(hex.match(/../g).map((h) => parseInt(h, 16)));
}
