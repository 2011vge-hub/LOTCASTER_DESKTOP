# LotCaster Platform Blueprint

Status: Authoritative product and access-control specification  
Decision date: 2026-07-21

## Product boundary

LotCaster is a multi-tenant dealership workspace. A dealership's users may only access data belonging to an explicitly authorized location. LotCaster employees may only access dealerships on their support list, except for Masters. All sensitive reads and writes are enforced by the hosted service and recorded in an audit trail.

Final publication to Facebook remains a deliberate user action. The extension may prepare the form and detect Facebook's success state, but it may not automate login or silently publish.

## Roles

### LotCaster Master

Masters have platform-wide operational access and demonstration posting capability. Only Masters may:

1. Create, remove, or promote Masters.
2. Change platform-wide pricing.
3. Permanently close a dealership account.
4. View all LotCaster financial information.
5. Change global security policies.
6. Access every dealership without a support assignment.
7. Restore archived users or dealerships.

### LotCaster General Manager

General Managers may onboard and activate dealerships on approved plans, manage routine billing setup, assign support coverage, create and supervise LotCaster Managers and support employees, and enter dealerships on their support list. Exceptions such as custom pricing, refunds, waived billing, or permanent closure require a Master.

### LotCaster Manager

LotCaster Managers may access only assigned dealerships, view dealership contacts, provide Dealer Owner-level workflow support, supervise assigned support employees, initiate account recovery, and help investigate protected-field corrections. They cannot promote Masters or General Managers or change platform-wide financial/security settings.

### LotCaster Support Employee

Support employees may use Support View for assigned dealerships and perform only the capabilities granted by their supervising LotCaster Manager or General Manager. They cannot silently impersonate dealership users.

### Dealer Owner

Dealer Owners control one or more authorized dealership locations, location settings, dealership Managers and Salespeople, location reports, and protected-field correction approvals. They cannot access LotCaster internal staffing or company-wide billing.

### Dealership Manager

Dealership Managers manage Salespeople, assignments, listing verification, fees and add-ons, source verification, wholesale approvals, reminders, and operational workflows for authorized locations. They may activate or deactivate roles beneath them and remotely revoke their sessions.

### Salesperson

Salespeople see only their own assignments and listing work. They may prepare listings, add their own photos and permitted description information, and manually confirm publication. VIN, stock number, verified price, fee treatment, mileage, and condition are protected. Wholesale creation is available only when granted and requires Manager approval.

## Tenant and location model

- A dealer group may contain multiple dealership locations.
- Every location has its own inventory sources, fee rules, staff membership, assignments, reports, notifications, price verification, and publication history.
- An authorized Owner or employee may belong to multiple locations and must select a location after login.
- The active location is always visible.
- LotCaster employee dealership selectors contain only locations on their support list, except for Masters.
- Cross-location reads and writes are denied by default.

## Authentication and sessions

- Onboarding supports emailed invitation links and randomly generated temporary passwords.
- Temporary passwords are single-use and require a new password at next login.
- Personal-device sessions may last up to 30 days when Remember this device is selected.
- Shared-device sessions last no more than 12 hours and end when the browser closes.
- Concurrent phone, home, and work-device sessions are allowed.
- Password reset or deactivation revokes all active sessions immediately.
- Dealership Managers may remotely sign out subordinate dealership users.
- Password reset events notify the user and the dealership's assigned LotCaster Manager.
- Deactivated accounts cannot access the portal for any reason.
- Deactivated assignments are frozen, may be manually reassigned immediately, and return to the pool automatically after 48 hours.
- After 30 days, deactivated user identity is anonymized while operational records remain archived.

## Inventory and price verification

- Opening LotCaster starts an inventory refresh for the selected location.
- Saved inventory is not shown to Salespeople as current while the refresh is pending.
- A failed source request is retried and then displays a clear error directing the user to their immediate Manager.
- Salespeople cannot build or publish a listing until that vehicle's price is verified for the current dealership-local calendar date.
- Refresh failures notify dealership Managers, Owners, and assigned LotCaster support staff.
- Only vehicles currently present on an authorized source are active source inventory.
- Removed source vehicles are blocked from new publication, unfinished assignments are cancelled, history is preserved, and leadership receives follow-up tasks for any Marketplace listing believed active.
- The source price is used as-is when the listing indicates dealer fees are included.
- Otherwise LotCaster adds only the dealer-entered fee configured for that location. It never invents or substitutes another fee.
- Source value, posting value, fee treatment, verification time, source URL, and evidence are preserved.

