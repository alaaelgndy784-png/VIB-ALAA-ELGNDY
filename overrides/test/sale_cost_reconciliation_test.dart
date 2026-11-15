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

  group('FIFO profit for ABS sprayer sold at purchase prices', () {
    const id='import_250501182315';
    const name='شطاف ABS + لى حرارى مقبل [علبة]';
    const costFromCurrentCard=270.0;
    Map<String,dynamic> purchase(String ref, DateTime at, int qty, double cost) => {
      'id':ref,'createdAt':at,'status':'completed',
      'items':[{'productId':id,'productName':name,
        'quantity':qty,'unitCost':cost}],
    };
    Map<String,dynamic> sale(String ref, DateTime at, int qty, double price) => {
      'id':ref,'createdAt':at,'status':'completed',
      'items':[{'productId':id,'productName':name,'quantity':qty,
        'unitPrice':price,'purchasePriceAtSale':costFromCurrentCard}],
    };

    test('old lot sold first; later 50 at 267 and 50 at 270 yield 150 EGP', () {
      final purchases=[
        purchase('oct-lot',DateTime(2026,10,7,12,10),50,261),
        purchase('nov-lot-a',DateTime(2026,11,14,14,7),50,267),
        purchase('nov-lot-b',DateTime(2026,11,14,14,41),50,270),
      ];
      final sales=[
        sale('oct-sale',DateTime(2026,10,7,12,50),50,266.22),
        sale('001331',DateTime(2026,11,14,18,16),100,270),
      ];
      final fifo=fifoSaleCostsFromPurchaseLots(purchases:purchases,sales:sales);
      expect(fifo['oct-sale']![id],261);
      expect(fifo['001331']![id],268.5);
      final revenue=100*270;
      final cost=fifo['001331']![id]!*100;
      expect(revenue-cost,150);
      expect(cost,26850);
      // The original saved cost snapshot of 270 EGP per unit remains unchanged.
      expect((sales[1]['items'] as List).first['purchasePriceAtSale'],270);
    });

    test('never pull a later purchase backward in time to invent profit', () {
      final fifo=fifoSaleCostsFromPurchaseLots(
        purchases:[purchase('later',DateTime(2026,11,15),100,200)],
        sales:[sale('before',DateTime(2026,11,14),100,270)]);
      expect(fifo['before'],isNull);
    });

    test('does not mix different product names sharing the same product id', () {
      final fifo=fifoSaleCostsFromPurchaseLots(
        purchases:[purchase('a',DateTime(2026,11,13),50,267)],
        sales:[{
          'id':'different','createdAt':DateTime(2026,11,14),
          'items':[{'productId':id,'productName':'شطاف مختلف',
            'quantity':50,'unitPrice':270}],
        }]);
      expect(fifo['different'],isNull);
    });

    test('sale with incomplete purchase history gets no guessed FIFO price', () {
      final fifo=fifoSaleCostsFromPurchaseLots(
        purchases:[purchase('half',DateTime(2026,11,13),50,267)],
        sales:[sale('full',DateTime(2026,11,14),100,270)]);
      expect(fifo['full'],isNull);
    });
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
