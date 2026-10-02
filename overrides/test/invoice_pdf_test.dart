import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('VibPreview')..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final thermal in [false,true]) {
    test('supplier payment voucher renders balances on ${thermal ? '80MM' : 'A4'}', () async {
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final bytes = await createSupplierPaymentVoucherPdf('PAY-001', {'accountName':'مورد الأدوات الصحية', 'supplierPhone':'01000000000', 'amount':1000.50, 'balanceBefore':30000, 'balanceAfter':28999.50, 'cashBefore':5000, 'cashAfter':3999.50, 'actorName':'علاء الجندي', 'note':'سداد مديونية المورد', 'createdAt':Timestamp.fromDate(DateTime(2026,10,3,12))}, font, thermal:thermal);
      expect(bytes.length,greaterThan(1000));
      Directory('dist').createSync(recursive:true);
      File('dist/VIB-SUPPLIER-PAYMENT-${thermal ? '80MM' : 'A4'}.pdf').writeAsBytesSync(bytes);
    });
  }

  for (final width in [360.0, 564.0]) {
    for(final sale in [false,true]) {
    testWidgets('two-step ${sale ? 'sales' : 'purchase'} editor at width $width retains edits and renumbers after deletion', (tester) async {
      tester.view.physicalSize=Size(width,760);tester.view.devicePixelRatio=1;
      addTearDown(() {tester.view.resetPhysicalSize();tester.view.resetDevicePixelRatio();});
      final costs=List.generate(22,(_)=>TextEditingController(text:'145.00'));
      final quantities=List.generate(22,(_)=>TextEditingController(text:'24'));
      final paid=TextEditingController(text:'200');
      final ids=List.generate(21,(i)=>i);
      final boundaryKey=GlobalKey();var checkout=false,credit=true,saves=0;
      await tester.pumpWidget(RepaintBoundary(key:boundaryKey,child:MaterialApp(theme:ThemeData(brightness:Brightness.dark,fontFamily:'VibPreview',
        colorScheme:ColorScheme.fromSeed(seedColor:gold,brightness:Brightness.dark)),home:Scaffold(
        body:MediaQuery(data:MediaQueryData(size:Size(width,760),textScaler:const TextScaler.linear(1.3)),
          child:Directionality(textDirection:TextDirection.rtl,child:StatefulBuilder(builder:(context,update)=>InvoiceEditorFrame(
            title:checkout ? 'حفظ الفاتورة' : sale ? 'فاتورة مبيعات' : 'فاتورة مشتريات',checkout:checkout,total:94386,
            headerAction:IconButton(tooltip:'المحادثة',onPressed:() {},icon:const Icon(Icons.chat_bubble_outline)),
            toolbar:InvoiceProductsBar(products:[(id:'extra',name:'صنف إضافي')],enabled:ids.length < 22,
              onSearch:()=>update(()=>ids.add(21)),onSelect:(_)=>update(()=>ids.add(21))),
            body:checkout ? ListView(children:[const Text('اختيار العميل أو المورد'),
              PurchaseSettlementPanel(total:94386,previousBalance:30000,credit:credit,paid:paid,enabled:true,
                partyLabel:sale ? 'العميل' : 'المورد',onModeChanged:(v)=>update(()=>credit=v),onChanged:()=>update(() {})),
            ]) : ListView(children:[for(var i=0;i<ids.length;i++) PurchaseInvoiceLine(
              key:ValueKey(ids[i]),number:i+1,name:'حنفية غسالة تركي نحاس اسم الصنف كامل رقم ${ids[i]+1}',
              cost:costs[ids[i]],quantity:quantities[ids[i]],enabled:true,onChanged:()=>update(() {}),onChoose:() {},
              onDelete:()=>update(()=>ids.removeAt(i)),
            )]),
            actions:[TextButton(onPressed:()=>update(()=>checkout=false),child:Text(checkout ? 'رجوع للبنود' : 'إلغاء')),
              FilledButton(onPressed:() {if(checkout) {saves++;} else {update(()=>checkout=true);}},child:Text(checkout ? 'تأكيد الحفظ' : 'إضافة'))],
          )))),
      ))));
      await tester.pumpAndSettle();
      expect(tester.takeException(),isNull);
      expect(find.text('بحث'),findsOneWidget);expect(find.text('إضافة بند جديد'),findsNothing);
      expect(find.byTooltip('المحادثة'),findsOneWidget);
      expect(find.text('آجل'),findsNothing);expect(find.text('اختيار العميل أو المورد'),findsNothing);
      expect(find.text('حنفية غسالة تركي نحاس اسم الصنف كامل رقم 1'),findsOneWidget);
      await tester.tap(find.text('بحث'));await tester.pumpAndSettle();expect(ids.length,22);
      await tester.enterText(find.widgetWithText(TextField,'145.00').first,'150.00');await tester.pumpAndSettle();
      expect(costs.first.text,'150.00');
      Directory('dist').createSync(recursive:true);
      await tester.runAsync(() async {
        final boundary=boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image=await boundary.toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);
        File('dist/VIB-${sale ? 'SALES' : 'PURCHASE'}-EDITOR-${width.toInt()}.png').writeAsBytesSync(data!.buffer.asUint8List());image.dispose();
      });
      await tester.tap(find.text('إضافة'));await tester.pumpAndSettle();expect(saves,0);
      expect(find.text('بحث'),findsNothing);expect(find.text('اختيار العميل أو المورد'),findsOneWidget);
      expect(find.byTooltip('المحادثة'),findsOneWidget);
      expect(find.text('آجل'),findsOneWidget);expect(paid.text,'200');
      await tester.tap(find.text('نقدي'));await tester.pumpAndSettle();expect(credit,false);
      await tester.tap(find.text('آجل'));await tester.pumpAndSettle();expect(credit,true);
      await tester.tap(find.text('رجوع للبنود'));await tester.pumpAndSettle();
      expect(costs.first.text,'150.00');expect(ids.length,22);expect(paid.text,'200');
      await tester.tap(find.byTooltip('حذف البند').first);await tester.pumpAndSettle();
      expect(ids.length,21);expect(find.text('1.'),findsOneWidget);
      expect(find.text('حنفية غسالة تركي نحاس اسم الصنف كامل رقم 2'),findsOneWidget);
      await tester.tap(find.text('إضافة'));await tester.pumpAndSettle();
      await tester.tap(find.text('تأكيد الحفظ'));expect(saves,1);expect(tester.takeException(),isNull);
      await tester.runAsync(() async {
        final boundary=boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image=await boundary.toImage(pixelRatio:2);final data=await image.toByteData(format:ui.ImageByteFormat.png);
        File('dist/VIB-${sale ? 'SALES' : 'PURCHASE'}-CHECKOUT-${width.toInt()}.png').writeAsBytesSync(data!.buffer.asUint8List());image.dispose();
      });
      await tester.pumpWidget(const SizedBox());for(final controller in [...costs,...quantities,paid]) {controller.dispose();}
    });
    }
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
