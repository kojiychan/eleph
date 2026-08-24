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
    connection_status text not null default 'online',
    last_seen_at timestamptz,
    last_motion_at timestamptz,
    firmware_version text,
    ip_address text,
    updated_at timestamptz not null default now(),
    created_at timestamptz not null default now()
);

alter table public.devices
    add column if not exists display_name text not null default 'Bathroom Monitor',
    add column if not exists connection_status text not null default 'online',
    add column if not exists last_seen_at timestamptz,
    add column if not exists last_motion_at timestamptz,
    add column if not exists firmware_version text,
    add column if not exists ip_address text,
    add column if not exists updated_at timestamptz not null default now(),
    add column if not exists created_at timestamptz not null default now();

create index if not exists devices_last_seen_idx
    on public.devices (last_seen_at desc);

drop trigger if exists set_devices_updated_at on public.devices;
create trigger set_devices_updated_at
    before update on public.devices
    for each row
    execute function public.set_updated_at();

alter table public.devices enable row level security;

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
