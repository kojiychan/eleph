import {
  buildQrImages,
  buildQrUrl,
  ensureUniqueDeviceDisplayName,
  generateClaimToken,
  generateDeviceId,
  getNextDeviceDisplayName,
  hashClaimToken,
  sanitizeDeviceInput,
} from "../../lib/admin/device-provisioning.mjs";

const json = (response, status, body) => {
  response.statusCode = status;
  response.setHeader("Content-Type", "application/json");
  response.end(JSON.stringify(body));
};

const readJsonBody = async (request) => {
  const chunks = [];

  for await (const chunk of request) {
    chunks.push(chunk);
  }

  if (!chunks.length) {
    return {};
  }

  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
};

const getSupabaseConfig = () => {
  const supabaseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
  }

  return {
    supabaseUrl: supabaseUrl.replace(/\/$/, ""),
    serviceRoleKey,
  };
};

const supabaseFetch = async (path, init = {}) => {
  const { supabaseUrl, serviceRoleKey } = getSupabaseConfig();
  const response = await fetch(`${supabaseUrl}${path}`, {
    ...init,
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
      ...init.headers,
    },
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(`Supabase ${response.status}: ${message}`);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json();
};

const fetchExistingDeviceNames = () =>
  supabaseFetch("/rest/v1/devices?select=display_name&order=created_at.asc");

const insertDevice = ({ deviceId, input, displayName }) =>
  supabaseFetch("/rest/v1/devices?select=*", {
    method: "POST",
    headers: {
      Prefer: "return=representation",
    },
    body: JSON.stringify({
      device_id: deviceId,
      display_name: displayName,
      model: input.model,
      hardware_serial: input.hardware_serial || null,
      batch_id: input.batch_id || null,
      notes: input.notes || null,
      connection_status: "unprovisioned",
    }),
  });

const isUniqueViolation = (error) =>
  error?.message?.includes("23505") || error?.message?.toLowerCase().includes("duplicate key");

export default async function handler(request, response) {
  try {
    if (request.method === "GET") {
      const [devices, existingDeviceNames] = await Promise.all([
        supabaseFetch(
          "/rest/v1/devices?select=device_id,display_name,model,connection_status,last_seen_at,created_at,device_claim_tokens(used_at)&order=created_at.desc&limit=50",
        ),
        fetchExistingDeviceNames(),
      ]);
      json(response, 200, {
        devices,
        next_display_name: getNextDeviceDisplayName(existingDeviceNames),
      });
      return;
    }

    if (request.method !== "POST") {
      response.setHeader("Allow", "GET, POST");
      json(response, 405, { error: "Method not allowed" });
      return;
    }

    const deviceId = generateDeviceId();
    const input = sanitizeDeviceInput(await readJsonBody(request));
    const claimToken = generateClaimToken();
    const tokenHash = hashClaimToken(claimToken, process.env.CLAIM_TOKEN_PEPPER);
    const now = new Date().toISOString();
    let existingDeviceNames = [];
    let displayName = input.display_name;
    let device = null;

    for (let attempt = 0; attempt < 3; attempt += 1) {
      existingDeviceNames = await fetchExistingDeviceNames();
      displayName = ensureUniqueDeviceDisplayName(displayName, existingDeviceNames);

      try {
        [device] = await insertDevice({ deviceId, input, displayName });
        break;
      } catch (error) {
        if (!isUniqueViolation(error) || attempt === 2) {
          throw error;
        }

        displayName = getNextDeviceDisplayName([...existingDeviceNames, { display_name: displayName }]);
      }
    }

    await supabaseFetch("/rest/v1/device_claim_tokens", {
      method: "POST",
      headers: {
        Prefer: "return=minimal",
      },
      body: JSON.stringify({
        device_id: deviceId,
        token_hash: tokenHash,
      }),
    });

    const qr_url = buildQrUrl({
      appBaseUrl: process.env.DEVICE_QR_BASE_URL ?? "https://eleph.app",
      deviceId,
      token: claimToken,
    });
    const qr = await buildQrImages(qr_url);

    json(response, 201, {
      device: {
        ...device,
        created_at: device.created_at ?? now,
      },
      next_display_name: getNextDeviceDisplayName([...existingDeviceNames, { display_name: displayName }]),
      claim_token: claimToken,
      qr_url,
      qr,
      warning: "The plaintext claim token is only shown once. Store only the printed QR label.",
    });
  } catch (error) {
    json(response, 500, { error: error.message });
  }
}
