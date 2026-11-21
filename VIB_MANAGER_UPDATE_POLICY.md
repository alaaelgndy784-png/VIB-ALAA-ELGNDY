# VIB Manager — mandatory stable baseline for future updates

**Current user-verified manager version: 0.2.87 (21 November 2026).**

Before creating another Android manager update:
- Use branch **stable/vib-manager-0-2-87** as the starting point (or a later verified stable branch).
- Do not use the older main branch's manager files as the app baseline: main has older code and does not contain the user-verified fourth purchase selling-price field.
- Keep the fourth editable **selling-price** input in the manager purchase item dialog and in purchase draft rows. It must be separate from purchase cost.
- Retain visible safe cancellation buttons for saved purchase invoices, and format invoice/receipt money with exactly two decimal places.
- The guarded stable branch includes automated **verify_manager_contract.py** source checks and Flutter widget tests run before APK publishing. If they fail, fix the regression instead of bypassing tests.
- Preserve the manager Android package ID, signing certificate, data compatibility, and invoice history.
- Independently verify each APK's build, signing, package identity, and device behavior before release.

**User-verified release tag:** vib-manager-0.2.87-stable-purchase-sale-price-20261121

**Release SHA:** 11c782e31084a4f2e3297877ed0f3016c2e2a521

**Protected-by-CI development baseline:** stable/vib-manager-0-2-87

This policy is for future development. It does not update the user's installed app or merge old main files over the working manager version.
