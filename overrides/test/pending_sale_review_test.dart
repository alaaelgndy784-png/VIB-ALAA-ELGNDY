import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('approval alert names the employee, customer and server-calculated total',(){
    final data={'customerName':'مؤسسة النور','customerId':'customer','credit':true,'paid':10.0,
      'items':[{'productId':'p','quantity':2,'unitPrice':30.0,'basePrice':30.0,'discountPercent':0}]};
    final text=pendingApprovalAlertText('أحمد','request123456',data);
    expect(text,contains('أحمد'));expect(text,contains('مؤسسة النور'));
    expect(text,contains('60.00 ج.م'));expect(text,contains('request12'));
  });
  setUpAll(() async {
    await (FontLoader('InvoicePreview')..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'))).load();
  });
  for(final width in [360.0,564.0]) {
    testWidgets('approval invoice has aligned columns, long names, totals and reachable actions at $width', (tester) async {
      tester.view.physicalSize=Size(width,800);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final key=GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(theme:ThemeData(brightness:Brightness.dark,fontFamily:'InvoicePreview'),
        builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.3)),child:child!),
        home:Scaffold(body:PendingSaleInvoiceDialog(data:{'customerName':'زبون طياري','employeeName':'ربيع','status':'pending','credit':true,'paid':10,
          'createdAt':Timestamp.fromDate(DateTime(2026,10,5,19,23)),
          'items':List.generate(50,(i)=>{'productName':'مجري الحياة 40 سم عرض 7 اسم الصنف كامل وطويل ${i+1}','unitPrice':12.35,'quantity':2})},
          actions:[TextButton(onPressed:(){},child:const Text('إغلاق')),TextButton(onPressed:(){},child:const Text('رفض مع السبب')),FilledButton(onPressed:(){},child:const Text('اعتماد وحفظ'))])))));
      await tester.pumpAndSettle();
      expect(find.text('المنتج'),findsOneWidget);expect(find.text('السعر'),findsOneWidget);expect(find.text('العدد'),findsOneWidget);
      expect(find.text('الإجمالي: 1235.00 ج.م'),findsOneWidget);expect(find.text('المدفوع: 10.00 ج.م'),findsOneWidget);expect(find.text('المتبقي: 1225.00 ج.م'),findsOneWidget);
      expect(find.text('الأصناف: 50 • العدد: 100'),findsOneWidget);
      final first=find.byType(InvoiceCompactReadOnlyLine).first;
      final product=tester.getRect(find.descendant(of:first,matching:find.textContaining('مجري الحياة')));
      final price=tester.getRect(find.descendant(of:first,matching:find.text('12.35')));
      final quantity=tester.getRect(find.descendant(of:first,matching:find.text('2')));
      expect(product.left,greaterThan(price.right));expect(price.left,greaterThan(quantity.right));
      expect(tester.getRect(find.text('اعتماد وحفظ')).bottom,lessThan(800));expect(tester.takeException(),isNull);
      final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image=await boundary.toImage(pixelRatio:1.5);
        try {final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await Directory('dist').create(recursive:true);
          await File('dist/VIB-APPROVAL-INVOICE-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());}finally{image.dispose();}
      });
      await tester.drag(find.byType(SingleChildScrollView),const Offset(0,-8000));await tester.pumpAndSettle();
      expect(find.textContaining('مجري الحياة 40 سم عرض 7 اسم الصنف كامل وطويل 50').hitTestable(),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }
  test('removal hides rejected proposals in both app lists without hiding legacy pending or approved',(){
    expect(pendingSaleIsVisible({'status':'rejected','removed':true}),isFalse);
    for(final status in ['pending','rejected','approved'])expect(pendingSaleIsVisible({'status':status}),isTrue);
  });
}
