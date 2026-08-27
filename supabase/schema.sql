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

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

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
    model text,
    hardware_serial text,
    batch_id text,
    notes text,
    serial_number text,
    room_name text,
    monitored_person_name text,
    connection_status text not null default 'unprovisioned'
        check (connection_status in ('unprovisioned', 'online', 'offline', 'connecting')),
    is_online boolean generated always as (connection_status = 'online') stored,
    last_connected_at timestamptz,
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

create index if not exists devices_last_seen_idx
    on public.devices (last_seen_at desc);

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

alter table public.device_claim_tokens enable row level security;

alter table public.devices enable row level security;

drop policy if exists "allow anon device reads" on public.devices;
create policy "allow anon device reads"
    on public.devices
    for select
    to anon
    using (length(trim(device_id)) > 0);

drop policy if exists "allow anon device heartbeat inserts" on public.devices;
create policy "allow anon device heartbeat inserts"
    on public.devices
    for insert
    to anon
    with check (
        length(trim(device_id)) > 0
        and connection_status in ('online', 'offline', 'connecting')
    );

drop policy if exists "allow anon device heartbeat updates" on public.devices;
create policy "allow anon device heartbeat updates"
    on public.devices
    for update
    to anon
    using (length(trim(device_id)) > 0)
    with check (
        length(trim(device_id)) > 0
        and connection_status in ('online', 'offline', 'connecting')
    );

create or replace function public.touch_device_from_motion_event()
returns trigger
language plpgsql
as $$
begin
    insert into public.devices (
        device_id,
        connection_status,
        last_seen_at,
        last_motion_at
    )
    values (
        new.device_id,
        'online',
        now(),
        new.detected_at
    )
    on conflict (device_id) do update
    set
        connection_status = 'online',
        last_seen_at = now(),
        last_motion_at = case
            when public.devices.last_motion_at is null
                or public.devices.last_motion_at < excluded.last_motion_at
                then excluded.last_motion_at
            else public.devices.last_motion_at
        end;

    return new;
end;
$$;

drop trigger if exists touch_device_from_motion_event on public.motion_events;
create trigger touch_device_from_motion_event
    after insert on public.motion_events
    for each row
    execute function public.touch_device_from_motion_event();

