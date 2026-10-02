import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../lib/main.dart';

void main() {
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
