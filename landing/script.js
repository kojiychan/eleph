const header = document.querySelector(".site-header");
const year = document.querySelector("#year");
const betaForm = document.querySelector("#beta-form");
const betaFormStatus = document.querySelector("#beta-form-status");

const syncHeader = () => {
  if (header) {
    header.classList.toggle("is-scrolled", window.scrollY > 12);
  }
};

if (year) {
  year.textContent = new Date().getFullYear();
}

syncHeader();
window.addEventListener("scroll", syncHeader, { passive: true });

const setFormStatus = (message, tone = "neutral") => {
  if (!betaFormStatus) {
    return;
  }

  betaFormStatus.textContent = message;
  betaFormStatus.dataset.tone = tone;
};

const normalizeValue = (formData, key) => String(formData.get(key) ?? "").trim();

betaForm?.addEventListener("submit", async (event) => {
  event.preventDefault();

  const formData = new FormData(betaForm);
  if (normalizeValue(formData, "company")) {
    betaForm.reset();
    setFormStatus("Thanks. You're on the beta list.", "success");
    return;
  }

  const config = window.ELEPH_CONFIG ?? {};
  const supabaseUrl = String(config.supabaseUrl ?? "").replace(/\/$/, "");
  const supabaseAnonKey = String(config.supabaseAnonKey ?? "");

  if (!supabaseUrl || !supabaseAnonKey) {
    setFormStatus("Beta signup storage is not configured yet.", "error");
    return;
  }

  const submitButton = betaForm.querySelector("button[type='submit']");
  const payload = {
    first_name: normalizeValue(formData, "first_name"),
    last_name: normalizeValue(formData, "last_name"),
    email: normalizeValue(formData, "email").toLowerCase(),
    phone: normalizeValue(formData, "phone"),
    source: "landing_page",
  };

  submitButton.disabled = true;
  setFormStatus("Submitting...", "neutral");

  try {
    const response = await fetch(`${supabaseUrl}/rest/v1/beta_signups`, {
      method: "POST",
      headers: {
        apikey: supabaseAnonKey,
        Authorization: `Bearer ${supabaseAnonKey}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify(payload),
    });

    if (response.status === 409) {
      setFormStatus("You're already on the beta list.", "success");
      betaForm.reset();
      return;
    }

    if (!response.ok) {
      throw new Error(`Supabase returned ${response.status}`);
    }

    betaForm.reset();
    setFormStatus("Thanks. You're on the beta list.", "success");
  } catch {
    setFormStatus("Something went wrong. Please try again in a minute.", "error");
  } finally {
    submitButton.disabled = false;
  }
});
