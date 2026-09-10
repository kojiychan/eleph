const ADMIN_USERNAME = "kojiychan";
const ADMIN_PASSWORD = "Test123";
const SESSION_KEY = "eleph.admin.authorization";

const loginPanel = document.querySelector("#admin-login-panel");
const dashboard = document.querySelector("#admin-dashboard");
const loginForm = document.querySelector("#admin-login-form");
const loginStatus = document.querySelector("#admin-login-status");
const logoutButton = document.querySelector("#admin-logout");
const refreshButton = document.querySelector("#refresh-devices");
const showCreateButton = document.querySelector("#show-create-device");
const createPanel = document.querySelector("#create-device-panel");
const devicesStatus = document.querySelector("#devices-status");
const devicesBody = document.querySelector("#devices-body");
const envSupabaseUrl = document.querySelector("#env-supabase-url");
const envServiceKey = document.querySelector("#env-service-key");
const envClaimPepper = document.querySelector("#env-claim-pepper");
const tableDevices = document.querySelector("#table-devices");
const tableStatusText = document.querySelector("#table-status-text");
const form = document.querySelector("#device-form");
const statusEl = document.querySelector("#device-form-status");
const resultEl = document.querySelector("#device-result");
const qrFrame = document.querySelector("#qr-frame");
const detailsEl = document.querySelector("#device-details");
const downloadPngButton = document.querySelector("#download-png");
const downloadSvgButton = document.querySelector("#download-svg");
const printButton = document.querySelector("#print-label");
const displayNameInput = document.querySelector("#display-name");

let latestResult = null;
let displayNameEdited = false;

const setStatus = (element, message, tone = "neutral") => {
  element.textContent = message;
  element.dataset.tone = tone;
};

const value = (formData, key) => String(formData.get(key) ?? "").trim();

const buildAuthorization = (username, password) => `Basic ${btoa(`${username}:${password}`)}`;

const getAuthorization = () => sessionStorage.getItem(SESSION_KEY) || "";

const readJsonResponse = async (response) => {
  const contentType = response.headers.get("content-type") || "";

  if (contentType.includes("application/json")) {
    return response.json();
  }

  throw new Error("Admin API is not available in this static preview.");
};

const adminFetch = (url, init = {}) =>
  fetch(url, {
    ...init,
    headers: {
      Authorization: getAuthorization(),
      ...init.headers,
    },
  });

const showDashboard = () => {
  loginPanel.hidden = true;
  loginPanel.style.display = "none";
  dashboard.hidden = false;
  dashboard.style.display = "";
  logoutButton.hidden = false;
  logoutButton.style.display = "";
};

const showLogin = () => {
  loginPanel.hidden = false;
  loginPanel.style.display = "";
  dashboard.hidden = true;
  dashboard.style.display = "none";
  logoutButton.hidden = true;
  logoutButton.style.display = "none";
};

const downloadDataUrl = (filename, dataUrl) => {
  const link = document.createElement("a");
  link.href = dataUrl;
  link.download = filename;
  link.click();
};

const downloadText = (filename, text, type) => {
  const blob = new Blob([text], { type });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  link.click();
  URL.revokeObjectURL(link.href);
};

const formatDate = (valueToFormat, fallback = "Not seen") => {
  if (!valueToFormat) {
    return fallback;
  }

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(valueToFormat));
};

const textCell = (text) => {
  const cell = document.createElement("td");
  cell.textContent = text || "Not set";
  return cell;
};

const renderDevices = (devices) => {
  devicesBody.replaceChildren();

  if (!devices.length) {
    const row = document.createElement("tr");
    const cell = textCell("No devices found.");
    cell.colSpan = 7;
    row.append(cell);
    devicesBody.append(row);
    return;
  }

  for (const device of devices) {
    const claimTokens = device.device_claim_tokens || [];
    const row = document.createElement("tr");

    row.append(
      textCell(device.device_id),
      textCell(device.display_name),
      textCell(device.model),
      textCell(device.connection_status),
      textCell(formatDate(device.last_seen_at)),
      textCell(formatDate(device.created_at, "Not set")),
      textCell(claimTokens.some((token) => Boolean(token.used_at)) ? "Yes" : "No"),
    );

    devicesBody.append(row);
  }
};

const renderDetails = ({ device, qr_url }) => {
  const rows = [
    ["Device ID", device.device_id],
    ["Device name", device.display_name],
    ["Model", device.model || "Not set"],
    ["Hardware serial", device.hardware_serial || "Not set"],
    ["Created", formatDate(device.created_at, "Not set")],
    ["QR payload", qr_url],
  ];

  detailsEl.replaceChildren();
  for (const [label, detail] of rows) {
    const term = document.createElement("dt");
    const description = document.createElement("dd");

    term.textContent = label;
    description.textContent = detail;
    detailsEl.append(term, description);
  }
};

const setDot = (element, ok) => {
  element.dataset.state = ok ? "ok" : "error";
};

