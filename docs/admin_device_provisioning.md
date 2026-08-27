# Admin Device Provisioning

Private manufacturing routes:

```text
/admin/devices/new/
/admin/devices/
```

The new-device route creates a device record, generates a one-time plaintext claim token,
stores only a SHA-256 hash in Supabase, and renders a QR code containing:

```text
https://eleph.app/device?device_id=...&token=...
```

The QR code is not used to connect to the Raspberry Pi. It assigns identity to the Pi after
the iOS app has already connected over Bluetooth.

## SQL

Run either:

```text
supabase/device_provisioning.sql
```

or the full schema:

```text
supabase/schema.sql
```

## Vercel Environment

Required server-side variables:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
ENABLE_ADMIN_DEVICE_PROVISIONING=true
ADMIN_DEVICE_PROVISIONING_KEY
CLAIM_TOKEN_PEPPER
DEVICE_QR_BASE_URL=https://eleph.app
```

`SUPABASE_SERVICE_ROLE_KEY`, `ADMIN_DEVICE_PROVISIONING_KEY`, and `CLAIM_TOKEN_PEPPER` must
never be exposed in browser config.

## Temporary Security

The current admin protection is intentionally temporary:

- `ENABLE_ADMIN_DEVICE_PROVISIONING=true` enables the API.
- `ADMIN_DEVICE_PROVISIONING_KEY` is submitted from the admin page and checked server-side.
- Proper authenticated admin role authorization is still required before production.

The serverless API does the sensitive work:

- Generates `device_id`
- Generates plaintext `claim_token`
- Hashes the token with `CLAIM_TOKEN_PEPPER`
- Inserts `token_hash` into `device_claim_tokens`
- Never stores plaintext claim tokens

## Local Checks

```bash
npm run build
npm run test:admin
```

The static pages can be previewed with:

```bash
npm run dev
```

The API route needs Vercel/serverless env vars to run end to end.
