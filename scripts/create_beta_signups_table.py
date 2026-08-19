#!/usr/bin/env python3
"""Create the Supabase beta_signups table using a Postgres connection URL.

Usage:
    python scripts/create_beta_signups_table.py

Environment:
    SUPABASE_DB_URL or DATABASE_URL must be a Postgres connection string.

This script requires psycopg:
    python -m pip install "psycopg[binary]"
"""

from __future__ import annotations

import os
import sys


BETA_SIGNUPS_SQL = """
create table if not exists public.beta_signups (
    id uuid primary key default gen_random_uuid(),
    first_name text not null check (length(trim(first_name)) > 0),
    last_name text not null check (length(trim(last_name)) > 0),
    email text not null check (email ~* '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'),
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

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

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
        and email ~* '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'
        and length(trim(phone)) >= 7
        and source = 'landing_page'
        and status = 'new'
    );
"""


def main() -> int:
    database_url = os.environ.get("SUPABASE_DB_URL") or os.environ.get("DATABASE_URL")
    if not database_url:
        print("Set SUPABASE_DB_URL or DATABASE_URL to your Supabase Postgres connection string.", file=sys.stderr)
        return 2

    try:
        import psycopg
    except ImportError:
        print('Install psycopg first: python -m pip install "psycopg[binary]"', file=sys.stderr)
        return 2

    with psycopg.connect(database_url) as connection:
        with connection.cursor() as cursor:
            cursor.execute(BETA_SIGNUPS_SQL)

    print("beta_signups table and anon insert policy are ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
