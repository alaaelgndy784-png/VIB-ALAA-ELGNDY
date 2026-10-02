import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final brand = <String, dynamic>{'companyName': 'VIB للتجارة والتوزيع', 'address': 'عنوان الشركة - مثال توضيحي',
    'taxNumber': '123-456-789', 'commercialRegister': '54321', 'phone': '01000000000', 'phone2': '01100000000', 'invoiceFooter': 'شكراً لتعاملكم معنا - نموذج توضيحي للطباعة'};
  for (final action in [('طباعة الفاتورة — A4 أو 80 مللي', 'print'), ('مشاركة PDF / إرسال على واتساب', 'share'), ('إغلاق', 'close')]) {
    testWidgets('saved invoice confirmation returns ${action.$2} after closing', (tester) async {
      String? selected;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
        TextButton(onPressed: () async {
          selected = await showDialog<String>(context: context, barrierDismissible: false,
            builder: (_) => const InvoiceSavedDialog(invoiceId: 'TEST-123'));
        }, child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('تم حفظ الفاتورة بنجاح'), findsOneWidget);
      expect(find.text('رقم الفاتورة: TEST-123'), findsOneWidget);
      await tester.tap(find.text(action.$1));
      await tester.pumpAndSettle();
      expect(selected, action.$2);
      expect(find.byType(InvoiceSavedDialog), findsNothing);
    });
  }
  testWidgets('invoice error appears above open purchase dialog and leaves form intact', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => showDialog<void>(context: context, builder: (invoiceContext) =>
        AlertDialog(title: const Text('فاتورة مشتريات'), actions: [
          TextButton(onPressed: () => showInvoiceSaveProblem(invoiceContext, 'قيمة المدفوع غير صحيحة'),
            child: const Text('حفظ الفاتورة')),
        ])), child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حفظ الفاتورة'));
    await tester.pumpAndSettle();
    expect(find.text('تنبيه حفظ الفاتورة'), findsOneWidget);
    expect(find.text('قيمة المدفوع غير صحيحة'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.text('رجوع لتعديل الفاتورة'));
    await tester.pumpAndSettle();
    expect(find.text('تنبيه حفظ الفاتورة'), findsNothing);
    expect(find.text('فاتورة مشتريات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('permission failure is explained without reporting success', () {
    final text = invoiceSaveFailureMessage(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    expect(text, contains('الخادم رفض صلاحيات العملية'));
    expect(text, isNot(contains('تم حفظ')));
  });
  final rows = [
    {'productName': 'حنفية غسالة تركي', 'quantity': 2, 'unitPrice': 175, 'lineTotal': 350},
    {'productName': 'حنفية نصف بوصة الحياة', 'quantity': 3, 'unitPrice': 195, 'lineTotal': 585},
    {'productName': 'طاسة دش الحياة مقاس 20 × 20', 'quantity': 1, 'unitPrice': 325, 'lineTotal': 325},
  ];
  for (final paper in ['a4','80']) {
    for (final long in [false,true]) {
      test('$paper ${long ? 'long invoice pagination' : 'brand and totals'}', () async {
        final items = long ? List.generate(50, (i) => {...rows[i % 3], 'productName': '${rows[i % 3]['productName']} - صنف إضافي رقم ${i + 1}'}) : rows;
        final total = items.fold<double>(0, (sum, row) => sum + (row['lineTotal'] as num).toDouble());
        final bytes = await createInvoicePdf('sales', 'VIB-DEMO-2026', {'items': items, 'total': total, 'paid': 500,
          'due': total - 500, 'customerName': 'عميل تجريبي', 'customerPhone': '01200000000',
          'customerPreviousBalance': 200, 'customerBalanceAfter': total - 300,
          'status': 'completed', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2, 15, 30))}, paperChoice: paper, settingsOverride: brand);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        expect(bytes.length, greaterThan(1000));
        Directory('dist').createSync(recursive: true);
        File('dist/VIB-INVOICE-${paper.toUpperCase()}${long ? '-LONG' : ''}.pdf').writeAsBytesSync(bytes);
      });
    }
  }
}
