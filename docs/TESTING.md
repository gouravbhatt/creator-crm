# Test checklist

Automated: `flutter test` (CSV escaping, FY/URL helpers, AES-GCM, recovery key, UPI URI). Run the list below on a device in airplane mode.

## Security
- [ ] First run: create user, weak password rejected, recovery key shown, cannot continue without "I saved it"
- [ ] Kill and reopen app → lock screen; wrong password rejected; 5 wrong attempts → delay
- [ ] Correct password unlocks; data present
- [ ] Forgot password → wrong recovery key rejected → correct key + new password unlocks, data intact, old password fails
- [ ] Settings › change password; Settings › new recovery key (old key stops working)
- [ ] Auto-lock after background time; "Lock now" in More

## Core records
- [ ] Brand add/edit/search/sort; duplicate name warning; delete blocked while it has collabs
- [ ] Contact add/edit/delete, linked to brand, search by brand/role; call/email buttons
- [ ] Collab create (brand required), edit, filter chips, search by reel link, sort
- [ ] Stage moves through all 9 stages; checklist warnings appear; Cancel requires a reason
- [ ] Deliverable add with draft link, revision count, checklist; invalid URL rejected; duplicate live link warning; adding live link offers "Mark Live"
- [ ] Log 24h/7d/30d metrics; engagement % shown; edit/delete snapshot
- [ ] Record partial payment with TDS; pending = agreed − (credited + TDS); multiple payments; status Partial → Paid; overdue when due date passes
- [ ] Expenses → P&L net profit
- [ ] Invoice: auto number, line items, GST on/off, save, share PDF (opens share sheet), UPI QR shows when UPI ID set, signature shows
- [ ] Payment reminder templates share text
- [ ] Timeline shows stage changes, payments, deliverables

## Products and limits
- [ ] Product with brand + collab; add images from gallery (multi) and camera; view, replace, remove
- [ ] Add links (validated), open, edit, delete
- [ ] Default limit 5: 6th image/link blocked with message; counter shows x / 5
- [ ] Raise limit to 20 in Settings → can add more without reinstall; persists after restart
- [ ] Lower limit to 2 with 5 images → warning, nothing deleted, add blocked
- [ ] Delete image file via another app → "Image missing" placeholder

## Dashboard & reports
- [ ] KPIs, needs-attention list (tap opens collabs), pipeline bars, 6-month chart, next 7 days
- [ ] Reports period switch; revenue by month; top brands; aging; TDS/GST; content stats; rate card; scorecard

## Backup / export
- [ ] Create backup → save to Downloads and share
- [ ] Restore with wrong password → rejected, no change
- [ ] Restore corrupted/other file → rejected
- [ ] Restore Merge on same phone → no duplicates
- [ ] Fresh install / second phone → Restore Replace → all records, images, links, limits back
- [ ] CSV export of each set opens in Sheets/Excel; commas, quotes, line breaks and ₹ intact

## Release
- [ ] `flutter build apk --release` succeeds (CI)
- [ ] APK installs on a physical device / emulator (Android 6+) and opens offline
