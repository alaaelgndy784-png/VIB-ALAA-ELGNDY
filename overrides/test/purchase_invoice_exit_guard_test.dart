import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vib_sales/purchase_invoice_exit_guard.dart';

void main() {
  Widget app({bool saving = false}) => MaterialApp(
        home: Builder(
          builder: (page) => Scaffold(
            body: Center(
              child: TextButton(
                child: const Text('افتح فاتورة مشتريات'),
                onPressed: () => showDialog<void>(
                  context: page,
                  barrierDismissible: false,
                  builder: (dialog) => PurchaseInvoiceExitGuard(
                    saving: saving,
                    child: AlertDialog(
                      title: const Text('فاتورة مشتريات'),
                      content: const Text('بنود المشتريات غير المحفوظة'),
                      actions: [
                        TextButton(
                          onPressed: () => requestPurchaseInvoiceExit(
                            dialog, saving: saving,
                          ),
                          child: const Text('إلغاء'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('Android Back and cancel require confirmation and keep draft',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('افتح فاتورة مشتريات'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الخروج من فاتورة المشتريات'), findsOneWidget);
    expect(find.text('بنود المشتريات غير المحفوظة'), findsOneWidget);

    await tester.tap(find.text('استكمال الفاتورة'));
    await tester.pumpAndSettle();
    expect(find.text('بنود المشتريات غير المحفوظة'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الخروج من فاتورة المشتريات'), findsOneWidget);

    await tester.tap(find.text('الخروج بدون حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('بنود المشتريات غير المحفوظة'), findsNothing);
    expect(find.text('افتح فاتورة مشتريات'), findsOneWidget);
  });

  testWidgets('Back while saving cannot close invoice', (tester) async {
    await tester.pumpWidget(app(saving: true));
    await tester.tap(find.text('افتح فاتورة مشتريات'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('بنود المشتريات غير المحفوظة'), findsOneWidget);
    expect(find.text('تأكيد الخروج من فاتورة المشتريات'), findsNothing);
  });
}
