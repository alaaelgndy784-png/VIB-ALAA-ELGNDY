# VIB Sales Play Store readiness

## Prepared in this repository

- Separate Android package IDs are already defined by the build: `com.alaa.vibsales.managerscan` and `com.alaa.vibsales.staffscan`.
- The Play build pins Flutter 3.38.5. Check the final AAB's target API in Play Console before submitting it.
- Employee account requests start as `pending`; Firestore rules prevent users from promoting themselves to `owner` or activating their own profile.
- The visit flow requests one-time foreground location only after the employee chooses a customer and consents. It does not request background location.
- A manual workflow at `.github/workflows/build-vib-sales-play.yml` now builds a signed AAB for each app and keeps the bundles as private workflow artifacts. It does not publish APK releases or submit to Google Play.

## Before running the Play build

Create a distinct upload keystore for each app, keep an offline backup, and add these secrets to the GitHub repository:

- `VIB_MANAGER_UPLOAD_KEYSTORE_BASE64`
- `VIB_MANAGER_UPLOAD_STORE_PASSWORD`
- `VIB_MANAGER_UPLOAD_KEY_PASSWORD`
- `VIB_MANAGER_UPLOAD_KEY_ALIAS`
- `VIB_STAFF_UPLOAD_KEYSTORE_BASE64`
- `VIB_STAFF_UPLOAD_STORE_PASSWORD`
- `VIB_STAFF_UPLOAD_KEY_PASSWORD`
- `VIB_STAFF_UPLOAD_KEY_ALIAS`

Never commit keystores, passwords, or their base64 contents to the repository. Enroll each app in Play App Signing when it is first created in Play Console.

## Store setup still needed

- Create the Play Console developer account and the two app records under an account controlled by the owner/company.
- Confirm both application IDs are unused in Play Console and create the matching Firebase Android app registrations if Firebase rejects the package IDs or push delivery needs app-specific configuration.
- Prepare Arabic store names, descriptions, icons and screenshots for the manager and employee apps.
- Publish a public HTTPS privacy policy, link it inside each app and in Play Console, and complete the Data safety and app access forms. The disclosures must cover account phone numbers, employee/customer/business records, consent-based visit location, voice messages and any data handled by Firebase or other SDKs.
- The app currently lets users create accounts from its sign-in screen. Before public release, add an in-app account deletion request flow and a public web page where users can submit deletion requests. Define what will be erased and any accounting records that must be retained.
- Provide Google Play reviewers with working demo credentials and steps for reaching manager and employee functionality. Do not share real customer data in those accounts.
- If this will be a personal developer account created after November 13, 2023, complete the required closed test before requesting production access.
- Confirm the release signing and version codes in Play Console before upload. The workflow currently uses version code `4047`; increase it for every later upload.

## Security note

The build workflow previously changed new manager-app signups from `pending` to `owner`. The current Firestore rules and the rules test reject that self-promotion, but the build-time rewrite was inconsistent with the authorization model and has been removed. New signups remain pending and require owner approval.
