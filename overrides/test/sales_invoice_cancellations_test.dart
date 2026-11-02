import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeChequeTimeZones());

  Map<String, dynamic> invoice({
    String status = 'completed',
    num total = 350,
    num paid = 100,
    num due = 250,
    num receiptPaid = 0,
    bool onlineEver = false,
  }) => {
    'id': 'sale-abc', 'status': status, 'total': total, 'paid': paid,
    'due': due, 'receiptPaid': receiptPaid, 'onlinePaymentEver': onlineEver,
    'onlinePaid': 0,
  };

  test('invoice monetary fingerprint ignores irrelevant map key order and display metadata', () {
    final a=invoice()..['customerId']='c-22'..['branchId']='main'
      ..['items']=[{'productId':'p1','quantity':2,'unitPrice':50,'lineTotal':100}];
    final b=invoice()..['branchId']='main'..['customerId']='c-22'
      ..['printedAt']=Timestamp.now()
      ..['items']=[{'lineTotal':100.0,'unitPrice':50.0,'quantity':2,'productId':'p1'}];
    expect(saleCancellationFinancialSnapshot(a),saleCancellationFinancialSnapshot(b));
    b['items']=[{'productId':'p1','quantity':3,'unitPrice':50,'lineTotal':150}];
    expect(saleCancellationFinancialSnapshot(a),isNot(saleCancellationFinancialSnapshot(b)));
  });

  testWidgets('employee checkout shows every item and old/new balance in the review', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:SingleChildScrollView(
      child:EmployeeSaleCheckoutSummary(
        items:[(name:'خلاط',quantity:2,unitPrice:100.0),
               (name:'خرطوم شطاف',quantity:3,unitPrice:50.0)],
        previousBalance:700,total:350,paid:100,customerName:'عميل تجريبي',
      ),
    ))));
    expect(find.byKey(const ValueKey('employee-sale-checkout-review')), findsOneWidget);
    expect(find.textContaining('خلاط'),findsOneWidget);
    expect(find.textContaining('خرطوم شطاف'),findsOneWidget);
    expect(find.textContaining('الرصيد بعد الفاتورة'),findsOneWidget);
    expect(find.textContaining('950.00'),findsOneWidget);
  });

  testWidgets('staff entry screen always shows customer balance and item count', (tester) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SizedBox(width:355,
      child:EmployeeSaleEntryBalanceStrip(
        customerName:'عميل تجريبي',previousBalance:325.5,
        invoiceTotal:1020,itemCount:4,onChooseCustomer:(){},
      ),
    ))));
    expect(find.byKey(const ValueKey('staff-sale-entry-balances')),findsOneWidget);
    expect(find.textContaining('عدد البنود: 4'),findsOneWidget);
    expect(find.textContaining('1020.00'),findsOneWidget);
    expect(find.textContaining('325.50'),findsOneWidget);
    expect(find.textContaining('اختيار عميل'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('staff entry asks for client instead of making an absent balance zero', (tester) async {
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:EmployeeSaleEntryBalanceStrip(
      customerName:'',previousBalance:null,invoiceTotal:0,itemCount:0,
      onChooseCustomer:(){},
    ))));
    expect(find.textContaining('اختر العميل لعرض الرصيد'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  test('only a completed sale is eligible for mistaken-invoice cancellation', () {
    expect(saleInvoiceCanBeCancelled(invoice()), isTrue);
    for (final state in ['returned', 'cancelled', 'pending', 'draft']) {
      expect(saleInvoiceCanBeCancelled(invoice(status: state)), isFalse);
    }
  });

  test('a sale with partial returns cannot be cancelled and reversed twice', () {
    expect(saleInvoiceCanBeCancelled(invoice()..['partialReturnTotal'] = 1), isFalse);
    expect(saleInvoiceCanBeCancelled(invoice()
      ..['partialReturnQuantities'] = {'0': 1}), isFalse);
  });

  test('card-payment history must be handled separately before invoice cancellation', () {
    expect(saleInvoiceCanBeCancelled(invoice(onlineEver: true)), isFalse);
    expect(saleInvoiceCanBeCancelled(invoice()..['onlinePaid'] = 1), isFalse);
  });

  test('cash and credit are reversed once when there was no linked receipt', () {
    final reversed = saleCancellationSettlement(invoice());
    expect(reversed.cash, 100);
    expect(reversed.debt, 250);
  });

  test('cancelled receipt amount is NOT reversed twice in sale cancellation', () {
    // Previous separate receipt cancellation already removed 120 from the
    // cashbox and restored 120 of customer debt.
    final sale = invoice(total: 350, paid: 100, due: 250, receiptPaid: 120);
    final reversed = saleCancellationSettlement(sale);
    expect(reversed.cash, 100);
    expect(reversed.debt, 250);
    final regularReturn = returnSettlement(sale, sales: true);
    expect(regularReturn.cash, 220);
    expect(regularReturn.debt, 130);
  });

  test('movement report excludes cancelled sale from active total without double counting', () {
    final time=Timestamp.fromDate(DateTime(2026,11,2,10,0));
    final beginning=DateTime(2026,11,2),end=beginning;
    final rows=[
      {...invoice(), 'displayNumber':'S-001','customerName':'عميل','createdAt':time},
      {...invoice(status:'cancelled'), 'id':'sale-002','displayNumber':'S-002',
        'customerName':'عميل','createdAt':time},
    ];
    final report=summarizeInvoiceMovement(rows,beginning,end,type:'sales',returns: [
      {'id':'return-002','sourceInvoiceId':'sale-002','total':350,
        'customerName':'عميل','createdAt':time,'returnType':'cancellation'},
    ]);
    expect(report.rows.length,2);
    expect(report.active.length,1);
    expect(report.returnedCount,1);
    expect(report.netCents,35000);
  });
}
