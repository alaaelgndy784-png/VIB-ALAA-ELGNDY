# Geidea payment links for VIB

The Android screen and backend are prepared. Live processing is disabled by default. No merchant credentials are included in this repository or the APK.

## Activation

1. Activate an Egypt Geidea merchant account for EGP payment links and refunds; agree settlement into the merchant's Banque Misr account with Geidea. Card acceptance and bank settlement are separate events.
2. Use a test merchant first. From `overrides/firebase`, install functions dependencies, authenticate the authorized Firebase administrator, and set `GEIDEA_API_PASSWORD` through Firebase Secret Manager. Configure `GEIDEA_PUBLIC_KEY`, `GEIDEA_MODE=test`, `GEIDEA_WEBHOOK_URL=https://us-central1-vib-sales.cloudfunctions.net/geideaWebhook`, and `GEIDEA_ENABLED=false` in the Firebase functions parameter environment. Deploy the functions and the accompanying Firestore rules. Deployment may require an eligible billing plan; no deployment or billing change is performed by this code.
3. Configure the signed order callback with Geidea. Verify the account's callback amount formatting and refund signature with real sandbox callbacks before enabling. Current callback canonicalization uses two decimal places; refund concatenation uses the numeric amount string. Validate the provider's exact wire representation; never weaken signature verification or accept a browser redirect as confirmation.
4. Enable only test mode first and complete: link creation, captured payment, failed/authorization-only payment, duplicate callback, manual status refresh, full card refund, expired link, network timeout and invoice changed while a link exists. Test results never alter real customer balances, cash or stock.
5. Activate live mode only after a real merchant-approved acceptance test and bank settlement reconciliation. Configure `GEIDEA_MODE=live` and `GEIDEA_ENABLED=true` on the server. Never enter API passwords in the phone app.

## Accounting

The server inquires the authenticated order API after a signed callback or an owner refresh. A confirmed captured payment reduces customer debt and increments invoice `receiptPaid` and `onlinePaid` once. Amounts go to `settings/geideaClearing`, separately from physical cash. A card refund reverses the applied debt and clearing amounts, leaving cash and stock untouched. Invoice return is blocked until `onlinePaid` is zero, then the original stock/cash/debt return can proceed. Paid online invoices cannot be edited. Changed/reset invoices and duplicate orders are flagged for review without another customer credit. Ambiguous creation/refund outcomes block repeat requests until reconciled.

Only the owner can create/share links and request refunds. The service doesn't read NFC cards or store PAN, CVV, PIN, OTP, raw callback bodies or card tokens. Tap on Phone requires Geidea's separate merchant activation and confirmation of supported devices in Egypt.

## Official references

- https://docs.geidea.net/docs/pay-by-link-apis
- https://docs.geidea.net/reference/get-order-details
- https://docs.geidea.net/docs/sample-callback-responses
- https://docs.geidea.net/docs/refund-2
