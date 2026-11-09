import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeChequeTimeZones);

  final stamp=Timestamp.fromDate(DateTime.utc(2026,11,9,11,30));
  Map<String,dynamic> invoice(String id, String customerId, num amount, {
    String status='completed', int invoiceNumber=1323,
  }) => {
    'id':id,'status':status,'createdAt':stamp,
    'internalNumber':invoiceNumber,
    'customerId':customerId,'customerName':'عميل اختبار',
    'paid':amount,'total':amount,'due':0,
  };
  Map<String,dynamic> receipt(String id,String customerId,num amount)=> {
    'id':id,'createdAt':stamp,'receiptDate':stamp,
    'customerId':customerId,'customerName':'عميل اختبار',
    'receiptNumber':id,'amount':amount,
  };

  test('cash paid on sale 1323 and later receipt both count as collections', () {
    final rows=vibCustomerPaymentReportRows(
      sales:[invoice('s1323','cust',6444.84)],
      receipts:[receipt('r1','cust',1000)],
      cancelledReceiptIds:{},
    );
    final period=summarizeReceiptPeriod(rows,DateTime(2026,11,9),DateTime(2026,11,9));
    expect(period.receiptCount,2);
    expect(period.totalCents,744484);
    expect(period.customers.single.receipts.map((row)=>row['paymentSource']).toSet(),{'receipt','invoice'});
    expect(rows.firstWhere((row)=>row['paymentSource']=='invoice')['receiptNumber'],'1323');
  });

  test('same sale or receipt document never appears twice', () {
    final rows=vibCustomerPaymentReportRows(
      sales:[invoice('s1323','cust',6444.84),invoice('s1323','cust',6444.84)],
      receipts:[receipt('r1','cust',1000),receipt('r1','cust',1000)],
      cancelledReceiptIds:{},
    );
    expect(rows.length,2);
    expect(rows.fold<double>(0,(sum,row)=>sum+(row['amount'] as num)),7444.84);
  });

  test('cancelled receipt and cancelled or returned invoice excluded, zero-paid excluded', () {
    final rows=vibCustomerPaymentReportRows(
      receipts:[receipt('cancelled-receipt','cust',150),receipt('ok','cust',200)],
      sales:[
        invoice('cancelled-sale','cust',852.5,status:'cancelled',invoiceNumber:1306),
        invoice('returned-sale','cust',400,status:'returned',invoiceNumber:1305),
        invoice('credit-sale','cust',0,invoiceNumber:1324),
        invoice('active','cust',600,invoiceNumber:1325),
      ],
      cancelledReceiptIds:{'cancelled-receipt'},
    );
    expect(rows.length,2);
    expect(rows.fold<num>(0,(sum,row)=>sum+(row['amount'] as num)),800);
  });

  test('only selected customer gets that customer invoices and receipts', () {
    final rows=vibCustomerPaymentReportRows(
      receipts:[receipt('a1','a',50),receipt('b1','b',250)],
      sales:[invoice('a2','a',100),invoice('b2','b',400)],
      cancelledReceiptIds:{},
    );
    final all=summarizeReceiptPeriod(rows,DateTime(2026,11,9),DateTime(2026,11,9));
    final selected=vibSelectReceiptParty(all,'','customer:a');
    expect(selected.totalCents,15000);
    expect(selected.receiptCount,2);
    expect(vibReceiptReportFingerprint(selected),isNot(contains('b2')));
  });
}
