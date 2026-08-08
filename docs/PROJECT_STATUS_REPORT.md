# Dealer Social Inventory Assistant - Project Status Report

Report date: June 25, 2026  
Current product name: LotCaster  
Workspace: `C:\Users\Gage\Documents\Codex\2026-06-23\i-need-to-build-an-app`

## 1. Product summary

### What this product is

LotCaster is a locally hosted dealership inventory assistant intended to help a dealer:

- Import used-vehicle inventory from an authorized online inventory source.
- Retain a local inventory list and detect new, existing, and removed vehicles.
- Review vehicle information and photos.
- Build a marketplace-ready listing packet.
- Copy individual fields or prepared listing text.
- Track whether a vehicle has been posted.
- Export complete inventory data as CSV.
- Give a master operator a local dealer-access management screen.

The current application runs on a Windows PC and opens in a browser at `http://localhost:5173`.

### Who it is for

The initial user is Walker Chevrolet, but the intended commercial product is for multiple independent or franchise dealerships. Likely users include:

- Dealer owner or master operator.
- Sales manager.
- Inventory manager.
- Salesperson responsible for preparing marketplace listings.

Only the local owner/master account is implemented today. Worker accounts and dealership workspaces are not yet implemented.

### Core workflow

1. Start LotCaster from the Windows desktop shortcut or launcher.
2. Sign in to the local installation.
3. Enter or update the dealership inventory page URL.
4. Import or refresh used inventory.
5. Search and review vehicle cards.
6. Select a vehicle and prepare its listing information.
7. Review the description, copy fields, or open the supported Facebook vehicle form helper.
8. Manually review and publish the listing.
9. Mark the vehicle as posted.
10. Export inventory to CSV when needed.

### What problem it solves

The app reduces repetitive dealership listing preparation. It centralizes vehicle data, preserves posting status, prepares reusable listing text, and reduces manual re-entry.

The product should remain a dealership inventory and listing-packet assistant. It should not become a Facebook account bot. It must not automate Facebook login, messaging, account actions, or pressing Publish. Any source import should be limited to inventory the dealership is authorized to use.

## 2. Current status

### Overall maturity

Current maturity: **functional local prototype / early internal beta**.

The application is usable on the original Windows PC and has a functioning branded login, local inventory persistence, AutoTrader import for the primary Walker dealership, CSV tools, listing preparation, and a local master-access screen.

It is not yet ready for reliable multi-dealer commercial distribution. The largest gaps are source reliability, photo retention, Facebook form compatibility, hosted access enforcement, user roles, testing, and installer-quality packaging.

### What is working now

- Local Windows launch flow.
- Branded LotCaster login screen.
- Local password authentication.
- Master-only Manage Access tab.
- Walker Chevrolet AutoTrader used-inventory import.
- Multi-brand vehicle parsing within the Walker used inventory.
- Import batches larger than the original 25-card page display, currently up to the source's first 100 embedded records.
- Local inventory persistence.
- New, seen, and removed inventory tracking.
- CSV import and export.
- Manual vehicle entry.
- Search and inventory filtering.
- Listing-description preparation.
- Copy controls for individual listing fields.
- Posted/unposted status tracking.
- Opening the Facebook vehicle-listing flow through the browser helper.
- A silent desktop launcher that avoids leaving a visible PowerShell window.
- Responsive desktop/mobile styling.

### What is partially working

- Import from other AutoTrader dealer pages.
  - The parser is not intentionally hardcoded to Chevrolet or only Walker vehicles.
  - A Roberts Toyota page was inspected successfully outside the normal app flow.
  - The app did not reliably complete that dealer import during the user's demonstration.
- Multiple vehicle photos.
  - Detail-page gallery discovery can find many images for some AutoTrader listings.
  - Rich image arrays are later overwritten by weaker one-image refresh results.
  - The current saved inventory contains no vehicles retaining more than one image.
- Facebook vehicle-form assistance.
  - Text fields can sometimes be filled.
  - Facebook's vehicle category must be selected first, and this is not reliably handled.
  - Photo attachment attempts up to eight files but currently often results in only one.
- Dealer access management.
  - The master can manage a local dealer registry.
  - It cannot suspend a copy of LotCaster installed on another computer.
- Licensing.
  - Local plan, status, and expiration fields exist.
  - No hosted license validation or billing provider exists.
- Generic non-AutoTrader source import.
  - Generic JSON-LD and page-card fallbacks exist.
  - Dealer websites, Cars.com, CarGurus, and other providers are not verified or dependable.

### What is still mocked or placeholder-level

