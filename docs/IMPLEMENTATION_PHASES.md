# LotCaster Implementation Phases

## Phase A — Preserve and baseline

- Preserve the working inventory, price, photo, and extension behavior.
- Add regression coverage for daily price verification, dealer-fee treatment, photo retention, and Edge/Chrome extension payloads.
- Remove single-assignee assumptions from the domain model without changing the current user experience prematurely.

## Phase B — Hosted identity and tenancy

- Create Supabase environments for development and production.
- Apply the multi-tenant schema and row-level security policies.
- Add invitation, temporary-password, password-reset, session, and dealership-switching flows.
- Move role enforcement from editable local files to server-verified memberships.
- Retain an explicit local-development mode; never allow it in a production build.

## Phase C — Dealership workflow

- Add many-to-many vehicle assignments, duplicate warnings, priority, due dates, notes, and closure behavior.
- Add daily source verification, price publication gates, source-removal handling, and correction approvals.
- Add wholesale creation, approval, review dates, and red-border presentation.
- Add in-app notification center and email event delivery.

## Phase D — Support and administration

- Add dealer groups, locations, support lists, and the restricted dealership selector.
- Add Support View with required reasons and complete audit history.
- Add user deactivation, 48-hour assignment release, 30-day anonymization, and remote session revocation.
- Add approved-plan onboarding and Master-only exception controls.

## Phase E — Publication evidence and extension

- Authenticate extension-to-LotCaster messages without exposing long-lived secrets.
- Detect supported Facebook success states in Edge and Chrome.
- Submit publication evidence and valid listing links.
- Preserve manual Mark Published as an independent verification path.
- Never automate Facebook login or the final Publish action.

## Phase F — Production readiness

- Add automated role-boundary, tenant-isolation, invitation, reset, notification, inventory, price, photo, and extension tests.
- Add backup/restore, monitoring, email delivery diagnostics, privacy exports, retention jobs, and incident logging.
- Pilot with at least one additional authorized dealership before billing broadly.
- Obtain legal review of data retention, source authorization, Facebook workflow, privacy, and customer terms.

## External setup required

Implementation can prepare all code and migrations locally. Activating hosted behavior requires:

1. A Supabase organization and project.
2. Development and production project URLs and public keys.
3. Server-only service credentials stored outside the repository.
4. Auth email templates and an approved sending domain before production.
5. A later billing-provider account; billing is not required to build or test core dealership workflows.
