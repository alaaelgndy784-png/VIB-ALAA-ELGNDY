import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  test('purchase delete only applies to complete modern invoices without returns', () {
    final invoice = <String, dynamic>{
      'status': 'completed', 'supplierId': 'supplier-1',
      'items': [{'productId':'p1','quantity':2,'unitCost':6.50}],
      'total': 13.00, 'paid': 3.00, 'due': 10.00,
    };
    expect(purchaseInvoiceCanBeCancelled(invoice), isTrue);
    expect(purchaseInvoiceCanBeCancelled({...invoice, 'status':'cancelled'}), isFalse);
    expect(purchaseInvoiceCanBeCancelled({...invoice, 'status':'returned'}), isFalse);
    expect(purchaseInvoiceCanBeCancelled({...invoice, 'status':'pending'}), isFalse);
    expect(purchaseInvoiceCanBeCancelled({...invoice, 'items': []}), isFalse);
    expect(purchaseInvoiceCanBeCancelled({...invoice, 'supplierId': ''}), isFalse);
    expect(purchaseInvoiceCanBeCancelled({...invoice, 'partialReturnTotal': 1}), isFalse);
    expect(purchaseInvoiceCanBeCancelled({...invoice,
      'partialReturnQuantities': {'p1': 1}}), isFalse);
  });

  for (final saleColumn in [false, true]) {
    testWidgets('draft invoice shows actual مسح text next to row saleColumn=$saleColumn',
        (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
      });
      final price = TextEditingController(text: '6.50');
      final quantity = TextEditingController(text: '1');
      final selling = TextEditingController(text: '9.00');
      var removed = false;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Directionality(
        textDirection: TextDirection.rtl, child: InvoiceCompactTableLine(
          number: 1, name: 'افيز حديد', price: price, quantity: quantity,
          sellingPrice: saleColumn ? selling : null,
          onDelete: () => removed = true,
        ),
      ))));
      expect(find.text('مسح'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('مسح'));
      await tester.pumpAndSettle();
      expect(removed, isTrue);
      price.dispose(); quantity.dispose(); selling.dispose();
    });
  }
}
