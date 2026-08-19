create table if not exists public.motion_events (
    id uuid primary key default gen_random_uuid(),
    device_id text not null,
    event_type text not null,
    detected_at timestamptz not null,
    sensor_type text not null default 'infrared_obstacle',
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists motion_events_device_time_idx
    on public.motion_events (device_id, detected_at desc);

alter table public.motion_events enable row level security;

drop policy if exists "allow anon motion event inserts" on public.motion_events;
create policy "allow anon motion event inserts"
    on public.motion_events
    for insert
    to anon
    with check (
        event_type = 'motion_detected'
        and sensor_type in ('infrared_obstacle', 'mmwave_c4001', 'simulated')
        and length(trim(device_id)) > 0
    );

drop policy if exists "allow anon motion event reads" on public.motion_events;
create policy "allow anon motion event reads"
    on public.motion_events
    for select
    to anon
    using (length(trim(device_id)) > 0);

create table if not exists public.devices (
    device_id text primary key,
    display_name text not null default 'Bathroom Monitor',
    serial_number text,
    room_name text,
    monitored_person_name text,
    connection_status text not null default 'online'
        check (connection_status in ('online', 'offline', 'connecting')),
    is_online boolean generated always as (connection_status = 'online') stored,
    last_connected_at timestamptz,
    last_seen_at timestamptz,
    last_motion_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.devices enable row level security;

drop policy if exists "allow anon device reads" on public.devices;
create policy "allow anon device reads"
    on public.devices
    for select
    to anon
    using (length(trim(device_id)) > 0);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    first_name text,
    last_name text,
    display_name text,
    email text,
    phone text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
    before update on public.profiles
    for each row
    execute function public.set_updated_at();

alter table public.profiles enable row level security;

drop policy if exists "users can read own profile" on public.profiles;
create policy "users can read own profile"
    on public.profiles
    for select
    to authenticated
    using (id = auth.uid());

drop policy if exists "users can create own profile" on public.profiles;
create policy "users can create own profile"
    on public.profiles
    for insert
    to authenticated
    with check (id = auth.uid());

drop policy if exists "users can update own profile" on public.profiles;
create policy "users can update own profile"
    on public.profiles
    for update
    to authenticated
    using (id = auth.uid())
    with check (id = auth.uid());

create table if not exists public.user_devices (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    device_id text not null references public.devices(device_id) on delete cascade,
    role text not null default 'owner'
        check (role in ('owner', 'caregiver', 'viewer')),
    created_at timestamptz not null default now(),
    unique (user_id, device_id)
);

create index if not exists user_devices_user_id_idx
    on public.user_devices (user_id);

create index if not exists user_devices_device_id_idx
    on public.user_devices (device_id);

alter table public.user_devices enable row level security;

drop policy if exists "users can read own device links" on public.user_devices;
create policy "users can read own device links"
    on public.user_devices
    for select
    to authenticated
    using (user_id = auth.uid());

drop policy if exists "users can claim device links" on public.user_devices;
create policy "users can claim device links"
    on public.user_devices
    for insert
    to authenticated
    with check (user_id = auth.uid());

drop policy if exists "owners can update own device links" on public.user_devices;
create policy "owners can update own device links"
    on public.user_devices
    for update
    to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

drop policy if exists "users can remove own device links" on public.user_devices;
create policy "users can remove own device links"
    on public.user_devices
    for delete
    to authenticated
    using (user_id = auth.uid());

drop policy if exists "users can read linked devices" on public.devices;
create policy "users can read linked devices"
    on public.devices
    for select
    to authenticated
    using (
        exists (
            select 1
            from public.user_devices
            where user_devices.user_id = auth.uid()
                and user_devices.device_id = devices.device_id
        )
    );

drop policy if exists "users can read linked motion events" on public.motion_events;
create policy "users can read linked motion events"
    on public.motion_events
    for select
    to authenticated
    using (
        exists (
            select 1
            from public.user_devices
            where user_devices.user_id = auth.uid()
                and user_devices.device_id = motion_events.device_id
        )
    );

create table if not exists public.device_settings (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    device_id text not null references public.devices(device_id) on delete cascade,
    monitored_person_name text not null default 'Grandma',
    relationship text,
    monitor_name text not null default 'Grandma''s Bathroom',
    room_name text not null default 'Hall Bathroom',
    caution_inactivity_minutes integer not null default 120
        check (caution_inactivity_minutes > 0),
    critical_inactivity_minutes integer not null default 240
        check (critical_inactivity_minutes > caution_inactivity_minutes),
    quiet_hours_start time,
    quiet_hours_end time,
    timezone text not null default 'America/Los_Angeles',
    push_notifications_enabled boolean not null default true,
    sms_notifications_enabled boolean not null default false,
    disconnected_alerts_enabled boolean not null default true,
    reconnected_alerts_enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, device_id)
);

create index if not exists device_settings_user_id_idx
    on public.device_settings (user_id);

create index if not exists device_settings_device_id_idx
    on public.device_settings (device_id);

drop trigger if exists set_device_settings_updated_at on public.device_settings;
create trigger set_device_settings_updated_at
    before update on public.device_settings
    for each row
    execute function public.set_updated_at();

alter table public.device_settings enable row level security;

drop policy if exists "users can read own device settings" on public.device_settings;
create policy "users can read own device settings"
    on public.device_settings
    for select
    to authenticated
    using (
        user_id = auth.uid()
        and exists (
            select 1
            from public.user_devices
            where user_devices.user_id = auth.uid()
                and user_devices.device_id = device_settings.device_id
        )
    );

drop policy if exists "users can create own device settings" on public.device_settings;
create policy "users can create own device settings"
    on public.device_settings
    for insert
    to authenticated
    with check (
        user_id = auth.uid()
        and exists (
            select 1
            from public.user_devices
            where user_devices.user_id = auth.uid()
                and user_devices.device_id = device_settings.device_id
        )
    );

drop policy if exists "users can update own device settings" on public.device_settings;
create policy "users can update own device settings"
    on public.device_settings
    for update
    to authenticated
    using (
        user_id = auth.uid()
        and exists (
            select 1
            from public.user_devices
            where user_devices.user_id = auth.uid()
                and user_devices.device_id = device_settings.device_id
        )
    )
    with check (
        user_id = auth.uid()
        and exists (
            select 1
            from public.user_devices
            where user_devices.user_id = auth.uid()
                and user_devices.device_id = device_settings.device_id
        )
    );
