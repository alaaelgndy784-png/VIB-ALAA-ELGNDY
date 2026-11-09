import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vib_sales/sales_invoice_exit_guard.dart';

void main() {
  Widget testApp({bool saving = false}) => MaterialApp(
        home: Builder(
          builder: (pageContext) => Scaffold(
            body: Center(
              child: TextButton(
                child: const Text('افتح فاتورة جديدة'),
                onPressed: () => showDialog<void>(
                  context: pageContext,
                  barrierDismissible: false,
                  builder: (dialogContext) => SalesInvoiceExitGuard(
                    saving: saving,
                    child: AlertDialog(
                      title: const Text('فاتورة مبيعات'),
                      content: const Text('بند مسجل في الفاتورة'),
                      actions: [
                        TextButton(
                          onPressed: () => requestSalesInvoiceExit(
                            dialogContext,
                            saving: saving,
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

  testWidgets('Android back asks before discarding and cancel preserves items',
      (tester) async {
    await tester.pumpWidget(testApp());
    await tester.tap(find.text('افتح فاتورة جديدة'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الخروج من فاتورة المبيعات'), findsOneWidget);
    expect(find.text('بند مسجل في الفاتورة'), findsOneWidget);

    await tester.tap(find.text('استكمال الفاتورة'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الخروج من فاتورة المبيعات'), findsNothing);
    expect(find.text('بند مسجل في الفاتورة'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الخروج من فاتورة المبيعات'), findsOneWidget);

    await tester.tap(find.text('الخروج بدون حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('بند مسجل في الفاتورة'), findsNothing);
    expect(find.text('افتح فاتورة جديدة'), findsOneWidget);
  });

  testWidgets('saving keeps invoice open on Android back', (tester) async {
    await tester.pumpWidget(testApp(saving: true));
    await tester.tap(find.text('افتح فاتورة جديدة'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('بند مسجل في الفاتورة'), findsOneWidget);
    expect(find.text('تأكيد الخروج من فاتورة المبيعات'), findsNothing);
  });
}
