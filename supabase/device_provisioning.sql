create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create table if not exists public.devices (
    device_id text primary key,
    display_name text not null default 'Bathroom Monitor',
    model text,
    hardware_serial text,
    batch_id text,
    notes text,
    connection_status text not null default 'unprovisioned'
        check (connection_status in ('unprovisioned', 'online', 'offline', 'connecting')),
    last_seen_at timestamptz,
    last_motion_at timestamptz,
    firmware_version text,
    ip_address text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.devices
    add column if not exists display_name text not null default 'Bathroom Monitor',
    add column if not exists model text,
    add column if not exists hardware_serial text,
    add column if not exists batch_id text,
    add column if not exists notes text,
    add column if not exists connection_status text not null default 'unprovisioned',
    add column if not exists last_seen_at timestamptz,
    add column if not exists last_motion_at timestamptz,
    add column if not exists firmware_version text,
    add column if not exists ip_address text,
    add column if not exists updated_at timestamptz not null default now(),
    add column if not exists created_at timestamptz not null default now();

alter table public.devices
    alter column connection_status set default 'unprovisioned';

alter table public.devices
    drop constraint if exists devices_connection_status_check;

alter table public.devices
    add constraint devices_connection_status_check
    check (connection_status in ('unprovisioned', 'online', 'offline', 'connecting'));

drop trigger if exists set_devices_updated_at on public.devices;
create trigger set_devices_updated_at
    before update on public.devices
    for each row
    execute function public.set_updated_at();

create table if not exists public.device_claim_tokens (
    id uuid primary key default gen_random_uuid(),
    device_id text not null references public.devices(device_id) on delete cascade,
    token_hash text not null,
    expires_at timestamptz,
    used_at timestamptz,
    created_at timestamptz not null default now()
);

create index if not exists device_claim_tokens_device_id_idx
    on public.device_claim_tokens (device_id);

create index if not exists device_claim_tokens_token_hash_idx
    on public.device_claim_tokens (token_hash);

create unique index if not exists devices_numbered_display_name_unique_idx
    on public.devices (lower(trim(display_name)))
    where display_name ~* '^Device[[:space:]]+[0-9]+$';

alter table public.devices enable row level security;
alter table public.device_claim_tokens enable row level security;
