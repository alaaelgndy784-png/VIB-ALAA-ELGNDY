import 'package:flutter_test/flutter_test.dart';
import '../lib/inventory_price_data.dart';
import '../lib/main.dart';

void main() {
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
  test('general supplier payments remain credit after a full return', () {
    final r=returnSettlement({'total':100,'paid':30,'due':70,'cashPosted':true},sales:false);
    // Opening debt20 + invoice due70 - a separate voucher50 =40.
    expect(40-r.debt,-30);
    // Cash200 - invoice payment30 - voucher50 + invoice refund30 =150.
    expect(200-30-50+r.cash,150);
    expect(accountBalanceLabel(-30,supplier:true),'رصيد لك عند المورد');
    expect(accountBalanceLabel(-30,supplier:false),'رصيد للعميل عندك');
  });
  test('return validates invoice settlement and preview becomes stale on collection', () {
    expect(()=>returnSettlement({'total':100,'paid':30,'due':80},sales:true),throwsStateError);
    expect(()=>returnSettlement({'paid':30,'due':70,'cashPaidPosted':40},sales:false),throwsStateError);
    final a={'total':100,'paid':30,'due':70,'receiptPaid':0};
    expect(invoiceReturnSignature(a),isNot(invoiceReturnSignature({...a,'receiptPaid':10})));
  });
}
