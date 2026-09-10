import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";

import healthHandler from "../api/admin/health.js";
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

test("QR URL contains identity fields and no Wi-Fi data", () => {
  const qrUrl = buildQrUrl({
    deviceId: "eleph-9k2m4q",
    displayName: "Bathroom Monitor",
    claimToken: "plain-token",
  });
  const parsed = new URL(qrUrl);

  assert.equal(parsed.origin, "https://eleph.app");
  assert.equal(parsed.pathname, "/device");
  assert.equal(parsed.searchParams.get("device_id"), "eleph-9k2m4q");
  assert.equal(parsed.searchParams.get("display_name"), "Bathroom Monitor");
  assert.equal(parsed.searchParams.get("claim_token"), "plain-token");
  assert.equal(parsed.searchParams.has("wifi_ssid"), false);
  assert.equal(parsed.searchParams.has("wifi_password"), false);
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

test("admin API requires login for device reads", async () => {
  const response = createMockResponse();
  await handler(
    {
      method: "GET",
      headers: {},
    },
    response,
  );

  assert.equal(response.statusCode, 401);
  assert.equal(response.headers["www-authenticate"], 'Basic realm="Eleph Admin"');
  assert.equal(JSON.parse(response.body).error, "Admin login required");
});

test("admin health reports missing Supabase env before table checks", async () => {
  const response = createMockResponse();
  await healthHandler(
    {
      method: "GET",
      headers: {
        authorization: `Basic ${Buffer.from("kojiychan:Test123").toString("base64")}`,
      },
    },
    response,
  );

  const body = JSON.parse(response.body);
  assert.equal(response.statusCode, 200);
  assert.equal(body.ok, false);
  assert.equal(body.env.supabaseUrl, false);
  assert.equal(body.env.supabaseServiceRoleKey, false);
  assert.equal(body.tables.devices.reason, "missing Supabase URL or service role key");
});

test("admin API creates QR when Supabase minimal insert returns an empty body", async () => {
  const originalFetch = globalThis.fetch;
  const originalEnv = { ...process.env };
  const calls = [];

  process.env.SUPABASE_URL = "https://example.supabase.co";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "service-role-key";
  process.env.CLAIM_TOKEN_PEPPER = "test-pepper";
  process.env.DEVICE_QR_BASE_URL = "https://eleph.app";

  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });

    if (String(url).includes("select=display_name")) {
      return jsonFetchResponse([]);
    }

    if (init.method === "POST" && String(url).includes("/rest/v1/devices")) {
      return jsonFetchResponse([
        {
          device_id: "eleph-test01",
          display_name: "Bathroom Monitor",
          model: "eleph-zero2w-c4001",
          created_at: "2026-09-10T00:00:00.000Z",
        },
      ]);
    }

    if (init.method === "POST" && String(url).includes("/rest/v1/device_claim_tokens")) {
      return textFetchResponse("");
    }

    throw new Error(`Unexpected fetch ${url}`);
  };

  try {
    const response = createMockResponse();
    await handler(
      {
        method: "POST",
        headers: {
          authorization: `Basic ${Buffer.from("kojiychan:Test123").toString("base64")}`,
        },
        [Symbol.asyncIterator]: async function* () {
          yield Buffer.from(
            JSON.stringify({
              display_name: "Bathroom Monitor",
              model: "eleph-zero2w-c4001",
            }),
          );
        },
      },
      response,
    );

    const body = JSON.parse(response.body);
    assert.equal(response.statusCode, 201);
    assert.equal(body.device.display_name, "Bathroom Monitor");
    assert.match(body.qr_url, /device_id=/);
    assert.match(body.qr_url, /display_name=Bathroom\+Monitor/);
    assert.match(body.qr_url, /claim_token=/);
    assert.equal(calls.some((call) => call.url.includes("device_claim_tokens")), true);
  } finally {
    globalThis.fetch = originalFetch;
    process.env = originalEnv;
  }
});

function jsonFetchResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => JSON.stringify(body),
  };
}

function textFetchResponse(body, status = 201) {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => body,
  };
}

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
