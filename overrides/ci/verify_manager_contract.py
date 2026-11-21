#!/usr/bin/env python3
"""Fail closed if a manager build drops validated purchase-invoice behavior.

Run from CI or locally: python3 overrides/ci/verify_manager_contract.py
This is a source preflight. Flutter widget tests are also mandatory.
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[2]


def load(relative):
    path = root / relative
    if not path.is_file():
        raise FileNotFoundError(f"Required regression file missing: {relative}")
    return path.read_text(encoding="utf-8")


try:
    main = load("overrides/lib/main.dart")
    editor = load("overrides/lib/invoice_editor.dart")
    history = load("overrides/lib/invoice_history.dart")
    cancel = load("overrides/lib/purchase_invoice_cancellations.dart")
    popup_test = load("overrides/test/purchase_sale_price_popup_test.dart")
    money_test = load("overrides/test/money_display_test.dart")
    delete_test = load("overrides/test/purchase_invoice_cancellations_test.dart")
    workflow = load(".github/workflows/build-vib-sales-independent.yml")
except (OSError, UnicodeError) as exc:
    sys.exit(f"VIB MANAGER REGRESSION GUARD FAILED: {exc}")

codes = [int(x) for x in re.findall(r"versionCode = (2\d{4})", workflow)]
checks = [
    ("manager purchase screen exists", "purchaseDialog(context,owner:owner)" in main),
    ("manager's independent selling-price visibility",
     "bool purchaseEditorShowsSalePrice" in main and
     re.search(r"owner\s*\|\|\s*!employeeApp", main) is not None),
    ("purchase item popup receives selling-price controller",
     "sellingPrice:purchaseEditorShowsSalePrice(owner:owner,employeeApp:staffApp) ? row.sellingPrice : null" in main),
    ("purchase draft list receives selling-price controller",
     "sellingPrice:purchaseEditorShowsSalePrice(owner:owner,employeeApp:staffApp) ? lines[i].sellingPrice : null" in main),
    ("fourth selling-price field has stable widget key",
     "purchase-item-dialog-sale-price" in main and "labelText: 'سعر البيع'" in main),
    ("line editor passes selling-price into popup",
     "initialSellingPrice:sellingPrice?.text" in editor and "sellingPrice:draftSellingPrice" in editor),
    ("confirm applies sale-price edits; cancellation does not",
     "result.sellingPriceChanged" in editor and "onSellingPriceChanged?.call()" in editor),
    ("purchase selling price cannot be below its cost",
     "salePrice < unitCost" in main and "changeSellingPrice: owner && row.sellingPriceEdited" in main),
    ("owner purchase drafts and history retain delete control",
     "PurchaseInvoiceDeleteButton" in main and "PurchaseInvoiceDeleteButton" in history),
    ("purchase cancellation keeps safe accounting reversal",
     "purchaseInvoiceCanBeCancelled" in cancel and "confirmPurchaseInvoiceCancellation" in cancel and
     "purchaseInvoiceCancellationBlockReason" in cancel),
    ("sale, purchase and paid amounts are displayed with piastre formatting",
     "vibVoucherMoney(sale['total'])" in main and "vibVoucherMoney(p['total'])" in main and
     "vibVoucherMoney(sale['paid'])" in main),
    ("popup tested at both phone widths",
     "for (final width in [360.0, 564.0])" in popup_test and
     "purchase-item-dialog-sale-price" in popup_test and
     "manager purchase keeps selling price" in popup_test),
    ("money rounding tested against the reported value",
     "3499.9800000000005" in money_test and "3,499.98" in money_test),
    ("receipt voucher UI, PDF and cancellation use one two-decimal renderer",
     "String vibReceiptCurrency" in main and
     "Text(vibReceiptCurrency(data['amount'])" in main and
     "detail('المبلغ المدفوع',vibReceiptCurrency(paid)" in main and
     "vibReceiptCurrency(displayed['amount'])" in load("overrides/lib/voucher_cancellations.dart") and
     "vibReceiptCurrency(data['amount'])" in load("overrides/lib/pending_receipts.dart") and
     "vibReceiptCurrency(data['paid'])" in load("overrides/lib/employee_collections.dart")),
    ("purchase deletion eligibility test retained",
     "purchaseInvoiceCancellationBlockReason" in delete_test),
    ("popup, money, and deletion widget tests run before APK build",
     all(f"test/{test}" in workflow for test in (
         "purchase_sale_price_popup_test.dart",
         "money_display_test.dart",
         "purchase_invoice_cancellations_test.dart"
     )) and 0 <= workflow.find("flutter test") < workflow.find("flutter build apk")),
    ("manager app ID and signing guard remain",
     "com.alaa.vibsales.managerscan" in workflow and
     "apksigner" in workflow and
     "5b0b9b961fea105fd0ae225b7400046be9c98bad40f13ea13a8c1929811d2a2f" in workflow),
    ("APK version is not below the verified 0.2.87", bool(codes) and min(codes) >= 20087),
]

failures = [title for title, passed in checks if not passed]
for title, passed in checks:
    print(("PASS" if passed else "FAIL") + " | " + title)
if failures:
    print("\nBLOCK MANAGER UPDATE: stable 0.2.87 regression contract not met.", file=sys.stderr)
    for issue in failures:
        print(" - " + issue, file=sys.stderr)
    sys.exit(1)
print("\nVIB Manager stable 0.2.87 regression contract: PASSED")
