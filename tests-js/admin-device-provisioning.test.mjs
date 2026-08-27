import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";

import handler from "../api/admin/devices.js";
import {
  assertAdminRequest,
  buildQrUrl,
  generateClaimToken,
  generateDeviceId,
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
    display_name: "Bathroom Monitor",
    model: "eleph-zero2w-c4001",
    hardware_serial: "",
    batch_id: "",
    notes: "",
  });
});

test("admin guard blocks when feature flag is missing", () => {
  assert.deepEqual(
    assertAdminRequest({
      enabled: "false",
      expectedKey: "secret",
      providedKey: "secret",
    }),
    {
      ok: false,
      status: 404,
      message: "Admin device provisioning is disabled.",
    },
  );
});

test("admin API rejects when provisioning flag is missing", async () => {
  const previousFlag = process.env.ENABLE_ADMIN_DEVICE_PROVISIONING;
  const previousKey = process.env.ADMIN_DEVICE_PROVISIONING_KEY;
  process.env.ENABLE_ADMIN_DEVICE_PROVISIONING = "false";
  process.env.ADMIN_DEVICE_PROVISIONING_KEY = "secret";

  const response = createMockResponse();
  await handler(
    {
      method: "GET",
      headers: {
        "x-admin-provisioning-key": "secret",
      },
    },
    response,
  );

  assert.equal(response.statusCode, 404);
  assert.equal(JSON.parse(response.body).error, "Admin device provisioning is disabled.");

  restoreEnv("ENABLE_ADMIN_DEVICE_PROVISIONING", previousFlag);
  restoreEnv("ADMIN_DEVICE_PROVISIONING_KEY", previousKey);
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

function restoreEnv(key, value) {
  if (value === undefined) {
    delete process.env[key];
  } else {
    process.env[key] = value;
  }
}