- Commercial billing and paywall.
- Remote dealer activation and suspension.
- Organization and workspace management.
- Worker invitations.
- Manager and salesperson roles.
- Assignment workflow.
- Activity/audit history.
- Training and onboarding.
- Hosted database and API.
- Secure password recovery.
- Formal compliance acknowledgement and source authorization records.
- Installer, updater, and extension distribution channel.

### What is not started

- Production hosting.
- Stripe or another billing provider.
- Multi-tenant data separation.
- Hosted identity service.
- Email invitation flow.
- Manager dashboard.
- Assignment queue.
- Analytics.
- Formal automated tests.
- Continuous integration and deployment.
- Legal documents, privacy policy, and customer terms.

## 3. Repository structure

### Top-level application files

- `Start-InventoryTool.ps1`
  - Primary application server.
  - Implements the HTTP server, authentication, inventory parsing, persistence, CSV generation, and APIs in PowerShell.
- `server.js`
  - Optional Node.js implementation of most server behavior.
  - Uses Node's built-in HTTP functionality and no third-party server framework.
- `package.json`
  - Defines the optional Node.js start commands and requires Node 18 or newer.
- `README.md`
  - Local setup, startup, and usage notes.
- `COMMERCIALIZATION.md`
  - Current commercialization direction, local security model, and future hosted licensing plan.

### Frontend

- `public/index.html`
  - Main application markup, login screen, inventory workspace, Manage Access screen, dialogs, and forms.
- `public/app.js`
  - Frontend state, API calls, login flow, inventory rendering, imports, CSV actions, listing preparation, and master controls.
- `public/styles.css`
  - Responsive LotCaster styling.
- `public/sw.js`
  - Service worker and cache behavior for the local progressive web app.
- `public/manifest.webmanifest`
  - Installable-app metadata.
- `public/lotcaster-logo.png`
  - Main LotCaster logo.
- `public/icon.svg`
  - Secondary application icon.
- `public/inventory-template.csv`
  - Example/manual inventory CSV structure.
- `public/walker-facebook-helper.zip`
  - Older compressed extension artifact. This should not be treated as the authoritative extension package.

### Browser helper

- `facebook-helper/manifest.json`
  - Manifest V3 extension configuration for Edge or Chrome.
- `facebook-helper/local-app.js`
  - Coordinates data passed from the local app.
- `facebook-helper/background.js`
  - Performs extension background work, including image retrieval.
- `facebook-helper/facebook-form.js`
  - Reads the prepared vehicle payload and attempts to populate the Facebook vehicle form.
- `facebook-helper/INSTALL.txt`
  - Manual unpacked-extension installation instructions.

### Local data

- `data/auth.json`
  - Local account, password salt/hash, role, and local license metadata.
- `data/inventory.json`
  - Current persistent vehicle inventory and posting state.
- `data/settings.json`
  - Current dealer URL, dealership name, city, and listing footer.
- `data/walker-auto-import.csv`
  - Generated CSV representation of imported inventory.
- `data/.lotcaster-master`
  - Private local marker enabling the master role on the development installation.
- `data/roberts-debug.html`
  - Temporary saved page used to inspect another AutoTrader dealer. It is a debug artifact and should eventually be removed.
- `data/dealer-access.json`
  - Expected storage location for the local dealer registry. It does not currently exist because no persistent dealer records are present.

### Launch and distribution files

- `Launch-LotCaster.vbs`
  - Silently starts the PowerShell server and opens the app.
- `Launch-Walker-Inventory-Tool.ps1`
  - PowerShell launcher.
- `Open Walker Inventory Tool.cmd`
  - Command launcher.
- `START WALKER INVENTORY APP.bat`
  - Batch launcher.
- `WalkerInventoryTool-App/`
  - Duplicate/package copy intended for distribution.
  - It requires deliberate synchronization with the root application.
  - It intentionally does not include the private master marker.

### Generated or temporary files

- `data/inventory.json`
- `data/walker-auto-import.csv`
- `data/roberts-debug.html`
- Any future `data/dealer-access.json`
- Browser/service-worker cache in the user's browser

### Missing expected project infrastructure

- No dependency lockfile.
- No build configuration.
- No test directory or test configuration.
- No lint configuration.
- No database schema or migrations.
- No continuous-integration configuration.
- No production deployment configuration.
- The visible `.git` path is not currently recognized as a usable Git repository, so change history and clean/dirty status cannot be trusted from Git.

## 4. Frontend architecture

### Framework

The frontend uses:

- Plain HTML.
- Plain CSS.
- Vanilla browser JavaScript.
- A service worker and web-app manifest.

