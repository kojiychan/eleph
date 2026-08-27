const form = document.querySelector("#device-form");
const statusEl = document.querySelector("#device-form-status");
const resultEl = document.querySelector("#device-result");
const qrFrame = document.querySelector("#qr-frame");
const detailsEl = document.querySelector("#device-details");
const downloadPngButton = document.querySelector("#download-png");
const downloadSvgButton = document.querySelector("#download-svg");
const printButton = document.querySelector("#print-label");

let latestResult = null;

const setStatus = (message, tone = "neutral") => {
  statusEl.textContent = message;
  statusEl.dataset.tone = tone;
};

const value = (formData, key) => String(formData.get(key) ?? "").trim();

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
        "X-Admin-Provisioning-Key": value(formData, "admin_key"),
      },
      body: JSON.stringify({
        display_name: value(formData, "display_name"),
        model: value(formData, "model"),
        hardware_serial: value(formData, "hardware_serial"),
        batch_id: value(formData, "batch_id"),
        notes: value(formData, "notes"),
      }),
    });
    const result = await response.json();

    if (!response.ok) {
      throw new Error(result.error || "Device creation failed");
    }

    latestResult = result;
    qrFrame.innerHTML = result.qr.svg;
    renderDetails(result);
    resultEl.hidden = false;
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
