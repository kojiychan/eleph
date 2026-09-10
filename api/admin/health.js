import { json, requireAdmin } from "../../lib/admin/auth.mjs";

const hasValue = (value) => typeof value === "string" && value.trim().length > 0;

const envStatus = () => ({
  supabaseUrl: hasValue(process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL),
  supabaseServiceRoleKey: hasValue(process.env.SUPABASE_SERVICE_ROLE_KEY),
  claimTokenPepper: hasValue(process.env.CLAIM_TOKEN_PEPPER),
  deviceQrBaseUrl: hasValue(process.env.DEVICE_QR_BASE_URL),
});

const getSupabaseConfig = () => {
  const supabaseUrl = process.env.SUPABASE_URL ?? process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!hasValue(supabaseUrl) || !hasValue(serviceRoleKey)) {
    return null;
  }

  return {
    supabaseUrl: supabaseUrl.replace(/\/$/, ""),
    serviceRoleKey,
  };
};

const checkTable = async (table) => {
  const config = getSupabaseConfig();
  if (!config) {
    return {
      ok: false,
      reason: "missing Supabase URL or service role key",
    };
  }

  const response = await fetch(`${config.supabaseUrl}/rest/v1/${table}?select=*&limit=1`, {
    headers: {
      apikey: config.serviceRoleKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      "Content-Type": "application/json",
    },
  });

  if (response.ok) {
    return { ok: true };
  }

  return {
    ok: false,
    status: response.status,
    reason: await response.text(),
  };
};

export default async function handler(request, response) {
  try {
    if (request.method !== "GET") {
      response.setHeader("Allow", "GET");
      json(response, 405, { error: "Method not allowed" });
      return;
    }

    if (!requireAdmin(request, response)) {
      return;
    }

    const env = envStatus();
    const tables =
      env.supabaseUrl && env.supabaseServiceRoleKey
        ? {
            devices: await checkTable("devices"),
            deviceClaimTokens: await checkTable("device_claim_tokens"),
          }
        : {
            devices: { ok: false, reason: "missing Supabase URL or service role key" },
            deviceClaimTokens: { ok: false, reason: "missing Supabase URL or service role key" },
          };

    json(response, 200, {
      ok:
        env.supabaseUrl &&
        env.supabaseServiceRoleKey &&
        env.claimTokenPepper &&
        tables.devices.ok &&
        tables.deviceClaimTokens.ok,
      env,
      tables,
    });
  } catch (error) {
    json(response, 500, { error: error.message });
  }
}