There is no React, Vue, Angular, TypeScript, bundler, component library, or frontend package dependency.

### Main screens

1. Authentication screen
   - Branded LotCaster login.
   - Initial local setup support.
   - Local license/trial information.
2. Inventory workspace
   - Dealership settings.
   - Import and refresh controls.
   - CSV import/export.
   - Manual vehicle entry.
   - Inventory counts, filters, search, and vehicle cards.
3. Listing preparation dialog
   - Vehicle details.
   - Prepared description.
   - Copy controls.
   - Facebook helper launch.
4. Manage Access screen
   - Visible only to the local master role.
   - Creates and updates local dealer access records.

### Key frontend functions

Authentication and startup:

- `init`
- `bindEvents`
- `loadAuth`
- `showAuth`
- `submitAuth`
- `enterApp`
- `logout`

Inventory:

- `loadSettings`
- `loadInventory`
- `refreshInventory`
- `autoImportInventory`
- `saveManualVehicle`
- `importInventory`
- `render`
- `renderVehicle`

Listing workflow:

- `openPostingSheet`
- `openFacebookWithVehicle`
- `encodePayload`
- Copy and helper-check functions

Master controls:

- `showWorkspace`
- `loadDealers`
- `addDealer`
- `renderDealers`
- `setDealerStatus`

### State management

Application state is kept in a single in-memory JavaScript state object in `public/app.js`. The browser reloads authoritative data from the local APIs. There is no formal state-management library.

### API interaction

The frontend uses browser `fetch` calls against the same local origin. Authentication is cookie-based, so protected API requests use the local session cookie.

### UI maturity

The UI is functional and branded, with a compact dealership-workflow layout and responsive behavior. It is more mature than a wireframe but not yet a polished multi-tenant SaaS interface.

Outstanding frontend concerns:

- Some Walker-specific labels remain.
- Source-import terminology is inconsistent.
- Quick-add, settings, CSV, and operational controls compete for attention on one screen.
- There is no guided onboarding.
- There is no role-specific interface for managers or salespeople.
- Accessibility has not been formally audited.
- The extension/install experience is too technical for dealer customers.

## 5. Backend / data architecture

### Primary runtime

The primary runtime is `Start-InventoryTool.ps1`, which implements a custom local HTTP server in PowerShell. It:

- Serves static frontend files.
- Reads and writes JSON files.
- Authenticates users.
- Manages in-memory sessions.
- Fetches third-party inventory pages.
- Parses and normalizes vehicles.
- Generates and imports CSV files.
- Exposes JSON APIs.

### Optional runtime

`server.js` provides a mostly parallel Node.js implementation using built-in Node modules. It is intended as a fallback for systems with Node 18 or newer.

Maintaining two backend implementations creates drift risk. Fixes must currently be applied twice or one runtime may behave differently from the other.

### Database

There is no database. Persistent data is stored in local JSON and CSV files under `data/`.

### Authentication

- Local email/password authentication.
- PBKDF2 SHA-256 password hashing.
- 120,000 iterations.
- Random salt and stored password hash.
- `HttpOnly` and `SameSite=Strict` session cookie.
- Twelve-hour session lifetime.
- Sessions are held only in server memory.

The current master credential is stored as a salt and password hash, not as a readable password. The actual password must not be included in handoff documents or logs.

### Roles

Implemented:

- `owner`
- `master`

Not implemented:

- Manager.
- Salesperson.
- Inventory specialist.
- Read-only user.
- Billing administrator.

There is currently one local user record per installation. There are no invitations or multiple user accounts within a dealership.

### Data model

Settings include:

- Inventory source URL.
- Dealership name.
- City.
- Listing footer.

Vehicle records include normalized listing data such as:

- Internal ID.
- Year, make, model, trim, and title.
- Price.
- Mileage.
- VIN.
- Stock number.
- Source/detail URL.
- Primary image and image array.
- Inventory state.
- Facebook posting status.
- First-seen and last-seen metadata.

Important missing vehicle fields:

- Reliable body type.
- Facebook vehicle category mapping.
- Fuel type.
- Transmission.
- Exterior/interior color.
- Drivetrain.
- Condition confidence/source provenance.
- Photo-quality and photo-source metadata.

### API surface

Authentication:

- `GET /api/auth/status`
- `POST /api/auth/setup`
- `POST /api/auth/login`
- `POST /api/auth/logout`

Settings and inventory:

