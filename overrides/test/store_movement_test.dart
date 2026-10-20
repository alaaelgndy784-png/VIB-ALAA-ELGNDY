import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeChequeTimeZones);

  test('store movement totals use selected Cairo dates and keep returns separate', () {
    final from = DateTime(2026, 10, 1), to = DateTime(2026, 10, 2);
    final start = movementReportBoundary(from), end = movementReportBoundary(to, next: true);
    final report = summarizeStoreMovement(
      from: from, to: to,
      sales: [
        {'id':'s1','createdAt':Timestamp.fromDate(start),'total':200,'paid':100,'due':100,'onlinePaid':10,
          'items':[{'quantity':2,'purchasePriceAtSale':25}]},
        {'id':'outside','createdAt':Timestamp.fromDate(end),'total':500,'paid':500,'due':0},
      ],
      purchases: [{'id':'p1','createdAt':Timestamp.fromDate(start),'total':100,'paid':40,'due':60,
        'cashPosted':true,'cardPaid':20,'chequePaid':5}],
      salesReturns: [{'id':'sr1','createdAt':Timestamp.fromDate(start.add(const Duration(days:1))),'total':20}],
      purchaseReturns: const [],
      expenses: [{'id':'e1','createdAt':Timestamp.fromDate(start),'amount':10}],
      movements: [
        {'id':'sp1','createdAt':Timestamp.fromDate(start),'accountType':'suppliers','kind':'payment','amount':5},
        {'id':'c1','createdAt':Timestamp.fromDate(start),'accountType':'cash','delta':50},
        {'id':'c2','createdAt':Timestamp.fromDate(start),'accountType':'cash','delta':-5},
      ],
      receipts: [
        {'id':'r1','receiptDate':Timestamp.fromDate(start),'createdAt':Timestamp.fromDate(start),'amount':25},
        {'id':'outside','receiptDate':Timestamp.fromDate(end),'createdAt':Timestamp.fromDate(end),'amount':500},
      ],
      customers: [{'balance':70,'openingBalance':10}], suppliers: [{'balance':150,'openingBalance':20}], cashBalance:45.4,
    );
    expect(report['إجمالي المبيعات'].amountCents,20000);
    expect(report['إجمالي المبيعات نقدًا'].amountCents,9000);
    expect(report['إجمالي المبيعات آجل'].amountCents,10000);
    expect(report['إجمالي المبيعات (بطاقة)'].amountCents,1000);
    expect(report['إجمالي مرتجع المبيعات'].amountCents,2000);
    expect(report['إجمالي المشتريات'].amountCents,10000);
    expect(report['إجمالي المشتريات (بطاقة)'].amountCents,2000);
    expect(report['إجمالي المشتريات (شيك)'].amountCents,500);
    expect(report['إجمالي السداد للموردين'].amountCents,4500);
    expect(report['إجمالي المتبقي للموردين من الفواتير'].amountCents,13000);
    expect(report['إجمالي المتبقي عند العملاء من الفواتير'].amountCents,6000);
    expect(report['إجمالي السداد من العملاء'].amountCents,2500);
    expect(report['الرصيد في الصندوق'].amountCents,4540);
    expect(report['حركة الصندوق خلال الفترة'].amountCents,4500);
    expect(report['إجمالي الأرباح'].amountCents,13000);
    expect(report['إجمالي الأرباح بعد خصم المصروفات'].amountCents,12000);
    expect(report['إجمالي المبيعات'].entries,hasLength(1));
  });

  test('store movement rejects a reversed date range', () {
    expect(() => summarizeStoreMovement(from:DateTime(2026,10,2),to:DateTime(2026,10,1),
      sales:const [],purchases:const [],salesReturns:const [],purchaseReturns:const [],expenses:const [],
      movements:const [],receipts:const [],customers:const [],suppliers:const [],cashBalance:0),throwsStateError);
  });
  test('cancelled customer receipts and supplier vouchers do not inflate store movement totals', () {
    final day = DateTime(2026, 10, 19);
    final at = Timestamp.fromDate(movementReportBoundary(day).add(const Duration(hours: 12)));
    Map<String, dynamic> movement(String id, double amount) => {
      'id': id, 'createdAt': at, 'accountType': 'suppliers', 'kind': 'payment', 'amount': amount,
    };
    Map<String, dynamic> receipt(String id, double amount) => {
      'id': id, 'createdAt': at, 'receiptDate': at, 'amount': amount,
    };
    final report = summarizeStoreMovement(
      from: day, to: day, sales: const [], purchases: const [],
      salesReturns: const [], purchaseReturns: const [], expenses: const [],
      movements: [movement('active-payment', 200), movement('cancelled-payment', 700)],
      receipts: [receipt('active-receipt', 4245), receipt('cancelled-receipt', 17110)],
      customers: const [], suppliers: const [], cashBalance: 0,
      cancelledReceiptIds: {'cancelled-receipt'},
      cancelledSupplierPaymentIds: {'cancelled-payment'},
    );
    expect(report['إجمالي السداد من العملاء'].amountCents, 424500);
    expect(report['إجمالي السداد من العملاء'].entries, hasLength(1));
    expect(report['إجمالي السداد للموردين'].amountCents, 20000);
    expect(report['إجمالي السداد للموردين'].entries, hasLength(1));
  });

}
