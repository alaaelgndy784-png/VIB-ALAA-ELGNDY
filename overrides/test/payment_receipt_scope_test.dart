import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeChequeTimeZones);

  final from = DateTime(2026, 9, 1);
  final to = DateTime(2026, 11, 2);

  Map<String, dynamic> payment(String id, String customerId, String name,
      num amount, int day, {String note = '', String method = 'نقدي'}) => {
    'id': id,
    'customerId': customerId,
    'customerName': name,
    'amount': amount,
    'receiptNumber': 'VIB-RC-' + id,
    'receiptDate': Timestamp.fromDate(
        movementReportBoundary(DateTime(2026, 10, day))
            .add(const Duration(hours: 13))),
    'createdAt': Timestamp.fromDate(
        movementReportBoundary(DateTime(2026, 10, day))
            .add(const Duration(hours: 14))),
    'note': note,
    'paymentMethod': method,
  };

  test('one selected client excludes another with same name on same dates', () {
    final receipts = [
      payment('1', 'a', 'معرض الجزار', 15000, 5),
      payment('2', 'a', 'معرض الجزار', 1484.44, 9),
      payment('3', 'a', 'معرض الجزار', 10000, 12),
      payment('4', 'a', 'معرض الجزار', 5000, 15),
      payment('5', 'a', 'معرض الجزار', 8000, 20),
      payment('6', 'a', 'معرض الجزار', 10000, 22),
      payment('7', 'a', 'معرض الجزار', 15451.30, 27),
      payment('foreign', 'b', 'معرض الجزار', 90000, 27),
    ];
    final whole = summarizeReceiptPeriod(receipts, from, to);
    final selectA = vibSelectReceiptParty(whole, '', 'customer:a');
    expect(whole.receiptCount, 8);
    expect(selectA.customers, hasLength(1));
    expect(selectA.customers.single.id, 'a');
    expect(selectA.receiptCount, 7);
    expect(selectA.totalCents, 6493574);
    expect(vibSelectReceiptParty(whole, '', 'customer:b').totalCents, 9000000);
    expect(vibSelectReceiptParty(whole, '', 'customer:missing').receiptCount, 0);
    expect(vibReceiptReportFingerprint(selectA),
      isNot(contains('foreign')));
  });

  test('free-text search matches visible customers, selected ID wins', () {
    final data = [
      payment('x1', 'x', 'معرض الجزار بنها', 10, 1),
      payment('y1', 'y', 'معرض الجزار فرع آخر', 20, 1),
      payment('z1', 'z', 'الروضة', 40, 1),
    ];
    final all = summarizeReceiptPeriod(data, from, to);
    expect(vibSelectReceiptParty(all, 'الجزار', null).receiptCount, 2);
    final precise = vibSelectReceiptParty(all, 'الجزار', 'customer:y');
    expect(precise.receiptCount, 1);
    expect(precise.totalCents, 2000);
    expect(precise.customers.single.name, 'معرض الجزار فرع آخر');
  });

  test('print fingerprint detects a different amount or newly created receipt', () {
    final old = vibSelectReceiptParty(
      summarizeReceiptPeriod([
        payment('r1', 'a', 'عميل اختباري', 123.45, 1, note: 'تحويل'),
      ], from, to), '', 'customer:a');
    final same = vibSelectReceiptParty(
      summarizeReceiptPeriod([
        payment('r1', 'a', 'عميل اختباري', 123.45, 1, note: 'تحويل'),
      ], from, to), '', 'customer:a');
    final changed = vibSelectReceiptParty(
      summarizeReceiptPeriod([
        payment('r1', 'a', 'عميل اختباري', 123.45, 1, note: 'تم التعديل'),
      ], from, to), '', 'customer:a');
    final appended = vibSelectReceiptParty(
      summarizeReceiptPeriod([
        payment('r1', 'a', 'عميل اختباري', 123.45, 1, note: 'تحويل'),
        payment('r2', 'a', 'عميل اختباري', 60, 2),
      ], from, to), '', 'customer:a');
    expect(vibReceiptReportFingerprint(old), vibReceiptReportFingerprint(same));
    expect(vibReceiptReportFingerprint(old),
      isNot(vibReceiptReportFingerprint(changed)));
    expect(vibReceiptReportFingerprint(old),
      isNot(vibReceiptReportFingerprint(appended)));
  });

  test('detailed PDF previews use only seven selected receipt rows', () async {
    final rows = [
      payment('1', 'a', 'معرض الجزار', 15000, 5, note: 'تحويل إنستا باي'),
      payment('2', 'a', 'معرض الجزار', 1484.44, 9, note: 'دفعة نقدية'),
      payment('3', 'a', 'معرض الجزار', 10000, 12),
      payment('4', 'a', 'معرض الجزار', 5000, 15),
      payment('5', 'a', 'معرض الجزار', 8000, 20),
      payment('6', 'a', 'معرض الجزار', 10000, 22),
      payment('7', 'a', 'معرض الجزار', 15451.30, 27),
      payment('foreign', 'b', 'عميل آخر', 90000, 27),
    ];
    final report = vibSelectReceiptParty(
      summarizeReceiptPeriod(rows, from, to), '', 'customer:a');
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    Directory('dist').createSync(recursive: true);
    for (final thermal in [false, true]) {
      final bytes = await createCustomerPaymentReportPdf(from, report,
        font, owner: true, to: to, thermal: thermal);
      expect(bytes.sublist(0, 4), [37, 80, 68, 70]);
      expect(bytes.length, greaterThan(2000));
      final filename = thermal
          ? 'dist/VIB-SELECTED-CUSTOMER-REPAYMENTS-80MM.pdf'
          : 'dist/VIB-SELECTED-CUSTOMER-REPAYMENTS-A4.pdf';
      File(filename).writeAsBytesSync(bytes);
    }
  });
}
