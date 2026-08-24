-- Beta-only policy: every signed-in tester can read the shared bathroom monitor.
-- Remove or replace this with per-user ownership policies before a multi-device launch.

drop policy if exists "authenticated users can read beta monitor motion" on public.motion_events;
create policy "authenticated users can read beta monitor motion"
    on public.motion_events
    for select
    to authenticated
    using (device_id = 'bathroom-monitor-001');

drop policy if exists "authenticated users can read beta monitor device" on public.devices;
create policy "authenticated users can read beta monitor device"
    on public.devices
    for select
    to authenticated
    using (device_id = 'bathroom-monitor-001');

drop policy if exists "authenticated users can read beta monitor sessions" on public.motion_sessions;
create policy "authenticated users can read beta monitor sessions"
    on public.motion_sessions
    for select
    to authenticated
    using (device_id = 'bathroom-monitor-001');