const loadHealth = async () => {
  setStatus(devicesStatus, "Checking Supabase connection...", "neutral");

  try {
    const response = await adminFetch("/api/admin/health");
    const result = await readJsonResponse(response);

    if (!response.ok) {
      throw new Error(result.error || "Could not check Supabase connection");
    }

    setDot(envSupabaseUrl, result.env?.supabaseUrl);
    setDot(envServiceKey, result.env?.supabaseServiceRoleKey);
    setDot(envClaimPepper, result.env?.claimTokenPepper);
    setDot(tableDevices, result.tables?.devices?.ok && result.tables?.deviceClaimTokens?.ok);

    if (!result.env?.supabaseUrl || !result.env?.supabaseServiceRoleKey) {
      tableStatusText.textContent = "Add Vercel env vars, then redeploy";
      setStatus(devicesStatus, "Supabase env vars are missing in Vercel.", "error");
      return false;
    }

    if (!result.env?.claimTokenPepper) {
      tableStatusText.textContent = "CLAIM_TOKEN_PEPPER missing";
      setStatus(devicesStatus, "Add CLAIM_TOKEN_PEPPER in Vercel, then redeploy.", "error");
      return false;
    }

    if (!result.tables?.devices?.ok || !result.tables?.deviceClaimTokens?.ok) {
      tableStatusText.textContent = "Run supabase/device_provisioning.sql";
      setStatus(devicesStatus, "Supabase is connected, but provisioning tables are missing.", "error");
      return false;
    }

    tableStatusText.textContent = "devices and device_claim_tokens reachable";
    return true;
  } catch (error) {
    setDot(envSupabaseUrl, false);
    setDot(envServiceKey, false);
    setDot(envClaimPepper, false);
    setDot(tableDevices, false);
    tableStatusText.textContent = "Could not run diagnostics";
    setStatus(devicesStatus, error.message, "error");
    return false;
  }
};

const loadDevices = async () => {
  refreshButton.disabled = true;
  setStatus(devicesStatus, "Loading devices...", "neutral");

  try {
    const response = await adminFetch("/api/admin/devices");
    const result = await readJsonResponse(response);

    if (response.status === 401) {
      sessionStorage.removeItem(SESSION_KEY);
      showLogin();
      throw new Error("Admin login required.");
    }

    if (!response.ok) {
      throw new Error(result.error || "Could not load devices");
    }

    renderDevices(result.devices || []);
    if (result.next_display_name && !displayNameEdited) {
      displayNameInput.value = result.next_display_name;
    }
    setStatus(devicesStatus, "Devices loaded.", "success");
  } catch (error) {
    setStatus(devicesStatus, error.message, "error");
  } finally {
    refreshButton.disabled = false;
  }
};

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  const formData = new FormData(loginForm);
  const username = value(formData, "username");
  const password = value(formData, "password");

  if (username !== ADMIN_USERNAME || password !== ADMIN_PASSWORD) {
    setStatus(loginStatus, "Invalid admin login.", "error");
    return;
  }

  sessionStorage.setItem(SESSION_KEY, buildAuthorization(username, password));
  loginForm.reset();
  setStatus(loginStatus, "", "neutral");
  showDashboard();
  if (await loadHealth()) {
    await loadDevices();
  }
});

logoutButton.addEventListener("click", () => {
  sessionStorage.removeItem(SESSION_KEY);
  showLogin();
});

refreshButton.addEventListener("click", loadDevices);

showCreateButton.addEventListener("click", () => {
  createPanel.hidden = !createPanel.hidden;
});

displayNameInput.addEventListener("input", () => {
  displayNameEdited = true;
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();

  const formData = new FormData(form);
  const submitButton = form.querySelector("button[type='submit']");

  submitButton.disabled = true;
  setStatus(statusEl, "Creating QR code...", "neutral");

  try {
    const response = await adminFetch("/api/admin/devices", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        display_name: value(formData, "display_name"),
        model: value(formData, "model"),
        hardware_serial: value(formData, "hardware_serial"),
        batch_id: value(formData, "batch_id"),
        notes: value(formData, "notes"),
      }),
    });
    const result = await readJsonResponse(response);

    if (!response.ok) {
      throw new Error(result.error || "Device creation failed");
    }

    latestResult = result;
    qrFrame.innerHTML = result.qr.svg;
    renderDetails(result);
    resultEl.hidden = false;
    if (result.next_display_name) {
      displayNameEdited = false;
      displayNameInput.value = result.next_display_name;
    }
    form.reset();
    await loadDevices();
    setStatus(statusEl, "QR code created. Print or download the label now.", "success");
  } catch (error) {
    setStatus(statusEl, error.message, "error");
  } finally {
    submitButton.disabled = false;
  }
});

downloadPngButton.addEventListener("click", () => {
  if (latestResult) {
    downloadDataUrl(`${latestResult.device.device_id}-qr.png`, latestResult.qr.pngDataUrl);
  }
});

downloadSvgButton.addEventListener("click", () => {
  if (latestResult) {
    downloadText(`${latestResult.device.device_id}-qr.svg`, latestResult.qr.svg, "image/svg+xml");
  }
});

printButton.addEventListener("click", () => {
  if (latestResult) {
    window.print();
  }
});

if (getAuthorization()) {
  showDashboard();
  if (await loadHealth()) {
    await loadDevices();
  }
} else {
  showLogin();
}
