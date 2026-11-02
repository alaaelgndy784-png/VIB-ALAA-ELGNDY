import 'package:flutter_test/flutter_test.dart';
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
