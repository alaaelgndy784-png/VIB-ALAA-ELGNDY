import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final products = <VibMovementProductChoice>[
    (id: 'a1', name: 'سماعة شطاف جروهي نيكل', code: 'G-10'),
    (id: 'a2', name: 'خلاط 1 مخرج جروهي', code: 'G-20'),
    (id: 'a3', name: 'لافيتا كود 4', code: 'L-4'),
  ];

  test('compact picker filters names and stock codes', () {
    expect(vibFilterMovementProductChoices(products, 'جروهي'), hasLength(2));
    expect(vibFilterMovementProductChoices(products, 'G-20').single.id, 'a2');
    expect(vibFilterMovementProductChoices(products, 'لافيتا').single.id, 'a3');
    expect(vibFilterMovementProductChoices(products, 'غير موجود'), isEmpty);
  });

  testWidgets('product picker shows separated rows and returns correct item', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    String? selection;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: Builder(builder: (context) =>
        FilledButton(onPressed: () async {
          selection = await showVibMovementProductPicker(context, products);
        }, child: const Text('اختيار')))),
    ));
    await tester.tap(find.text('اختيار'));
    await tester.pumpAndSettle();
    expect(find.text('اختيار الصنف'), findsOneWidget);
    expect(find.text('النتائج: 3 صنف'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'خلاط');
    await tester.pumpAndSettle();
    expect(find.text('النتائج: 1 صنف'), findsOneWidget);
    expect(find.text('خلاط 1 مخرج جروهي'), findsOneWidget);
    expect(find.text('سماعة شطاف جروهي نيكل'), findsNothing);
    await tester.tap(find.text('خلاط 1 مخرج جروهي'));
    await tester.pumpAndSettle();
    expect(selection, 'a2');
    expect(tester.takeException(), isNull);
  });

  test('purchase and sales PDFs generate readable invoice-based pages', () async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final time = DateTime(2026, 10, 25, 12, 30);
    final buys = [
      VibProductInvoiceHit(id: 'purchase-document-internal-id',
        number: '431', party: 'مؤسسة أدوات صحية',
        type: 'purchases', date: time,
        invoice: const {'supplierName': 'مؤسسة أدوات صحية'},
        item: const {'productName': 'خلاط', 'quantity': 5,
          'unitCost': 120, 'lineTotal': 600}),
      VibProductInvoiceHit(id: 'other-purchase-id',
        number: '432', party: 'مورد آخر',
        type: 'purchases', date: time,
        invoice: const {'supplierName': 'مورد آخر'},
        item: const {'productName': 'خلاط', 'quantity': 2,
          'unitCost': 125, 'lineTotal': 250}),
    ];
    final buyingPdf = await createVibProductInvoiceReportPdf(
      productName: 'خلاط', type: 'purchases',
      hits: buys, font: font, allDates: true);
    expect(buyingPdf.sublist(0, 4), [37, 80, 68, 70]);
    expect(buyingPdf.length, greaterThan(2000));
    final sellingPdf = await createVibProductInvoiceReportPdf(
      productName: 'خلاط', type: 'sales',
      hits: [VibProductInvoiceHit(id: 'sale-id',
        number: '1223', party: 'عميل',
        type: 'sales', date: time, invoice: const {},
        item: const {'quantity': 1, 'unitPrice': 180,
          'lineTotal': 180})],
      font: font, allDates: false,
      from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));
    expect(sellingPdf.sublist(0, 4), [37, 80, 68, 70]);
    expect(sellingPdf.length, greaterThan(2000));
  });
}