## Protected-field corrections

- Salespeople cannot edit protected fields.
- Dealership Managers may propose a correction.
- Dealer Owners may approve it.
- An assigned LotCaster General Manager may approve while supporting a dealership when an Owner is unavailable; the Owner is notified.
- Masters retain emergency authority.
- The original value, proposed value, approved value, reason, evidence, requester, approver, and timestamps remain auditable.

## Assignments

- A vehicle can have multiple active assignments.
- Assigning an already-assigned vehicle always shows a non-disableable confirmation dialog.
- Duplicate-assignment notifications may be muted per recipient, but the confirmation dialog may not be disabled.
- An assignment contains assignee, location, vehicle, due date, optional priority, status, notes, and publication record.
- “All inventory” for a Manager means all active inventory in the selected location.
- “All inventory” for a Salesperson means all inventory assigned to that Salesperson.
- The first verified successful publication closes other active assignments for the vehicle.
- Three days later, if the vehicle remains on the source, the Manager is asked whether to reopen it. LotCaster does not automatically choose.
- Default reminders occur at assignment, 24 hours before due, when overdue, daily while overdue, and escalate to the Owner after three overdue days.

## Publication verification

Publication uses multiple evidence sources:

1. Salesperson manually selects Mark Published after Facebook confirms success.
2. The extension detects Facebook's success state.
3. A valid Marketplace listing URL may be attached and checked when permitted.
4. A Manager may verify a valid link or manually set an unknown listing to active.

Publication records preserve the listing URL, timestamp, publisher, verified price, mileage, description, and photo set. Screenshots are not required.

## Manual and wholesale inventory

- Managers may create and assign manual inventory.
- Salespeople may create it only when granted permission.
- Salesperson-created units remain pending until Manager approval.
- Build Listing Packet remains disabled until approval.
- Required fields: VIN, year, make, model, price, exterior color, interior color, body style, body type, fee treatment, mileage, at least one photo, and review date.
- Review date defaults to 14 days and can be changed by the creator.
- Reason is optional.
- Manual/wholesale units use a visible red border throughout operational views.
- Managers may approve their own entries; self-approval is recorded. An Owner may enable a second-approver requirement.
- Managers and Owners can see Salesperson-created units in the creator's profile and Active Listings.

## Notifications

Notification delivery uses in-app and email. SMS is excluded.

Required operational events include deactivation, password reset, refresh failure, removed inventory with an active listing, protected-field attempts/corrections, and wholesale review dates. Duplicate assignment confirmation is always required. Recipients may configure non-critical assignment, change, publication, overdue, and summary notifications, but required audit events remain visible in the notification center.

## Support View and auditing

- LotCaster staff never silently impersonate a dealership user.
- Support View displays the effective role and the supporting employee's identity.
- If a future assisted-action mode is added, both identities are attached to every action.
- Support entry/exit, reason, dealership, records touched, changes, password resets, protected corrections, access changes, and billing changes are audited.
- Dealer Owners can view their dealership's support history.

## Reporting and rankings

- Salespeople see only their work.
- Managers and Owners see their complete dealership/location scope.
- LotCaster employees see only supported dealerships, except Masters.
- Salespeople do not see team rankings unless the dealership enables them.
- Reporting uses factual measures rather than a hidden composite score: successfully published listings, assignment-to-publication time, overdue assignments, active listings, correction count, and verified publication rate.

## Retention

- Publication, pricing, assignment, protected correction, wholesale approval, billing, and support-access history: 7 years.
- Sign-in and security history: 2 years.
- Detailed device/session records: 1 year.
- Expired temporary credentials and tokens: deleted promptly.
- Photos: retained while operationally necessary and subject to dealership data policy.
- Commercial retention and privacy language require legal review before broad launch.

## Implementation rule

No interface-only permission counts as security. Every protected operation must be authorized on the server and, for hosted data, constrained by database row-level security. The local prototype may provide a migration/fallback experience, but it is not the authority for production identity, dealership membership, billing, or support access.