- `GET /api/settings`
- `POST /api/settings`
- `GET /api/inventory`
- `POST /api/scrape`
- `POST /api/auto-import`
- `POST /api/manual`
- `POST /api/import`
- `POST /api/facebook-status`
- `POST /api/vehicle-photos`
- `GET /api/export.csv`
- `GET /api/auto-import.csv`

Master controls:

- `GET /api/admin/dealers`
- `POST /api/admin/dealers`
- `POST /api/admin/dealer-status`

### Integrations

Implemented or attempted:

- AutoTrader dealer-page parsing.
- AutoTrader detail-page gallery parsing.
- Generic JSON-LD vehicle parsing.
- Generic page-card parsing.
- Facebook Marketplace vehicle-form browser helper.

Not implemented:

- Authorized dealer-management-system feed.
- OEM inventory API.
- Hosted licensing API.
- Payment processor.
- Email provider.
- Cloud file storage.
- Analytics or logging service.

## 6. Inventory ingestion

### Accepted input

The app accepts:

- A dealer inventory-page URL entered in settings.
- CSV upload.
- Manual vehicle entry.

### AutoTrader behavior

For AutoTrader URLs, the server:

- Adds or updates `numRecords=100`.
- Downloads the dealer page.
- Reads the embedded Next.js application state.
- Locates inventory entries.
- Filters for used or certified vehicles.
- Normalizes title, year, make, model, trim, price, mileage, VIN, stock number, URL, and primary image.
- Merges results into the existing local inventory.

The parser is not limited to Chevrolet. It can read other makes present in the selected dealer's used inventory.

### Multiple-vehicle handling

Multiple listings are imported in one request. The current practical limit is the first embedded source batch, normally up to 100 records.

The app does not yet implement source pagination. A dealer page reporting more than 100 vehicles may be truncated.

### Duplicate prevention

Vehicle identity is derived in this priority order:

1. VIN.
2. Stock number.
3. Source/detail URL.
4. Normalized title.

The merge process uses that identity to update existing vehicles and reduce duplicate records.

### Inventory lifecycle

The merge process tracks:

- Newly discovered vehicles.
- Existing vehicles seen again.
- Vehicles no longer present in the latest successful source result.
- Facebook posted/unposted state.

If an import unexpectedly returns zero vehicles, the app attempts to avoid wiping the current inventory.

### Error handling

The app returns warning/error messages and generally preserves the previous inventory when a source read fails.

Current limitations:

- Error messages still contain some Walker-specific language.
- Source-specific failures are not categorized clearly.
- No retry queue or scheduled sync.
- No per-source health history.
- No visual import log.
- URL query noise such as tracking parameters is not consistently removed.

### Current multi-dealer finding

A Roberts Toyota AutoTrader page was inspected during debugging:

- The page reported 164 available vehicles.
- Its embedded state contained 100 inventory entries.
- Its structure appeared compatible with the existing AutoTrader parser.

However, the normal application flow did not reliably import that dealership during the user's demonstration. This remains an unresolved production blocker. Likely investigation areas include:

- Page URL normalization.
- Source pagination.
- Runtime differences between the PowerShell and Node implementations.
- Cached frontend/server versions.
- Source response variation and blocking.
- Dealer-specific embedded-state differences.

No fix for this issue has been applied in the current audit.

## 7. Vehicle data model

### Parsed fields

The code attempts to parse:

- Year.
- Make.
- Model.
- Trim.
- Combined title.
- Price.
- Mileage.
- VIN.
- Stock number.
- Vehicle detail URL.
- Primary image.
- Additional image URLs when available.
- Source and dealership context.

### Missing or weak fields

The following are absent or inconsistently populated:

- Body type.
- Car/truck/SUV category.
- Transmission.
- Fuel.
- Drivetrain.
- Exterior color.
- Interior color.
- Engine.
- Seller notes.
- Certified status as a dedicated normalized field.
- Accurate location per vehicle.
- Option/package details.

### Normalization

Normalization converts inconsistent source properties into one local shape. It also creates a stable ID and constructs marketplace text.

Known normalization risks:

- Source titles may be trusted too heavily.
- Price and mileage cleaning depends on source formatting.
- Generic parsers can pick up unrelated page data.
- No schema validator rejects malformed records.
- There is no confidence score or source-field provenance.

### Photo behavior

Dealer search pages generally expose one thumbnail per vehicle. The app can fetch a vehicle's AutoTrader detail page and inspect the embedded gallery, where many photos may be available.

One tested listing exposed 33 gallery photos, confirming that the gallery parser can work.

The current critical bug is data regression:

