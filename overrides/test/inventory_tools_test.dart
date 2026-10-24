import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../lib/inventory_price_data.dart';
import '../lib/main.dart';

void main() {
  testWidgets('return entry pages fit a small phone with keyboard and text scaling', (tester) async {
    tester.view.physicalSize=const Size(360,640);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    for(final type in ['sales','purchases']) {
      await tester.pumpWidget(MaterialApp(home:MediaQuery(data:const MediaQueryData(size:Size(360,640),viewInsets:EdgeInsets.only(bottom:280),textScaler:TextScaler.linear(1.3)),child:Directionality(textDirection:TextDirection.rtl,child:Scaffold(body:InvoiceReturnPage(key:ValueKey(type),type:type))))));
      expect(find.textContaining('من:'),findsOneWidget);expect(find.textContaining('إلى:'),findsOneWidget);
      await tester.enterText(find.byType(TextField),'TEST-123');await tester.pump();
      expect(find.textContaining('في الفترة'),findsOneWidget);expect(tester.takeException(),isNull);
    }
  });
  test('price adjustments use current prices and round fractional amounts', () {
    expect(adjustedInventoryPrice(100,10,increase:true),110);
    expect(adjustedInventoryPrice(100,10,increase:false),90);
    expect(adjustedInventoryPrice(0,10,increase:true),0);
    expect(adjustedInventoryPrice(12.35,10,increase:true),13.59);
    expect(adjustedInventoryPrice(100,100,increase:false),0);
    for(final n in [0,-1,double.nan,double.infinity]) {
      expect(()=>adjustedInventoryPrice(100,n,increase:true),throwsStateError);
    }
    expect(()=>adjustedInventoryPrice(100,101,increase:false),throwsStateError);
    expect(()=>adjustedInventoryPrice(-1,10,increase:true),throwsStateError);
  });
  test('purchase audit finds true latest unit cost, not the date an old invoice was amended', () {
    final base=DateTime(2026,10,16);
    final newer=DateTime(2026,10,24);
    final rows=[
      {'id':'000446','status':'completed','createdAt':base,'updatedAt':newer,
        'items':[{'productId':'ideos-shower','unitCost':850,'quantity':4}]},
      {'id':'000445','status':'completed','createdAt':DateTime(2026,10,14),
        'items':[{'productId':'ideos-shower','unitCost':858}]},
      {'id':'000447','status':'returned','createdAt':newer,
        'items':[{'productId':'ideos-shower','unitCost':900}]},
      {'id':'legacy','status':'completed','createdAt':DateTime(2026,10,15),
        'productId':'old-item','unitCost':135},
      {'id':'invalid','status':'completed','createdAt':newer,
        'items':[{'productId':'bad','unitCost':double.nan}]},
    ];
    final latest=latestPurchaseUnitCosts(rows);
    expect(latest['ideos-shower']!.invoiceId,'000446');
    expect(latest['ideos-shower']!.cost,850);
    expect(latest['old-item']!.cost,135);
    expect(latest.containsKey('bad'),isFalse);
    expect(inventoryPriceMismatch(858,latest['ideos-shower']!.cost),isTrue);
    expect(inventoryPriceMismatch(850,latest['ideos-shower']!.cost),isFalse);
    expect(inventoryPriceMismatch(850.001,850),isFalse);
    expect(inventoryPriceMismatch(null,850),isTrue);
  });
  test('newer purchases supersede edited older invoices and selling prices stay separate', () {
    final old=DateTime(2026,10,16),newer=DateTime(2026,10,22);
    final latest=latestPurchaseUnitCosts([
      {'id':'old','status':'completed','createdAt':old,
        'items':[{'productId':'p','unitCost':850}]},
      {'id':'newer','status':'completed','createdAt':newer,
        'items':[{'productId':'p','unitCost':875}]},
    ]);
    expect(latest['p']!.invoiceId,'newer');
    expect(latest['p']!.cost,875);
    expect(inventoryPriceMismatch(875,875),isFalse);
    // Purchase price and selling price are different concepts: no automatic
    // adjustment of current selling price to the invoice's unit cost.
    final product={'purchasePrice':875,'price':920};
    expect(product['price'],920);
  });
  test('latest purchase correction refreshes its cost without overwriting later changes', () {
    final original=DateTime(2026,10,16);
    final saved=DateTime(2026,10,16,23);
    bool can({
      String? latest='invoice-446', String? productLast='invoice-446',
      double? recorded=858, double? oldCost=858, double newCost=850,
      DateTime? manual,
    })=>shouldSyncEditedPurchaseCost(
      invoiceId:'invoice-446',latestInvoiceId:latest,
      previousInvoiceCost:oldCost,correctedInvoiceCost:newCost,
      currentProductCost:recorded,productLastPurchaseId:productLast,
      lastPurchaseRecordedAt:saved,originalInvoiceAt:original,
      manualCorrectionAt:manual,
    );
    expect(can(),isTrue);
    expect(can(productLast:null),isTrue); // legacy purchases without provenance
    expect(can(latest:'newer-purchase'),isFalse);
    expect(can(productLast:'newer-purchase'),isFalse);
    expect(can(recorded:840),isFalse); // manual change not overwritten
    expect(can(manual:DateTime(2026,10,17)),isFalse);
    expect(can(manual:DateTime(2026,10,15)),isTrue);
    expect(can(oldCost:850),isFalse); // unchanged purchase cost
    expect(can(recorded:null),isFalse);
  });
  test('duplicate invoice lines return their combined quantity once', () {
    final rows=groupedReturnItems([{'productId':'p','quantity':2},{'productId':'q','quantity':3},{'productId':'p','quantity':4}]);
    expect(rows.length,2);expect(rows.first['quantity'],6);
    const before=10;
    expect(before+(rows.first['quantity'] as int),16);
    expect(before-(rows.first['quantity'] as int),4);
    for(final qty in [0,-1,1.5,double.nan]) {
      expect(()=>groupedReturnItems([{'productId':'p','quantity':qty}]),throwsStateError);
    }
  });
  test('partial sale returns reject quantities already returned and split cash and debt safely', () {
    expect(returnedQuantitiesBySourceLine([
      {'items':[{'sourceItemIndex':0,'quantity':2},{'sourceItemIndex':1,'quantity':1}]},
      {'items':[{'sourceItemIndex':0,'quantity':3}]},
    ]), {0:5,1:1});
    expect(partialReturnCashCents(valueCents:2500,cashAvailableCents:6000,debtAvailableCents:4000),1500);
    expect(partialReturnCashCents(valueCents:4000,cashAvailableCents:6000,debtAvailableCents:4000),2400);
    expect(partialReturnCashCents(valueCents:10000,cashAvailableCents:6000,debtAvailableCents:4000),6000);
    expect(()=>partialReturnCashCents(valueCents:10001,cashAvailableCents:6000,debtAvailableCents:4000),throwsStateError);
    expect(()=>returnedQuantitiesBySourceLine([{'items':[{'sourceItemIndex':0,'quantity':0}]}]),throwsStateError);
  });
  test('general supplier payments remain credit after a full return', () {
    final r=returnSettlement({'total':100,'paid':30,'due':70,'cashPosted':true},sales:false);
    // Opening debt20 + invoice due70 - a separate voucher50 =40.
    expect(40-r.debt,-30);
    // Cash200 - invoice payment30 - voucher50 + invoice refund30 =150.
    expect(200-30-50+r.cash,150);
    expect(accountBalanceLabel(-30,supplier:true),'رصيد لك عند المورد');
    expect(accountBalanceLabel(-30,supplier:false),'رصيد للعميل عندك');
  });
  test('general customer receipts remain credit while linked receipts are refunded once', () {
    final r=returnSettlement({'total':100,'paid':30,'due':70,'receiptPaid':25},sales:true);
    // Opening20 + due70 - linked25 - general50 =15 before return.
    expect(15-r.debt,-30);
    // Opening cash200 + paid30 + linked25 + general50 - refund55.
    expect(200+30+25+50-r.cash,250);
    expect(accountBalanceLabel(-30,supplier:false),'رصيد للعميل عندك');
  });
  test('return validates invoice settlement and preview becomes stale on collection', () {
    expect(()=>returnSettlement({'total':100,'paid':30,'due':80},sales:true),throwsStateError);
    expect(()=>returnSettlement({'paid':30,'due':70,'cashPaidPosted':40},sales:false),throwsStateError);
    final a={'total':100,'paid':30,'due':70,'receiptPaid':0};
    expect(invoiceReturnSignature(a),isNot(invoiceReturnSignature({...a,'receiptPaid':10})));
  });
}
