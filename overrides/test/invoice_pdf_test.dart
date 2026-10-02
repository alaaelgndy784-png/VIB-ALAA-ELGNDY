import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [360.0, 564.0]) {
    testWidgets('purchase form keeps names, add button, settlement and save usable at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
      final costs = List.generate(22, (_) => TextEditingController(text: '145.00'));
      final quantities = List.generate(22, (_) => TextEditingController(text: '24'));
      final paid = TextEditingController(text: '0');
      final boundaryKey = GlobalKey();
      var count = 21, credit = true, saves = 0;
      await tester.pumpWidget(RepaintBoundary(key: boundaryKey, child: MaterialApp(theme: ThemeData.dark(), home: Scaffold(
        body: MediaQuery(data: MediaQueryData(size: Size(width, 760), textScaler: const TextScaler.linear(1.3)),
          child: Directionality(textDirection: TextDirection.rtl, child: StatefulBuilder(builder: (context, update) => PurchaseInvoiceFrame(
            itemCount: count, onAdd: () => update(() => count++),
            body: ListView(children: [for (var i = 0; i < count; i++) PurchaseInvoiceLine(
              number: i + 1, name: 'حنفية غسالة تركي نحاس اسم الصنف كامل رقم ${i + 1}',
              cost: costs[i], quantity: quantities[i], enabled: true, onChanged: () => update(() {}),
              onChoose: () {}, onDelete: () {},
            )]),
            settlement: PurchaseSettlementPanel(total: 94386, previousBalance: 30000, credit: credit,
              paid: paid, enabled: true, onModeChanged: (v) => update(() => credit = v), onChanged: () => update(() {})),
            actions: [TextButton(onPressed: () {}, child: const Text('إلغاء')),
              FilledButton(onPressed: () => saves++, child: const Text('حفظ الفاتورة'))],
          )))),
      ))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('حنفية غسالة تركي نحاس اسم الصنف كامل رقم 1'), findsOneWidget);
      expect(find.text('إضافة بند جديد'), findsOneWidget);
      expect(find.text('آجل'), findsOneWidget);
      await tester.tap(find.text('إضافة بند جديد'));
      await tester.pumpAndSettle();
      expect(count, 22);
      expect(costs.first.text, '145.00');
      await tester.tap(find.text('نقدي'));
      await tester.pumpAndSettle();
      expect(credit, isFalse);
      await tester.tap(find.text('آجل'));
      await tester.pumpAndSettle();
      expect(credit, isTrue);
      await tester.tap(find.text('حفظ الفاتورة'));
      expect(saves, 1);
      expect(tester.takeException(), isNull);
      Directory('dist').createSync(recursive: true);
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('dist/VIB-PURCHASE-FORM-${width.toInt()}.png').writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      for (final controller in [...costs, ...quantities, paid]) { controller.dispose(); }
    });
  }
  for (final thermal in [false, true]) {
  for (final count in [1, 140]) {
    test('customer daily payment ${thermal ? '80mm' : 'A4'} PDF renders $count receipts', () async {
      final day = DateTime(2026, 10, 2);
      final receipts = List.generate(count, (i) => <String, dynamic>{
        'id': 'RECEIPT-${i + 1}', 'customerId': 'customer-${i ~/ 2}',
        'customerName': 'تاجر تجريبي رقم ${i ~/ 2 + 1}', 'amount': 100.25,
        'actorName': 'موظف التحصيل', 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2, 12)),
      });
      final report = summarizeReceiptDay(receipts, day);
      expect(report.totalCents, count * 10025);
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final bytes = await createCustomerPaymentReportPdf(day, report, font, owner: true, thermal: thermal);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(1000));
      Directory('dist').createSync(recursive: true);
      File('dist/VIB-CUSTOMER-PAYMENTS-${thermal ? '80MM' : 'A4'}${count == 1 ? '' : '-LONG'}.pdf').writeAsBytesSync(bytes);
    });
  }
  }
  final brand = <String, dynamic>{'companyName': 'VIB للتجارة والتوزيع', 'address': 'عنوان الشركة - مثال توضيحي',
    'taxNumber': '123-456-789', 'commercialRegister': '54321', 'phone': '01000000000', 'phone2': '01100000000', 'invoiceFooter': 'شكراً لتعاملكم معنا - نموذج توضيحي للطباعة'};
  for (final paper in ['a4', '80']) {
    test('purchase $paper prints supplier outstanding balance after instalment', () async {
      final bytes = await createInvoicePdf('purchases', 'PURCHASE-DEMO', {
        'items': [{'productName': 'حنفية غسالة تركي نحاس', 'quantity': 24, 'unitCost': 145, 'lineTotal': 3480}],
        'total': 3480, 'paid': 1000, 'due': 2480, 'supplierName': 'مورد تجريبي',
        'supplierPreviousBalance': 30000, 'supplierBalanceAfter': 32480, 'status': 'completed',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2, 23)),
      }, paperChoice: paper, settingsOverride: brand);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      Directory('dist').createSync(recursive: true);
      File('dist/VIB-PURCHASE-BALANCE-${paper.toUpperCase()}.pdf').writeAsBytesSync(bytes);
    });
  }
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
