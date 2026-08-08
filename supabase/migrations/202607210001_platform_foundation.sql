-- LotCaster hosted platform foundation.
-- Apply through the Supabase migration workflow; never paste service-role keys into the app.

create extension if not exists pgcrypto;

create type public.platform_role as enum (
  'master',
  'lotcaster_general_manager',
  'lotcaster_manager',
  'lotcaster_support'
);
create type public.dealership_role as enum ('owner', 'manager', 'salesperson');
create type public.account_state as enum ('invited', 'active', 'deactivated', 'archived');
create type public.assignment_state as enum ('assigned', 'in_progress', 'prepared', 'published', 'closed', 'cancelled');
create type public.inventory_origin as enum ('source', 'manual_wholesale');
create type public.approval_state as enum ('not_required', 'pending', 'approved', 'rejected');
create type public.listing_state as enum ('unknown', 'active', 'inactive', 'removed');
create type public.notification_delivery as enum ('in_app', 'email');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  email text not null,
  display_name text not null,
  phone text,
  state public.account_state not null default 'invited',
  must_change_password boolean not null default false,
  deactivated_at timestamptz,
  anonymize_after timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_deactivation_dates check (
    (state not in ('deactivated', 'archived')) or deactivated_at is not null
  )
);

create table public.platform_memberships (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  role public.platform_role not null,
  supervisor_id uuid references public.profiles(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.dealer_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  state public.account_state not null default 'invited',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.dealerships (
  id uuid primary key default gen_random_uuid(),
  dealer_group_id uuid references public.dealer_groups(id) on delete set null,
  name text not null,
  contact_name text,
  contact_email text,
  contact_phone text,
  timezone text not null default 'America/Chicago',
  state public.account_state not null default 'invited',
  subscription_plan text,
  billing_state text not null default 'not_configured',
  rankings_enabled boolean not null default false,
  require_second_wholesale_approver boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.dealership_memberships (
  dealership_id uuid not null references public.dealerships(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete restrict,
  role public.dealership_role not null,
  state public.account_state not null default 'invited',
  can_create_wholesale boolean not null default false,
  invited_by uuid references public.profiles(id) on delete set null,
  activated_at timestamptz,
  deactivated_at timestamptz,
  release_assignments_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (dealership_id, user_id)
);

create table public.support_assignments (
  dealership_id uuid not null references public.dealerships(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete restrict,
  assigned_by uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default now(),
  ended_at timestamptz,
  primary key (dealership_id, user_id)
);

create table public.inventory_sources (
  id uuid primary key default gen_random_uuid(),
  dealership_id uuid not null references public.dealerships(id) on delete cascade,
  source_url text not null,
  source_type text not null default 'authorized_web_listing',
  authorization_note text,
  enabled boolean not null default true,
  dealer_fee numeric(12,2) not null default 0 check (dealer_fee >= 0),
  source_prices_include_dealer_fee boolean not null default false,
  last_refresh_started_at timestamptz,
  last_refresh_completed_at timestamptz,
  last_refresh_state text,
  last_refresh_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  dealership_id uuid not null references public.dealerships(id) on delete cascade,
  inventory_source_id uuid references public.inventory_sources(id) on delete set null,
  origin public.inventory_origin not null default 'source',
  source_vehicle_key text,
  source_url text,
  vin text not null,
  stock_number text,
  year integer not null check (year between 1886 and 2200),
  make text not null,
  model text not null,
  trim text,
  body_style text not null,
  body_type text not null,
  exterior_color text not null,
  interior_color text not null,
  mileage integer not null check (mileage >= 0),
  vehicle_condition text not null,
  source_price numeric(12,2) not null check (source_price >= 0),
  posting_price numeric(12,2) not null check (posting_price >= 0),
  dealer_fee_applied numeric(12,2) not null default 0 check (dealer_fee_applied >= 0),
  source_says_fees_included boolean not null default false,
  price_verified_at timestamptz,
  price_verified_local_date date,
  price_evidence jsonb not null default '{}'::jsonb,
  approval_state public.approval_state not null default 'not_required',
  review_at timestamptz,
  manual_reason text,
  created_by uuid references public.profiles(id) on delete set null,
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  source_present boolean not null default true,
  removed_from_source_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (dealership_id, vin),
  constraint wholesale_review_required check (origin <> 'manual_wholesale' or review_at is not null),
  constraint fee_calculation_consistent check (
    posting_price = source_price + dealer_fee_applied
    and (not source_says_fees_included or dealer_fee_applied = 0)
  )
);

create table public.vehicle_photos (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  storage_path text,
  source_url text,
  position integer not null default 0 check (position >= 0),
  uploaded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint photo_has_location check (storage_path is not null or source_url is not null)
);

create table public.vehicle_assignments (
  id uuid primary key default gen_random_uuid(),
  dealership_id uuid not null references public.dealerships(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  assignee_id uuid not null references public.profiles(id) on delete restrict,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  state public.assignment_state not null default 'assigned',
  due_at timestamptz,
  priority smallint check (priority between 1 and 5),
  notes text,
  frozen_at timestamptz,
  release_to_pool_at timestamptz,
  closed_at timestamptz,
  close_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index vehicle_assignments_one_open_per_user
  on public.vehicle_assignments(vehicle_id, assignee_id)
  where state in ('assigned', 'in_progress', 'prepared');

create table public.publications (
  id uuid primary key default gen_random_uuid(),
  dealership_id uuid not null references public.dealerships(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  assignment_id uuid references public.vehicle_assignments(id) on delete set null,
  published_by uuid not null references public.profiles(id) on delete restrict,
  marketplace_url text,
  state public.listing_state not null default 'unknown',
  manual_confirmation_at timestamptz,
  extension_confirmation_at timestamptz,
  manager_verified_at timestamptz,
  manager_verified_by uuid references public.profiles(id) on delete set null,
  published_at timestamptz not null,
  reopen_review_at timestamptz not null,
  posted_price numeric(12,2) not null,
  posted_mileage integer not null,
  description text not null,
  photo_snapshot jsonb not null default '[]'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.protected_field_corrections (
  id uuid primary key default gen_random_uuid(),
  dealership_id uuid not null references public.dealerships(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  field_name text not null check (field_name in ('vin','stock_number','source_price','posting_price','dealer_fee_applied','mileage','vehicle_condition')),
  original_value jsonb not null,
  proposed_value jsonb not null,
  approved_value jsonb,
  reason text not null,
  evidence jsonb not null default '{}'::jsonb,
  state public.approval_state not null default 'pending',
  requested_by uuid not null references public.profiles(id) on delete restrict,
  decided_by uuid references public.profiles(id) on delete restrict,
  requested_at timestamptz not null default now(),
  decided_at timestamptz
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  dealership_id uuid references public.dealerships(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null,
  required boolean not null default false,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.notification_preferences (
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null,
  delivery public.notification_delivery not null,
  enabled boolean not null default true,
  primary key (user_id, event_type, delivery)
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  dealership_id uuid references public.dealerships(id) on delete set null,
  actor_id uuid references public.profiles(id) on delete set null,
  assisted_user_id uuid references public.profiles(id) on delete set null,
  event_type text not null,
  entity_type text,
  entity_id text,
  reason text,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

-- Authorization helpers bypass membership RLS only to answer narrowly scoped questions.
create or replace function public.current_platform_role()
returns public.platform_role
language sql stable security definer
set search_path = public
as $$ select role from public.platform_memberships where user_id = auth.uid() $$;

create or replace function public.is_master()
returns boolean
language sql stable security definer
set search_path = public
as $$ select coalesce(public.current_platform_role() = 'master', false) $$;

create or replace function public.supports_dealership(target_dealership uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select public.is_master() or exists (
    select 1 from public.support_assignments sa
    join public.platform_memberships pm on pm.user_id = sa.user_id
    join public.profiles p on p.id = sa.user_id
    where sa.user_id = auth.uid()
      and sa.dealership_id = target_dealership
      and sa.ended_at is null
      and p.state = 'active'
  )
$$;

create or replace function public.has_dealership_role(target_dealership uuid, allowed public.dealership_role[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.dealership_memberships dm
    join public.profiles p on p.id = dm.user_id
    where dm.user_id = auth.uid()
      and dm.dealership_id = target_dealership
      and dm.role = any(allowed)
      and dm.state = 'active'
      and p.state = 'active'
  )
$$;

create or replace function public.can_view_dealership(target_dealership uuid)
returns boolean
language sql stable
as $$
  select public.supports_dealership(target_dealership)
      or public.has_dealership_role(target_dealership, array['owner','manager','salesperson']::public.dealership_role[])
$$;

create or replace function public.can_manage_dealership(target_dealership uuid)
returns boolean
language sql stable
as $$
  select public.supports_dealership(target_dealership)
      or public.has_dealership_role(target_dealership, array['owner','manager']::public.dealership_role[])
$$;

alter table public.profiles enable row level security;
alter table public.platform_memberships enable row level security;
alter table public.dealer_groups enable row level security;
alter table public.dealerships enable row level security;
alter table public.dealership_memberships enable row level security;
alter table public.support_assignments enable row level security;
alter table public.inventory_sources enable row level security;
alter table public.vehicles enable row level security;
alter table public.vehicle_photos enable row level security;
alter table public.vehicle_assignments enable row level security;
alter table public.publications enable row level security;
alter table public.protected_field_corrections enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.audit_events enable row level security;

create policy profiles_read_self_or_managed on public.profiles for select
  using (id = auth.uid() or public.is_master() or exists (
    select 1 from public.dealership_memberships target
    where target.user_id = profiles.id and public.can_manage_dealership(target.dealership_id)
  ) or exists (
    select 1 from public.support_assignments target
    where target.user_id = profiles.id and public.supports_dealership(target.dealership_id)
  ));

create policy platform_memberships_read on public.platform_memberships for select
  using (user_id = auth.uid() or public.is_master() or public.current_platform_role() = 'lotcaster_general_manager');

create policy dealer_groups_read on public.dealer_groups for select
  using (public.is_master() or exists (
    select 1 from public.dealerships d where d.dealer_group_id = dealer_groups.id and public.can_view_dealership(d.id)
  ));

create policy dealerships_read on public.dealerships for select
  using (public.can_view_dealership(id));

create policy dealership_memberships_read on public.dealership_memberships for select
  using (user_id = auth.uid() or public.can_manage_dealership(dealership_id));

create policy support_assignments_read on public.support_assignments for select
  using (user_id = auth.uid() or public.is_master() or public.current_platform_role() = 'lotcaster_general_manager' or public.has_dealership_role(dealership_id, array['owner']::public.dealership_role[]));

create policy inventory_sources_read on public.inventory_sources for select
  using (public.can_view_dealership(dealership_id));
create policy inventory_sources_manage on public.inventory_sources for all
  using (public.can_manage_dealership(dealership_id))
  with check (public.can_manage_dealership(dealership_id));

create policy vehicles_read on public.vehicles for select
  using (
    public.can_manage_dealership(dealership_id)
    or exists (
      select 1 from public.vehicle_assignments va
      where va.vehicle_id = vehicles.id and va.assignee_id = auth.uid()
        and va.state in ('assigned','in_progress','prepared','published')
    )
  );
create policy vehicles_manager_write on public.vehicles for all
  using (public.can_manage_dealership(dealership_id))
  with check (public.can_manage_dealership(dealership_id));

create policy vehicle_photos_read on public.vehicle_photos for select
  using (exists (select 1 from public.vehicles v where v.id = vehicle_photos.vehicle_id));
create policy vehicle_photos_add on public.vehicle_photos for insert
  with check (uploaded_by = auth.uid() and exists (select 1 from public.vehicles v where v.id = vehicle_photos.vehicle_id));

create policy assignments_read on public.vehicle_assignments for select
  using (assignee_id = auth.uid() or public.can_manage_dealership(dealership_id));
create policy assignments_manage on public.vehicle_assignments for all
  using (public.can_manage_dealership(dealership_id))
  with check (public.can_manage_dealership(dealership_id));
create policy assignments_assignee_progress on public.vehicle_assignments for update
  using (assignee_id = auth.uid())
  with check (assignee_id = auth.uid());

create policy publications_read on public.publications for select
  using (published_by = auth.uid() or public.can_manage_dealership(dealership_id));
create policy publications_create on public.publications for insert
  with check (published_by = auth.uid() and public.can_view_dealership(dealership_id));
create policy publications_manager_update on public.publications for update
  using (public.can_manage_dealership(dealership_id))
  with check (public.can_manage_dealership(dealership_id));

create policy corrections_read on public.protected_field_corrections for select
  using (requested_by = auth.uid() or public.can_manage_dealership(dealership_id));
create policy corrections_manager_create on public.protected_field_corrections for insert
  with check (requested_by = auth.uid() and public.can_manage_dealership(dealership_id));
create policy corrections_owner_or_support_decide on public.protected_field_corrections for update
  using (public.supports_dealership(dealership_id) or public.has_dealership_role(dealership_id, array['owner']::public.dealership_role[]))
  with check (public.supports_dealership(dealership_id) or public.has_dealership_role(dealership_id, array['owner']::public.dealership_role[]));

create policy notifications_own_read on public.notifications for select using (recipient_id = auth.uid());
create policy notifications_own_update on public.notifications for update
  using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());
create policy notification_preferences_own on public.notification_preferences for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy audit_read on public.audit_events for select
  using (actor_id = auth.uid() or (dealership_id is not null and (
    public.supports_dealership(dealership_id)
    or public.has_dealership_role(dealership_id, array['owner','manager']::public.dealership_role[])
  )));

-- Direct client writes are intentionally absent for profiles, platform roles,
-- memberships, support assignments, notifications, and audit events. Trusted
-- server functions/service processes own those mutations and must emit audits.

create index dealership_memberships_user_idx on public.dealership_memberships(user_id, state);
create index support_assignments_user_idx on public.support_assignments(user_id) where ended_at is null;
create index vehicles_dealership_idx on public.vehicles(dealership_id, source_present);
create index assignments_assignee_idx on public.vehicle_assignments(assignee_id, state);
create index assignments_dealership_idx on public.vehicle_assignments(dealership_id, state, due_at);
create index publications_vehicle_idx on public.publications(vehicle_id, published_at desc);
create index notifications_recipient_idx on public.notifications(recipient_id, read_at, created_at desc);
create index audit_dealership_idx on public.audit_events(dealership_id, occurred_at desc);
