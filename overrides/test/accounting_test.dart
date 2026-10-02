import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../lib/main.dart';

void main() {
  Map<String, dynamic> receipt(String id, String customerId, String name, num amount, DateTime at) => {
    'id': id, 'customerId': customerId, 'customerName': name, 'amount': amount, 'createdAt': Timestamp.fromDate(at),
  };
  test('daily receipts include midnight and exclude next day, grouping by customer ID', () {
    final report = summarizeReceiptDay([
      receipt('r0', 'a', 'Trader', 999, DateTime(2026, 10, 1, 23, 59, 59)),
      receipt('r1', 'a', 'Trader', 100.10, DateTime(2026, 10, 2)),
      receipt('r2', 'a', 'Trader', 50.20, DateTime(2026, 10, 2, 23, 59, 59)),
      receipt('r3', 'b', 'Trader', 25.30, DateTime(2026, 10, 2, 12)),
      receipt('r4', 'a', 'Trader', 999, DateTime(2026, 10, 3)),
      {'id': 'pending', 'customerId': 'a', 'amount': 500, 'createdAt': null},
    ], DateTime(2026, 10, 2, 18));
    expect(report.receiptCount, 3);
    expect(report.customers.length, 2);
    expect(report.totalCents, 17560);
    expect(report.customers.firstWhere((c) => c.id == 'a').amountCents, 15030);
    expect(report.customers.firstWhere((c) => c.id == 'a').receipts.map((r) => r['id']), ['r1', 'r2']);
  });
  test('daily report accepts UTC timestamps for the selected local day and empty days', () {
    final local = DateTime(2026, 10, 2, 12);
    final report = summarizeReceiptDay([receipt('r1', 'a', 'Trader', .10, local.toUtc()),
      receipt('r2', 'a', 'Trader', .20, local.toUtc())], local);
    expect(report.totalCents, 30);
    final empty = summarizeReceiptDay([], local);
    expect(empty.totalCents, 0);
    expect(empty.customers, isEmpty);
    expect(empty.receiptCount, 0);
  });
  test('daily report refuses invalid amounts instead of publishing an incorrect total', () {
    for (final amount in [-1, 0, double.nan, double.infinity]) {
      expect(() => summarizeReceiptDay([receipt('bad', 'a', 'Trader', amount, DateTime(2026, 10, 2))],
        DateTime(2026, 10, 2)), throwsStateError);
    }
  });
  test('partial cash sale then linked receipt then return restores debt and cash', () {
    final reversal = returnSettlement({'paid': 40, 'due': 60, 'receiptPaid': 25}, sales: true);
    // Start cash 200 and customer debt 50; invoice and collection precede return.
    expect(200 + 40 + 25 - reversal.cash, 200);
    expect(50 + 60 - 25 - reversal.debt, 50);
  });
  test('fully collected invoice returns all receipts without subtracting debt twice', () {
    final reversal = returnSettlement({'paid': 40, 'due': 60, 'receiptPaid': 60}, sales: true);
    expect(reversal, (cash: 100.0, debt: 0.0));
  });
  test('new purchase return restores cash and supplier opening balance', () {
    final reversal = returnSettlement({'paid': 30, 'due': 70, 'cashPosted': true}, sales: false);
    expect(200 - 30 + reversal.cash, 200);
    expect(50 + 70 - reversal.debt, 50);
  });
  test('legacy purchase cash not posted is never refunded twice', () {
    expect(returnSettlement({'paid': 30, 'due': 70}, sales: false).cash, 0);
    expect(returnSettlement({'paid': 40, 'due': 70, 'cashPaidPosted': 10}, sales: false).cash, 10);
  });
  test('corrupt over-collection aborts settlement', () {
    expect(() => returnSettlement({'paid': 0, 'due': 10, 'receiptPaid': 11}, sales: true), throwsStateError);
  });
  test('general receipts lock only invoices before the receipt; linked receipts stay traceable', () {
    final at = Timestamp.fromDate(DateTime(2026, 10, 2));
    final earlier = Timestamp.fromDate(DateTime(2026, 10, 1));
    expect(unallocatedReceiptAfter({'createdAt': earlier}, {'createdAt': at}), isTrue);
    expect(unallocatedReceiptAfter({'createdAt': at}, {'createdAt': earlier}), isFalse);
    expect(unallocatedReceiptAfter({'createdAt': earlier}, {'createdAt': at, 'invoiceId': 'another'}), isFalse);
  });
}
