const form = document.querySelector("#devices-form");
const statusEl = document.querySelector("#devices-status");
const devicesBody = document.querySelector("#devices-body");

const setStatus = (message, tone = "neutral") => {
  statusEl.textContent = message;
  statusEl.dataset.tone = tone;
};

const readJsonResponse = async (response) => {
  const contentType = response.headers.get("content-type") || "";

  if (contentType.includes("application/json")) {
    return response.json();
  }

  throw new Error("Admin API is not available in this static preview.");
};

const formatDate = (valueToFormat) => {
  if (!valueToFormat) {
    return "Not seen";
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
      textCell(formatDate(device.created_at)),
      textCell(claimTokens.some((token) => Boolean(token.used_at)) ? "Yes" : "No"),
    );

    devicesBody.append(row);
  }
};

form.addEventListener("submit", async (event) => {
  event.preventDefault();

  const submitButton = form.querySelector("button[type='submit']");

  submitButton.disabled = true;
  setStatus("Loading devices...", "neutral");

  try {
    const response = await fetch("/api/admin/devices");
    const result = await readJsonResponse(response);

    if (!response.ok) {
      throw new Error(result.error || "Could not load devices");
    }

    renderDevices(result.devices || []);
    setStatus("Devices loaded.", "success");
  } catch (error) {
    setStatus(error.message, "error");
  } finally {
    submitButton.disabled = false;
  }
});
