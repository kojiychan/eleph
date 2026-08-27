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

const setStatus = (message, tone = "neutral") => {
  statusEl.textContent = message;
  statusEl.dataset.tone = tone;
};

const value = (formData, key) => String(formData.get(key) ?? "").trim();

const readJsonResponse = async (response) => {
  const contentType = response.headers.get("content-type") || "";

  if (contentType.includes("application/json")) {
    return response.json();
  }

  throw new Error("Admin API is not available in this static preview.");
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

const formatDate = (valueToFormat) => {
  if (!valueToFormat) {
    return "Not set";
  }

  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(valueToFormat));
};

const renderDetails = ({ device, qr_url }) => {
  const rows = [
    ["Device ID", device.device_id],
    ["Display name", device.display_name],
    ["Model", device.model || "Not set"],
    ["Hardware serial", device.hardware_serial || "Not set"],
    ["Created", formatDate(device.created_at)],
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

const refreshNextDisplayName = async () => {
  if (displayNameEdited) {
    return;
  }

  try {
    const response = await fetch("/api/admin/devices");
    const result = await readJsonResponse(response);

    if (!response.ok) {
      throw new Error(result.error || "Could not load next device name");
    }

    if (result.next_display_name && !displayNameEdited) {
      displayNameInput.value = result.next_display_name;
    }
  } catch (error) {
    setStatus(error.message, "error");
  }
};

displayNameInput.addEventListener("input", () => {
  displayNameEdited = true;
});
refreshNextDisplayName();

form.addEventListener("submit", async (event) => {
  event.preventDefault();

  const formData = new FormData(form);
  const submitButton = form.querySelector("button[type='submit']");

  submitButton.disabled = true;
  setStatus("Creating device...", "neutral");

  try {
    const response = await fetch("/api/admin/devices", {
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
    setStatus("Device created. Print or download the QR label now.", "success");
  } catch (error) {
    setStatus(error.message, "error");
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
