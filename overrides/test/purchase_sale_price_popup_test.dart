import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('manager purchase keeps selling price regardless of navigation owner flag', () {
    expect(purchaseEditorShowsSalePrice(owner:true, employeeApp:false), isTrue);
    expect(purchaseEditorShowsSalePrice(owner:false, employeeApp:false), isTrue);
    expect(purchaseEditorShowsSalePrice(owner:false, employeeApp:true), isFalse);
  });
  for (final width in [360.0, 564.0]) {
    testWidgets('purchase item modal has fourth editable sale price at $width', (tester) async {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final cost = TextEditingController(text: '6.50');
      final quantity = TextEditingController(text: '1');
      final salePrice = TextEditingController(text: '7.50');
      var salePriceEdits = 0;
      final discount = PurchaseDiscountDraft();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(body: Builder(builder: (context) => TextButton(
          onPressed: () => showInvoiceLineEditor(context,
            name: 'افيز حديد خمسة عين 1 بوصة',
            price: cost, quantity: quantity, discount: discount,
            unitCost: 6.50, sellingPrice: salePrice,
            onSellingPriceChanged: () => salePriceEdits++),
          child: const Text('فتح الصنف'),
        ))),
      ));
      await tester.tap(find.text('فتح الصنف'));
      await tester.pumpAndSettle();
      const priceKey = ValueKey('purchase-item-dialog-sale-price');
      expect(find.byKey(priceKey), findsOneWidget);
      expect(find.text('بيانات الصنف'), findsOneWidget);
      expect(find.text('مشتريات المدير • 0.2.90'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Discarded edits must not update the product's price.
      await tester.enterText(find.byKey(priceKey), '9.00');
      await tester.tap(find.text('تراجع'));
      await tester.pumpAndSettle();
      expect(salePrice.text, '7.50');
      expect(salePriceEdits, 0);
      // A confirmed edit changes only the selling price, not purchase cost or quantity.
      await tester.tap(find.text('فتح الصنف'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(priceKey), '9.00');
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();
      expect(salePrice.text, '9.00');
      expect(cost.text, '6.50');
      expect(quantity.text, '1');
      expect(salePriceEdits, 1);
      expect(tester.takeException(), isNull);
      cost.dispose(); quantity.dispose(); salePrice.dispose();
    });
  }



  for(final width in [360.0,564.0]) {
    testWidgets('manager purchase outer invoice table always has sale-price column at $width', (tester) async {
      tester.view.physicalSize=Size(width,760);
      tester.view.devicePixelRatio=1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final cost=TextEditingController(text:'377.65');
      final qty=TextEditingController(text:'1');
      final sale=TextEditingController(text:'466.10');
      var changed=0;
      await tester.pumpWidget(MaterialApp(
        theme:ThemeData(brightness:Brightness.dark),
        home:Scaffold(body:InvoiceEditorFrame(
          title:'فاتورة مشتريات',checkout:false,total:377.65,
          tableMode:true,
          purchaseSellingPriceColumn:purchaseEditorShowsSalePrice(owner:false,employeeApp:false),
          invoiceNumber:'000473',itemCount:1,quantityCount:1,
          body:ListView(children:[InvoiceCompactTableLine(
            number:1,name:'خلاط شجرة هواي',price:cost,quantity:qty,
            sellingPrice:sale,onSellingPriceChanged:()=>changed++,
            onEdit:(){},onDelete:(){},
          )]),actions:[const Text('إلغاء')],
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.text('سعر البيع'),findsOneWidget);
      final saleField=find.byKey(const ValueKey('purchase-sale-price-1'));
      expect(saleField,findsOneWidget);
      await tester.enterText(saleField,'500.00');
      expect(sale.text,'500.00');
      expect(changed,1);
      expect(cost.text,'377.65');
      expect(tester.takeException(),isNull);
      cost.dispose();qty.dispose();sale.dispose();
    });
  }

  testWidgets('editing an existing purchase shows a fourth sale price independently', (tester) async {
    final cost=TextEditingController(text:'6.50');
    final quantity=TextEditingController(text:'1');
    final sale=TextEditingController(text:'9.00');
    var changed=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(
      child:PurchaseInvoiceLine(
        number:1,name:'صنف مشتريات',cost:cost,quantity:quantity,
        sellingPrice:sale,onSellingPriceChanged:()=>changed++,
        enabled:true,totalEditable:true,discountDraft:PurchaseDiscountDraft(),
        onChanged:(){},onChoose:(){},onDelete:(){},
      ),
    ))));
    final priceInput=find.byKey(const ValueKey('purchase-item-dialog-sale-price'));
    expect(priceInput,findsOneWidget);
    await tester.enterText(priceInput,'11.00');
    expect(sale.text,'11.00');
    expect(cost.text,'6.50');
    expect(quantity.text,'1');
    expect(changed,1);
    expect(tester.takeException(),isNull);
    cost.dispose(); quantity.dispose(); sale.dispose();
  });

  testWidgets('sales invoice modal retains original three fields', (tester) async {
    final price = TextEditingController(text: '9.00');
    final quantity = TextEditingController(text: '1');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showInvoiceLineEditor(context,
          name: 'حنفية', price: price, quantity: quantity,
          discount: PurchaseDiscountDraft(), saleScreen: true),
        child: const Text('فتح المبيعات'),
      ),
    ))));
    await tester.tap(find.text('فتح المبيعات'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('purchase-item-dialog-sale-price')), findsNothing);
    expect(tester.takeException(), isNull);
    price.dispose(); quantity.dispose();
  });
}
