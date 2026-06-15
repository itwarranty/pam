#!/usr/bin/env node
/**
 * TOTP QR for test-repo-key onboarding (PNG + UTF-8 ASCII).
 * Usage: node gen-totp-qr.mjs <otpauth-uri> <out.png> <out.ascii.txt>
 */
import { writeFileSync } from 'node:fs';
import QRCode from 'qrcode';

const [uri, pngPath, asciiPath] = process.argv.slice(2);
if (!uri || !pngPath || !asciiPath) {
  console.error('usage: gen-totp-qr.mjs <otpauth-uri> <out.png> <out.ascii.txt>');
  process.exit(1);
}

await QRCode.toFile(pngPath, uri, { type: 'png', width: 280, margin: 2, errorCorrectionLevel: 'M' });
const ascii = await QRCode.toString(uri, { type: 'utf8', small: true });
writeFileSync(asciiPath, ascii, 'utf8');
