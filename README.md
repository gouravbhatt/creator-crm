# Creator CRM

Offline-only Android app (Flutter) for creators to run brand collaborations end to end: brands, contacts, collab lifecycle, deliverables with reel links and performance, payments with TDS, GST invoices with UPI QR, products with images/links, dashboards and reports. No account, no server, no sync — data is encrypted on the phone.

## Install the APK

Every push to `main` builds a release APK on GitHub Actions and publishes it under **Releases** (`build-<n>`, file `app-release.apk`).

1. On the phone open the repo → **Releases** → latest → `app-release.apk`.
2. Allow "Install unknown apps" for your browser when Android asks.
3. Requires Android 6.0 (API 23) or newer.

The release is signed with the default debug key so it installs directly. For Play Store distribution, add your own keystore (see Flutter docs "Signing the app").

## Build locally

```bash
flutter create --platforms=android --org com.gouravbhatt --project-name creator_crm .
bash tool/patch_android.sh
flutter pub get
flutter test
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

Tested toolchain: Flutter 3.24.5, Java 17. The `android/` folder is generated in CI from the Flutter template and patched by `tool/patch_android.sh` (minSdk 23, backup disabled, app label, R8 keep rules for SQLCipher).

## Backup and restore

- **More › Backup, restore & export › Create backup** → choose a backup password → save to phone storage or share (Drive, email…). File: `creator_crm_<date>.ccrm`.
- Contains every table (brands, contacts, collabs, deliverables, metrics, payments, invoices, expenses, products, product images + links, activity, settings incl. limits) and all image files.
- **Restore from file** on any phone: pick the `.ccrm`, enter the backup password. The app decrypts and verifies every file's SHA-256 before touching data, shows counts, then asks **Merge** (keep current data, add backup records) or **Replace** (wipe, then restore; asks twice).
- Wrong password or a damaged file is rejected without changes. Restores run in one database transaction.
- Moving to a new phone: install app → set up a new login → Restore → Replace.

## Docs

- [docs/SECURITY.md](docs/SECURITY.md) — database, key handling, backup format
- [docs/TESTING.md](docs/TESTING.md) — manual test checklist