create table if not exists public.motion_sessions (
    id uuid primary key default gen_random_uuid(),
    device_id text not null,
    started_at timestamptz not null,
    ended_at timestamptz,
    motion_count integer not null default 1,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists motion_sessions_device_started_idx
    on public.motion_sessions (device_id, started_at desc);

create unique index if not exists motion_sessions_open_device_idx
    on public.motion_sessions (device_id)
    where ended_at is null;

drop trigger if exists set_motion_sessions_updated_at on public.motion_sessions;
create trigger set_motion_sessions_updated_at
    before update on public.motion_sessions
    for each row
    execute function public.set_updated_at();

alter table public.motion_sessions enable row level security;

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

drop policy if exists "users can read linked motion sessions" on public.motion_sessions;
create policy "users can read linked motion sessions"
    on public.motion_sessions
    for select
    to authenticated
    using (
        exists (
            select 1
            from public.user_devices
            where user_devices.user_id = auth.uid()
                and user_devices.device_id = motion_sessions.device_id
        )
    );

create or replace function public.record_device_motion(
    p_device_id text,
    p_detected_at timestamptz,
    p_sensor_type text,
    p_metadata jsonb,
    p_insert_motion_event boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    current_session public.motion_sessions%rowtype;
    session_action text;
begin
    if length(trim(p_device_id)) = 0 then
        raise exception 'device_id is required';
    end if;

    if p_sensor_type not in ('infrared_obstacle', 'mmwave_c4001', 'simulated') then
        raise exception 'unsupported sensor_type: %', p_sensor_type;
    end if;

    insert into public.devices (
        device_id,
        connection_status,
        last_seen_at,
        last_motion_at
    )
    values (
        p_device_id,
        'online',
        now(),
        p_detected_at
    )
    on conflict (device_id) do update
    set
        connection_status = 'online',
        last_seen_at = now(),
        last_motion_at = greatest(
            coalesce(public.devices.last_motion_at, p_detected_at),
            p_detected_at
        );

    if p_insert_motion_event then
        insert into public.motion_events (
            device_id,
            event_type,
            detected_at,
            sensor_type,
            metadata
        )
        values (
            p_device_id,
            'motion_detected',
            p_detected_at,
            p_sensor_type,
            coalesce(p_metadata, '{}'::jsonb)
        );
    end if;

    select *
    into current_session
    from public.motion_sessions
    where device_id = p_device_id
        and ended_at is null
    order by started_at desc
    limit 1
    for update;

    if not found then
        insert into public.motion_sessions (
            device_id,
            started_at,
            motion_count
        )
        values (
            p_device_id,
            p_detected_at,
            1
        )
        returning * into current_session;
        session_action := 'started';
    else
        update public.motion_sessions
        set motion_count = motion_count + 1
        where id = current_session.id
        returning * into current_session;
        session_action := 'updated';
    end if;

    return jsonb_build_object(
        'motion_event_inserted', p_insert_motion_event,
        'session_action', session_action,
        'session_id', current_session.id,
        'motion_count', current_session.motion_count
    );
end;
$$;

create or replace function public.end_motion_session(
    p_device_id text,
    p_ended_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    ended_session public.motion_sessions%rowtype;
begin
    if length(trim(p_device_id)) = 0 then
        raise exception 'device_id is required';
    end if;

    update public.motion_sessions
    set ended_at = p_ended_at
    where id = (
        select id
        from public.motion_sessions
        where device_id = p_device_id
            and ended_at is null
        order by started_at desc
        limit 1
    )
    returning * into ended_session;

    if not found then
        return jsonb_build_object('ended', false);
    end if;

    return jsonb_build_object(
        'ended', true,
        'session_id', ended_session.id,
        'ended_at', ended_session.ended_at
    );
end;
$$;

create or replace function public.close_stale_motion_sessions(
    p_idle_timeout_seconds double precision default 180
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    closed_count integer;
begin
    update public.motion_sessions
    set ended_at = updated_at
    where ended_at is null
        and updated_at < now() - make_interval(secs => p_idle_timeout_seconds);

    get diagnostics closed_count = row_count;

    return jsonb_build_object('closed_count', closed_count);
end;
$$;

grant execute on function public.record_device_motion(text, timestamptz, text, jsonb, boolean)
    to anon, authenticated;
grant execute on function public.end_motion_session(text, timestamptz)
    to anon, authenticated;
grant execute on function public.close_stale_motion_sessions(double precision)
    to anon, authenticated;

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
    caution_alerts_enabled boolean not null default true,
    critical_alerts_enabled boolean not null default true,
    push_notifications_enabled boolean not null default true,
    sms_notifications_enabled boolean not null default false,
    disconnected_alerts_enabled boolean not null default true,
    reconnected_alerts_enabled boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, device_id)
);

alter table public.device_settings
    add column if not exists caution_alerts_enabled boolean not null default true,
    add column if not exists critical_alerts_enabled boolean not null default true;

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

create table if not exists public.beta_signups (
    id uuid primary key default gen_random_uuid(),
    first_name text not null check (length(trim(first_name)) > 0),
    last_name text not null check (length(trim(last_name)) > 0),
    email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    email_normalized text generated always as (lower(trim(email))) stored,
    phone text not null check (length(trim(phone)) >= 7),
    source text not null default 'landing_page',
    status text not null default 'new'
        check (status in ('new', 'contacted', 'invited', 'accepted', 'declined')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (email_normalized)
);

create index if not exists beta_signups_created_at_idx
    on public.beta_signups (created_at desc);

drop trigger if exists set_beta_signups_updated_at on public.beta_signups;
create trigger set_beta_signups_updated_at
    before update on public.beta_signups
    for each row
    execute function public.set_updated_at();

alter table public.beta_signups enable row level security;

drop policy if exists "allow anon beta signup inserts" on public.beta_signups;
create policy "allow anon beta signup inserts"
    on public.beta_signups
    for insert
    to anon
    with check (
        length(trim(first_name)) > 0
        and length(trim(last_name)) > 0
        and email = lower(trim(email))
        and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        and length(trim(phone)) >= 7
        and source = 'landing_page'
        and status = 'new'
    );
