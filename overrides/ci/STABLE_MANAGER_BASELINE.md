# VIB Manager stable release contract

User-verified Android release: **VIB Manager 0.2.87** (21 November 2026).

- Published tag: vib-manager-0.2.87-stable-purchase-sale-price-20261121
- Release commit: 11c782e31084a4f2e3297877ed0f3016c2e2a521
- Safe development baseline branch: stable/vib-manager-0-2-87
- Android app ID: com.alaa.vibsales.managerscan

## Requirements for every subsequent manager update

1. Create the next version from this guarded stable branch, or from a newer user-verified stable release.
2. Preserve the **fourth editable selling-price field** in manager purchase item popups and purchase draft rows, separate from the purchase cost. The employee app has its own permissions.
3. Retain a red delete control for purchase invoices, with confirmation and safe stock/accounting reversal; unsupported old invoices must explain why they cannot be automatically cancelled.
4. Show sale, purchase, paid, due, and receipt amounts to two decimal places without rewriting historic records just to change their appearance.
5. Keep the package ID and signing certificate unchanged, and increase the APK version for in-place upgrades.
6. The preflight command python3 overrides/ci/verify_manager_contract.py must pass. Flutter popup, money, and purchase cancellation tests must also pass before publishing.
7. Do not announce a verified release until manager build, Android package/signature checks, and publishing jobs all succeed.
8. Test on the actual phone after installation. CI cannot certify every device-specific scenario.

This guard intentionally **fails closed** when crucial source strings or tests are removed. For legitimate refactors, retain or strengthen the behavior tests and update the guard in the same reviewed change. Never disable a failing test simply to publish.

**Keep the original 0.2.87 release tag immutable**; publish newer versions under different tags.