- A successful detail lookup can save many photos.
- A later inventory refresh or weaker photo lookup can replace that array with one image.
- The current saved inventory has 71 active vehicles and zero vehicles retaining more than one image.

The merge and photo-update logic should preserve the richest valid image set, deduplicate URLs, and only replace existing images when the new result is demonstrably better.

### Listing packet generation

The app builds a marketplace-oriented description from normalized vehicle data and the dealership footer. It supports field-by-field copying and prepared text review.

This is a useful base, but a complete packet should also include:

- Ordered photo selection.
- Required-field completeness indicators.
- Category/body-type mapping.
- Dealer-approved description template.
- Compliance reminders.
- Source attribution and last-refresh time.

## 8. Authentication and account management

### Login flow

The application opens on a LotCaster login screen. A local setup route can create the first account, and a local login route validates the stored password hash.

### Persistence

The user record persists in `data/auth.json`.

Sessions do not persist across a server restart because they are held in memory. Restarting LotCaster signs the user out.

### Password handling

Passwords are hashed using PBKDF2 SHA-256 with a random salt. The readable password is not stored by the application.

Missing account protections:

- Password reset.
- Email verification.
- Multi-factor authentication.
- Login rate limiting.
- Account lockout.
- Security-event logging.
- Persistent/revocable session records.

### Master account

The development installation contains a master user and a private `.lotcaster-master` marker. The packaged copy intentionally excludes that marker.

The frontend displays Manage Access only when the authenticated user role is `master`. Admin APIs independently verify the master role.

The master mechanism is adequate only as a local prototype. A user with write access to the local data files can alter the account data or marker. This must not be presented as secure commercial license enforcement.

### Dealer access controls

The Manage Access screen supports local records containing:

- Dealer name.
- Owner email.
- Plan.
- Active or suspended status.
- Expiration date.
- Notes.

These records do not communicate with installations at other dealerships. Suspending a record locally does not turn off a remote copy.

### Multi-dealer support

Not yet implemented:

- Hosted dealership organizations.
- Separate dealer workspaces.
- Multiple users per dealer.
- Invitations.
- Role-based permissions beyond local owner/master.
- Secure remote access revocation.
- Device activation.

## 9. Roles and permissions

### Implemented roles

`owner`

- Uses the local inventory application.
- Can update settings and inventory.
- Can prepare listings and update posting status.

`master`

- Has all owner behavior.
- Can see the Manage Access tab.
- Can create and update local dealer-access records.

### Planned roles

Manager:

- View all dealer inventory.
- Assign vehicles.
- Review listing packets.
- See posting progress.
- Manage dealership users.

Salesperson:

- View assigned vehicles.
- Prepare listing packets.
- Copy approved data.
- Mark workflow status.

Inventory manager:

- Configure authorized inventory sources.
- Review import errors.
- Correct vehicle data.
- Approve photos and descriptions.

### Permission enforcement

Current enforcement exists in both the frontend and backend for master-only admin routes. General inventory APIs require authentication but do not distinguish between non-master roles because those roles do not yet exist.

### Permission gaps

- No per-dealership tenant boundary.
- No assignment restrictions.
- No field-level permissions.
- No audit trail.
- No server-side permission matrix.
- No invitation acceptance.
- No user deactivation within a dealership.

## 10. Facebook Marketplace workflow

### Current workflow

1. The user selects Prepare for Facebook on a vehicle.
2. The app requests additional vehicle photos.
3. A review dialog displays the vehicle data and prepared description.
4. The user may copy individual fields.
5. The user can open the Facebook Marketplace vehicle form using the extension/helper.
6. The extension reads a vehicle payload from the URL fragment.
7. It attempts to fill matching fields and attach up to eight photos.
8. The user reviews the form and manually publishes.

### What is copied or prepared

- Year.
- Make.
- Model.
- Trim.
- Price.
- Mileage.
- VIN.
- Description.
- Vehicle/source URL.
- Photo URLs or attempted photo attachments.

### What must remain manual

- Facebook login.
- Account selection.
- Marketplace policy acceptance.
- Final vehicle/category verification.
- Final description review.
- Final photo review.
- Publishing.
- Messaging with buyers.
- Editing or deleting live Facebook listings.

### Current bugs

- Vehicle category/body type is not reliably selected as car, truck, or SUV before dependent fields are filled.
- Facebook can hide or reset dependent fields when the category is missing.
- Some text values therefore disappear or fail to populate.
- The helper attempts up to eight photos, but the source data usually retains only one.
- Even when multiple URLs are available, Facebook's file input may accept only one because of browser restrictions, download failures, changing DOM behavior, or platform safeguards.
- Facebook DOM selectors can change without notice.

