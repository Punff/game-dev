// Admin password reset: prints the SQL that sets a new password for an
// account and logs it out everywhere. See signaling/README.md.
//   node tools/hash.mjs <username> <new password>
// (Uses the default rounds; the account is re-hashed with the configured
// count at its next login anyway.)
import { hashPassword, randomHex, ITERATIONS } from "../src/password.js";

const [username, password] = process.argv.slice(2);
if (!username || !password || password.length < 8) {
  console.error("usage: node tools/hash.mjs <username> <new password (8+ chars)>");
  process.exit(1);
}
const salt = randomHex(16);
const hash = await hashPassword(password, salt, ITERATIONS);
const name = username.replace(/'/g, "''");
console.log(
  `UPDATE accounts SET pass_hash = '${hash}', salt = '${salt}', iterations = ${ITERATIONS} WHERE username = '${name}'; ` +
  `DELETE FROM sessions WHERE account_id = (SELECT id FROM accounts WHERE username = '${name}');`);
