# VIB Staff for iPhone

The web build uses the same employee accounts, Firestore rules, invoice design and branch permissions as Android. The browser portal admits active employees only. New accounts remain pending until the manager approves them. The browser keeps its Firebase session but does not save the account PIN.

Open the deployed HTTPS URL in Safari, then Share → Add to Home Screen. An internet connection is required. A4 and 80 mm PDF invoices are retained. Native Android notification sounds and microphone recording are unavailable in this web edition; text chat and playback of existing voice messages remain available. Bluetooth/USB thermal printers depend on the printer's own iPhone support; PDFs can be shared or printed via the system print dialog.

## Free deployment

The `Build free VIB Staff web app` workflow builds and uploads `VIB-STAFF-WEB` even when publishing credentials are absent. Add a least-privilege Firebase service account as the repository secret `FIREBASE_HOSTING_SERVICE_ACCOUNT` and rerun the workflow to publish. Grant only Firebase Hosting Admin and API Keys Viewer on vib-sales. These permissions support Hosting deployment and reading client configuration; they do not grant Firestore or Authentication administration. Never paste credentials in chat or commit them.

Publishing verifies that billing is disabled before doing anything, uses the already registered `VIB Staff Web` app ID and rebuilds, then deploys **Hosting only** to `https://vib-sales.web.app`. It does not change Firestore rules, existing customer data, billing, Cloud Storage, Functions or SMS. If billing cannot be verified, deployment stops. Spark quotas apply across Android and web; quota exhaustion can interrupt the service but does not upgrade the project or charge it.

The bundle uses the registered VIB Staff Web configuration. The publication step also explicitly selects that web app ID. Do not describe the URL as live until deployment succeeds.