### Compliance and platform risk

The browser helper does not intentionally press Publish and does not automate login or messaging. It does, however, attempt automated field entry and photo attachment on Facebook. This is fragile and may conflict with platform rules or trigger anti-automation behavior.

The safer commercial product direction is:

- Prepare a complete listing packet.
- Provide explicit copy controls.
- Download or open approved photos for manual upload.
- Track workflow and posting status.
- Keep publication and account actions manual.

Before distributing the helper commercially, review Facebook's current terms and obtain legal guidance. Do not market the product as guaranteed one-click Facebook posting.

## 11. Tests and validation

### Automated tests

None are currently present.

There is no:

- Unit-test framework.
- Integration-test suite.
- Browser end-to-end suite.
- Lint command.
- Type checking.
- Continuous-integration pipeline.

### Manual validation performed

The project has been manually checked through:

- Starting the PowerShell server.
- Requesting the local home page and settings API.
- Importing Walker Chevrolet inventory.
- Inspecting generated inventory JSON and CSV.
- Testing local authentication.
- Checking master-only UI visibility.
- Loading the browser extension manually.
- Opening the Facebook vehicle form.
- Inspecting an alternate AutoTrader dealer page.
- Inspecting AutoTrader detail-page photo data.
- Running JavaScript syntax checks during earlier development.

### What has not been tested enough

- Reliable import from a representative set of AutoTrader dealers.
- Dealers with more than 100 vehicles.
- Generic dealership websites.
- Cars.com and CarGurus.
- Source blocking, captchas, and response changes.
- Photo retention across repeated imports.
- Eight-photo Facebook transfer.
- Facebook form changes across accounts and regions.
- CSV round-trip completeness.
- Duplicate handling under VIN/stock changes.
- Session expiry and restart behavior.
- Security boundaries under local file tampering.
- Mobile browser behavior.
- Edge versus Chrome extension behavior.
- Packaged-copy parity with the root project.

### Minimum test plan before dealer distribution

1. Add parser fixtures for at least ten authorized dealer pages.
2. Add unit tests for normalization, IDs, CSV, and merge behavior.
3. Add regression tests proving richer photo arrays are preserved.
4. Add API integration tests for authentication and roles.
5. Add browser tests for login, import, search, listing preparation, and posting status.
6. Test clean installation on a second Windows computer.
7. Test offline/restart behavior.
8. Perform a security review before hosted licensing.

## 12. Setup and run instructions

### Recommended Windows startup

Use the LotCaster desktop shortcut, which should launch:

`Launch-LotCaster.vbs`

This starts the PowerShell server without leaving a visible console window and opens the app in the default browser.

### Manual PowerShell startup

From the project directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-InventoryTool.ps1 -Port 5173
```

Then open:

`http://localhost:5173`

### Optional Node.js startup

Requirements:

- Node.js 18 or newer.

Commands:

```powershell
npm start
```

Equivalent:

```powershell
node server.js
```

Optional Node environment variables:

- `PORT`
- `HOST`

No build command is required because the frontend is served directly as static files.

### Browser helper installation

For Microsoft Edge:

1. Open `edge://extensions`.
2. Enable Developer mode.
3. Select Load unpacked.
4. Select the `facebook-helper` directory.

For Chrome:

1. Open `chrome://extensions`.
2. Enable Developer mode.
3. Select Load unpacked.
4. Select the `facebook-helper` directory.

The old ZIP file should not be trusted as the current installation source unless it is rebuilt and verified.

### Expected local files

The app needs write access to its `data` directory. The packaged dealer version should not include the private master marker or development customer data.

### Build, test, and lint commands

- Build: none.
- Test: none currently.
- Lint: none currently.
- PowerShell run: command above.
- Node run: `npm start`.

## 13. UI/UX status

### Polished areas

- LotCaster branding and logo.
- Dedicated login screen.
- Responsive layout.
- Inventory counts and searchable vehicle cards.
- Visible import and export actions.
- Prepared listing review dialog.
- Copy controls.
- Master-only access tab.
- Local trial/license display.

### Rough areas

- Too many operational controls share the main inventory screen.
- CSV and manual-entry tools are more prominent than most daily users need.
- Extension installation is technical.
- Import errors do not provide enough diagnostic detail.
- There is no progress history showing which import stage failed.
- Photo count and photo-source quality are not clearly presented.
- The posting workflow does not warn early enough when required Facebook fields are missing.
- No empty-state guidance for a new dealer.

### Stale or misleading text

