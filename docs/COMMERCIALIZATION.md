# Commercialization Roadmap

## Verified Local Foundation

- First-run owner account setup.
- Salted PBKDF2 password hashing.
- HTTP-only, SameSite session cookies.
- Protected settings, inventory, photo, import, and export APIs.
- Login, logout, and session expiration.
- Local trial/license record.
- Existing inventory preserved during the authentication upgrade.
- Private master-installation marker and master-only Manage Access APIs.
- Dealer access registry with active and suspended states.

## Master Dealer Console

The development/master installation contains a private marker that allows the first owner named `LOTCASTER` to receive the `master` role. Dealer distribution packages intentionally exclude this marker. Typing `LOTCASTER` on a dealer installation therefore does not grant master access.

The current Manage Access screen maintains and tests the dealer registry locally. Remote suspension requires the hosted licensing service below. A customer installation must regularly validate its signed license with that service; otherwise changing a record on the master computer cannot affect another computer across the internet.

## Next Milestone: Internal Team Edition

Build a small hosted service that owns dealership accounts and user access.

1. Dealership account with one owner.
2. Worker invitations with owner, manager, and salesperson roles.
3. Per-user audit records for imports, listing preparation, and posted status.
4. Device activation and remote session revocation.
5. Encrypted backup and restore for dealership settings and posting history.

The local app should cache an encrypted session for short offline use, but the hosted service remains the authority for access.

## Paid Dealer Edition

1. Stripe Checkout for subscription purchase.
2. Stripe webhooks update the dealership license.
3. Plans define seats, dealerships, and active devices.
4. Failed or cancelled subscriptions enter a short grace period, then become read-only.
5. Stripe Customer Portal handles cards, invoices, and cancellation.

No Stripe secret, master key, or permanent license belongs on the customer computer or USB drive.

## Distribution

- Package the app as a signed Windows installer.
- Publish the Edge helper privately or unlisted for controlled installation and automatic updates.
- Use a USB drive only as an installer and recovery medium.
- Require account activation after installation so copying the USB does not copy a paid license.
- Add automatic app updates before selling beyond a small pilot group.

## Pilot Gate

Before charging additional dealerships:

- Run the internal team edition with several workers for at least two weeks.
- Verify account removal, password reset, device replacement, backup recovery, and subscription-lock behavior.
- Record Facebook form changes and helper failures without storing Facebook credentials.
- Prepare terms, privacy policy, support expectations, and an automation-risk disclaimer.
