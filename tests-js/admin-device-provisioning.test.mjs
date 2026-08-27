import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";

import handler from "../api/admin/devices.js";
import {
  buildQrUrl,
  ensureUniqueDeviceDisplayName,
  generateClaimToken,
  generateDeviceId,
  getNextDeviceDisplayName,
  hashClaimToken,
  sanitizeDeviceInput,
} from "../lib/admin/device-provisioning.mjs";

test("device id generator uses the eleph short-id format", () => {
  const deviceId = generateDeviceId(() => Buffer.from([0, 1, 2, 3, 4, 5]));

  assert.equal(deviceId, "eleph-abcdef");
  assert.match(generateDeviceId(), /^eleph-[a-z2-9]{6}$/);
});

test("claim token is generated and not equal to its stored hash", () => {
  const token = generateClaimToken(() => Buffer.alloc(32, 7));
  const tokenHash = hashClaimToken(token, "test-pepper");

  assert.ok(token.length > 30);
  assert.match(tokenHash, /^[a-f0-9]{64}$/);
  assert.notEqual(tokenHash, token);
});

test("QR URL contains device_id and plaintext one-time token", () => {
  const qrUrl = buildQrUrl({
    deviceId: "eleph-9k2m4q",
    token: "plain-token",
  });
  const parsed = new URL(qrUrl);

  assert.equal(parsed.origin, "https://eleph.app");
  assert.equal(parsed.pathname, "/device");
  assert.equal(parsed.searchParams.get("device_id"), "eleph-9k2m4q");
  assert.equal(parsed.searchParams.get("token"), "plain-token");
});

test("device input gets required defaults", () => {
  assert.deepEqual(sanitizeDeviceInput({}), {
    display_name: "Device 1",
    model: "eleph-zero2w-c4001",
    hardware_serial: "",
    batch_id: "",
    notes: "",
  });
});

test("next device display name advances from the highest created device number", () => {
  assert.equal(
    getNextDeviceDisplayName([
      { display_name: "Device 1" },
      { display_name: "Kitchen Monitor" },
      { display_name: "Device 4" },
      { display_name: "device 2" },
    ]),
    "Device 5",
  );
});

test("duplicate device display names are replaced with the next numbered device name", () => {
  const devices = [{ display_name: "Device 1" }, { display_name: "Device 2" }];

  assert.equal(ensureUniqueDeviceDisplayName("Device 2", devices), "Device 3");
  assert.equal(ensureUniqueDeviceDisplayName(" device 1 ", devices), "Device 3");
  assert.equal(ensureUniqueDeviceDisplayName("Kitchen Monitor", devices), "Kitchen Monitor");
});

test("admin API rejects unsupported methods without an admin key or feature flag", async () => {
  const response = createMockResponse();
  await handler(
    {
      method: "PATCH",
      headers: {},
    },
    response,
  );

  assert.equal(response.statusCode, 405);
  assert.equal(JSON.parse(response.body).error, "Method not allowed");
});

function createMockResponse() {
  const response = new EventEmitter();
  response.headers = {};
  response.setHeader = (key, value) => {
    response.headers[key.toLowerCase()] = value;
  };
  response.end = (body) => {
    response.body = body;
    response.emit("finish");
  };
  return response;
}