- Walker-specific names remain in launcher names, helper names, messages, and placeholders.
- "Auto Import" can imply broader compatibility than is currently verified.
- "Prepare for Facebook" may imply reliable automated form completion.
- Some documentation says the tool only prepares/copies data, while the extension currently attempts form filling and photo attachment.

### Unfinished screens

- Manage Access is only a local registry.
- No user-management screen.
- No dealership workspace screen.
- No source-management screen.
- No assignment board.
- No manager dashboard.
- No activity log.
- No billing screen.
- No onboarding or training center.

## 14. Security and compliance notes

### Local secrets and credentials

- The master password must never be committed to documentation or exposed in UI/debug logs.
- `data/auth.json` contains a password salt/hash and should be treated as sensitive.
- `data/.lotcaster-master` should remain private and excluded from dealer packages.
- Customer data files should not be bundled into distributable copies.

### Local security limitations

- Data files are unencrypted.
- A user with local file access can copy or modify them.
- The server uses local HTTP, not TLS.
- Sessions are held in memory.
- There is no CSRF token.
- There is no rate limiting or lockout.
- There is no tamper-resistant licensing.
- There is no signed update mechanism.

### Scraping and source authorization

The product should ingest only inventory sources the dealership is authorized to use. Direct page scraping can break when a provider changes its site and may conflict with provider terms.

A production version should prefer, in order:

1. Dealer-provided export or API.
2. Dealer-management-system feed.
3. Authorized inventory syndication feed.
4. Explicitly permitted public page ingestion.

The app should record the source type, authorization, last sync, and import result.

### Facebook policy risk

The product must not:

- Automate Facebook login.
- Evade platform controls.
- Send automated buyer messages.
- Create or control accounts.
- Press Publish without the user.
- Misrepresent listings or dealer identity.

The existing form helper is technically fragile and should be treated as experimental pending a platform-policy and legal review.

### Commercial compliance gaps

- No privacy policy.
- No customer terms.
- No data-processing policy.
- No incident-response process.
- No audit logging.
- No deletion/export policy for customer data.
- No signed installer.
- No hosted access-control boundary.

## 15. Known issues / technical debt

### Critical

1. Other dealer imports are not reliable.
   - The alternate AutoTrader page appears structurally compatible but failed in the normal application flow.
   - This blocks multi-dealer commercialization.

2. Multiple photos are not retained.
   - Rich gallery results are overwritten by later one-image results.
   - Current persisted inventory has no multi-photo vehicles.

3. Facebook vehicle category is not set reliably.
   - Dependent fields disappear or fail to populate.
   - Vehicle body type/category is missing from the normalized data model.

4. Remote suspension is not real.
   - Manage Access cannot disable software installed on another dealer's PC.

### High

5. PowerShell and Node backends duplicate behavior.
   - They can drift and receive inconsistent fixes.

6. No pagination beyond the first 100 embedded AutoTrader records.

7. No automated tests.

8. No true multi-user or multi-tenant model.

9. The extension depends on unstable Facebook page structure.

10. Local data and license files are easy to copy or edit.

### Medium

11. The project/package copy requires manual synchronization.

12. Walker-specific branding remains in filenames and messages.

13. Tracking query parameters are retained in saved source URLs.

14. Generic source parsers can collect strange or unrelated page details.

15. No structured schema validation for imported vehicles.

16. Session cookies use the legacy name `walker_session`.

17. Sessions are lost on restart.

18. The stale `public/walker-facebook-helper.zip` can confuse installation.

19. `data/roberts-debug.html` is a large temporary debug artifact.

20. No trusted Git status/history is available from the current workspace metadata.

### Low

21. Documentation and actual extension behavior are inconsistent.

22. No formal accessibility testing.

23. No import history or user-visible diagnostic log.

24. No automatic updater.

## 16. Recommended next steps

### Immediate blockers

1. Make AutoTrader ingestion dealer-independent.
   - Normalize and sanitize dealer URLs.
   - Add fixture-based tests for multiple dealer IDs and brands.
   - Compare PowerShell and Node parser output.
   - Add pagination or source-batch retrieval beyond 100 records.
   - Show exact source-stage errors in the UI.

2. Fix photo preservation.
   - Merge and deduplicate image arrays.
   - Never replace a richer valid gallery with a weaker one-image result.
   - Save photo source and retrieval time.
   - Limit the listing packet to the best eight photos after preserving the full gallery.

3. Add a normalized vehicle category/body-type field.
   - Parse it from source data where possible.
   - Provide a manual correction control.
   - Require category confirmation before opening the Facebook workflow.

