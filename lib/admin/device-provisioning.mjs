import { createHash, randomBytes } from "node:crypto";
import QRCode from "qrcode";

const DEFAULT_DISPLAY_NAME = "Device 1";
const DEFAULT_DISPLAY_NAME_PREFIX = "Device";
const DEFAULT_MODEL = "eleph-zero2w-c4001";
const DEVICE_ID_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789";

export function generateDeviceId(randomBytesFn = randomBytes) {
  const bytes = randomBytesFn(6);
  let suffix = "";

  for (const byte of bytes) {
    suffix += DEVICE_ID_ALPHABET[byte % DEVICE_ID_ALPHABET.length];
  }

  return `eleph-${suffix}`;
}

export function generateClaimToken(randomBytesFn = randomBytes) {
  return randomBytesFn(32).toString("base64url");
}

export function hashClaimToken(token, pepper) {
  if (!pepper) {
    throw new Error("CLAIM_TOKEN_PEPPER is required");
  }

  return createHash("sha256").update(`${pepper}:${token}`).digest("hex");
}

export function buildQrUrl({ appBaseUrl = "https://eleph.app", deviceId, token }) {
  const url = new URL("/device", appBaseUrl);
  url.searchParams.set("device_id", deviceId);
  url.searchParams.set("token", token);
  return url.toString();
}

export async function buildQrImages(qrUrl) {
  const svg = await QRCode.toString(qrUrl, {
    type: "svg",
    errorCorrectionLevel: "M",
    margin: 2,
    color: {
      dark: "#112943",
      light: "#ffffff",
    },
  });
  const pngDataUrl = await QRCode.toDataURL(qrUrl, {
    type: "image/png",
    errorCorrectionLevel: "M",
    margin: 2,
    width: 1024,
    color: {
      dark: "#112943",
      light: "#ffffff",
    },
  });

  return { svg, pngDataUrl };
}

export function sanitizeDeviceInput(input = {}) {
  return {
    display_name: cleanText(input.display_name) || DEFAULT_DISPLAY_NAME,
    model: cleanText(input.model) || DEFAULT_MODEL,
    hardware_serial: cleanText(input.hardware_serial),
    batch_id: cleanText(input.batch_id),
    notes: cleanText(input.notes, 2000),
  };
}

export function getNextDeviceDisplayName(devices = [], prefix = DEFAULT_DISPLAY_NAME_PREFIX) {
  const numberedNamePattern = new RegExp(`^${escapeRegExp(prefix)}\\s+(\\d+)$`, "i");
  let highestDeviceNumber = 0;

  for (const device of devices) {
    const displayName = cleanText(device?.display_name);
    const match = displayName.match(numberedNamePattern);

    if (match) {
      highestDeviceNumber = Math.max(highestDeviceNumber, Number(match[1]));
    }
  }

  return `${prefix} ${highestDeviceNumber + 1}`;
}

export function ensureUniqueDeviceDisplayName(inputDisplayName, devices = []) {
  const displayName = cleanText(inputDisplayName) || getNextDeviceDisplayName(devices);

  if (devices.some((device) => cleanText(device?.display_name).toLowerCase() === displayName.toLowerCase())) {
    return getNextDeviceDisplayName(devices);
  }

  return displayName;
}

export function assertAdminRequest({ enabled }) {
  if (enabled !== "true") {
    return {
      ok: false,
      status: 404,
      message: "Admin device provisioning is disabled.",
    };
  }

  return { ok: true };
}

function cleanText(value, maxLength = 240) {
  return String(value ?? "").trim().slice(0, maxLength);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
