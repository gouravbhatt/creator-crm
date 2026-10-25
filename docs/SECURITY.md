# Database and encryption

## Keys

| Item | How it is protected |
|---|---|
| Database | SQLCipher (AES-256) file `creator_crm.db` in app-private storage |
| Database key (DEK) | 32 random bytes from `Random.secure()`, never stored in clear |
| Password | Never stored. Argon2id(password, 16-byte salt; m=19 MiB, t=2, p=1) → KEK that wraps the DEK with AES-256-GCM |
| Recovery key | 32 characters (≈157 bits), shown once at setup. Argon2id → second KEK that wraps the same DEK |
| Wrapped keys + salts + username | `flutter_secure_storage` (Android Keystore–backed EncryptedSharedPreferences) |

Login = derive KEK from password → AES-GCM decrypt of the wrapped DEK. A wrong password fails the GCM tag check. After 5 failures the screen adds a 30 s delay (growing).

Recovery = derive KEK from the recovery key → unwrap DEK → user sets a new password → DEK re-wrapped. Data is untouched. Settings can rotate the recovery key (old one stops working) or change the password.

Auto-lock closes the database and drops the DEK from memory after the configured background time (default 5 min).

`android:allowBackup="false"` stops Android cloud backup from copying the database without its Keystore key.

Lost both password **and** recovery key = data cannot be recovered (by design). Keep a `.ccrm` backup.

## Schema (v1)

`settings, brands, contacts, collabs, deliverables, metrics, payments, invoices, expenses, products, product_images, product_links, activity`

- UUID v4 primary keys (stable across backup/restore and merge).
- Foreign keys on. Deleting a brand with collabs is blocked (RESTRICT); deleting a collab cascades to its deliverables, metrics, payments, invoices, expenses and activity; products are unlinked (SET NULL). Deleting a product cascades its image/link rows and the app deletes the image files.
- Images live in `appDocuments/media/<uuid>.<ext>`; the DB stores only the file name, never a picker temp path.
- Pending = agreed − (credited + TDS). Payment status: Paid / Partial / Unpaid / Overdue (due date passed).
- Limits `max_images` / `max_links` are rows in `settings` (1–100). Lowering a limit never deletes items; adding is blocked until under the limit.
- Migrations: bump `AppDb.schemaVersion` and add steps in `_upgrade`. Restore ignores unknown columns and rejects backups from a newer schema.

## Backup file (.ccrm)

```
"CCRM" | format version (1 byte) | salt (16) | nonce (12) | AES-256-GCM ciphertext | tag (16)
key = Argon2id(backup password, salt)
plaintext = zip { manifest.json, data.json, media/* }
manifest = { format, formatVersion, schemaVersion, createdAt, counts, missingMedia, files: { name: sha256 } }
```