4. Stabilize the listing-packet workflow.
   - Make prepared data review the primary experience.
   - Add a required-field checklist.
   - Provide a reliable photo download/open workflow for manual upload.
   - Keep final Facebook publishing manual.

### Backend and architecture

5. Choose one backend implementation.
   - Recommended direction: migrate to one maintained Node service for future hosted development, or formally commit to PowerShell only for the local prototype.

6. Introduce a typed, validated vehicle schema.

7. Add automated tests before more source adapters.

8. Replace manual package duplication with a repeatable packaging script.

9. Remove debug data and stale extension ZIP artifacts from distributable output.

### Multi-dealer product foundation

10. Design hosted organizations, dealerships, users, roles, and device activations.

11. Move master access enforcement to a hosted licensing service.

12. Add signed installation/device tokens with periodic validation and a reasonable offline grace period.

13. Add manager and salesperson accounts, invitations, and assignments.

14. Add activity history and posting-status reporting.

### Commercialization

15. Confirm source and Facebook policy boundaries with legal guidance.

16. Build a signed Windows installer and update process.

17. Add billing only after hosted identity and licensing are secure.

18. Pilot with one additional authorized dealership before broad release.

19. Document support, backups, data ownership, privacy, and cancellation behavior.

### Longer-term enhancements

20. Add authorized DMS/feed connectors.

21. Add inventory-source health monitoring.

22. Add dealer-approved listing templates.

23. Add assignment queues and manager review.

24. Add dashboard reporting for ready, assigned, prepared, posted, removed, and overdue vehicles.

## 17. Suggested product roadmap

### Phase 1 - Stabilize the local prototype

Goal: make the existing Walker workflow dependable.

- Fix cross-dealer AutoTrader parsing.
- Add URL normalization.
- Add support for more than 100 listings.
- Fix multi-photo retention.
- Add body type/category.
- Improve import diagnostics.
- Remove stale artifacts and Walker-only UI text.
- Add core parser, merge, CSV, and auth tests.

Exit criteria:

- Walker plus at least three other authorized AutoTrader dealers import reliably.
- Repeated refreshes do not lose photos.
- Required listing fields remain stable.
- A clean Windows installation works without development tools.

### Phase 2 - Harden the listing-packet workflow

Goal: deliver a dependable human-reviewed posting assistant.

- Add complete listing-packet review.
- Add field-completeness checks.
- Add best-eight-photo selection and manual download/open flow.
- Add dealer templates and compliance reminders.
- Improve posting status and retry workflow.
- Reassess or reduce the Facebook form-filling helper based on platform guidance.

Exit criteria:

- A salesperson can prepare a complete listing without editing raw data files.
- Final publication remains a clear manual user action.
- Failed/missing fields are visible before leaving LotCaster.

### Phase 3 - Multi-user dealership workspace

Goal: support a real dealership team.

- Hosted authentication.
- Dealership organizations/workspaces.
- Owner, manager, inventory, and salesperson roles.
- Invitations and deactivation.
- Vehicle assignments.
- Manager review.
- Activity log.
- Dashboard and reporting.

Exit criteria:

- Multiple users can safely share one dealership workspace.
- Permissions are enforced server-side.
- Managers can see who prepared and posted each vehicle.

### Phase 4 - Commercial access and billing

Goal: distribute and control paid installations.

- Hosted licensing API.
- Device activation.
- Remote suspension.
- Offline grace period.
- Billing provider integration.
- Signed installer and updates.
- Customer account portal.
- Backup and export process.

Exit criteria:

- A dealer's access can be activated or suspended remotely.
- Local file edits cannot grant master or paid access.
- Billing and access state are auditable.

### Phase 5 - Broader authorized inventory integrations

Goal: reduce dependence on fragile page parsing.

- Dealer-provided CSV automation.
- DMS and syndication-feed connectors.
- Source-specific adapters with contract tests.
- Scheduled synchronization.
- Source health and failure alerts.
- Data provenance and authorization tracking.

Exit criteria:

- Most customers use an authorized feed or stable connector.
- Page scraping is a fallback, not the core product dependency.

### Phase 6 - Production hardening

Goal: prepare for wider dealer distribution.

- Security review.
- Privacy and customer terms.
- Monitoring and support tooling.
- Audit logs.
- Disaster recovery.
- Accessibility review.
- Performance testing.
- Controlled extension distribution, if the helper remains part of the product.

Exit criteria:

- The product has documented operational, security, compliance, and support processes.
- New dealer onboarding is repeatable and does not require source-code changes.
