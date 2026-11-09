import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final purchases = <Map<String,dynamic>>[
    {
      'status':'completed',
      'createdAt':DateTime(2026,10,17),
      'items':[{
        'productId':'shared-corner-code',
        'productName':'ركنه 3 رف دهبى موكا',
        'unitCost':320.0,
      }],
    },
    {
      'status':'completed',
      'createdAt':DateTime(2026,10,23),
      'items':[{
        'productId':'shared-corner-code',
        'productName':'ركنه 1 رف نيكل استلس',
        'unitCost':135.0,
      }],
    },
  ];

  test('historic sale cost is 135 from matching purchase, not 320 from reused id', () {
    final costs=verifiedPurchaseCostsAtSale(
      saleDate:DateTime(2026,10,28),
      productNames:{'shared-corner-code':'ركنة 1 رف نيكل استلس'},
      purchases:purchases,
    );
    expect(costs['shared-corner-code'], 135.0);
    expect((154.50-135.0)*5,97.5);
  });

  test('old sale retains old cost before newer purchase', () {
    final costs=verifiedPurchaseCostsAtSale(
      saleDate:DateTime(2026,10,20),
      productNames:{'shared-corner-code':'ركنة 3 رف دهبى موكا'},
      purchases:purchases,
    );
    expect(costs['shared-corner-code'], 320.0);
  });

  test('no match when sale name differs or purchase is later', () {
    expect(verifiedPurchaseCostsAtSale(
      saleDate:DateTime(2026,10,18),
      productNames:{'shared-corner-code':'ركنة 1 رف نيكل استلس'},
      purchases:purchases,
    ),isEmpty);
  });

  test('cancelled purchases cannot change cost snapshots', () {
    final costs=verifiedPurchaseCostsAtSale(
      saleDate:DateTime(2026,11,5),
      productNames:{'shared-corner-code':'ركنة 1 رف نيكل استلس'},
      purchases:[...purchases,{
        'status':'cancelled',
        'createdAt':DateTime(2026,11,1),
        'items':[{
          'productId':'shared-corner-code',
          'productName':'ركنة 1 رف نيكل استلس',
          'unitCost':900.0,
        }],
      }],
    );
    expect(costs['shared-corner-code'],135.0);
  });

  testWidgets('each draft invoice item has a visible working remove button', (tester) async {
    final price=TextEditingController(text:'154.50'),quantity=TextEditingController(text:'5');
    var removed=false;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:450,
      child:InvoiceCompactTableLine(number:1,name:'ركنة 1 رف',price:price,
        quantity:quantity,onDelete:()=>removed=true)))));
    final button=find.byKey(const ValueKey('remove-draft-invoice-line-1'));
    expect(button,findsOneWidget);
    await tester.tap(button);
    expect(removed,isTrue);
    price.dispose();
    quantity.dispose();
  });
}
