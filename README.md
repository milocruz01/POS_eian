# Car Wash POS

Offline Android POS for automatic touchless car washes (HeyCar TS-5 / TS-7). Built with Flutter.

## Features
- **Wash screen**: pick machine (TS-5 / TS-7), tap packages, plate + customer, discount, payment method, cash change calculator, shareable receipt.
- **Packages**: price, machine, recipe of materials per wash, live cost / profit / margin, duplicate, hide.
- **Materials**: unit, cost per unit (or from pack price / size), stock, low-stock alerts, restock (can log an expense and update unit cost).
- **Automatic stock deduction** per wash and exact material cost saved on every sale; voiding a sale returns the stock.
- **Expenses**: any category (editable), date, note, totals by category.
- **Reports**: today / yesterday / 7 days / month / last month / all / custom. Cars, sales, material cost, gross and net profit, daily chart, busy hours, by package / machine / payment, materials used, expenses by category, low stock.
- **Customers** with plate, phone and visit history.
- **Excel**: export everything, export a report, import materials / packages / recipes / customers / expenses.
- Optional PIN lock, dark mode, works fully offline.

## Get the APK
1. Create a new GitHub repository and upload everything in this folder (keep the `.github` and `ci` folders).
2. Open the **Actions** tab, run **Build APK** (it also runs on every push).
3. When it finishes (about 5-8 minutes) download `CarWashPOS.apk` from **Releases** (or from the run's Artifacts).
4. On the phone/tablet allow "Install unknown apps" for your browser or file manager and open the APK.

All builds are signed with the same key in `ci/`, so you can install a newer version over the old one without losing data.
