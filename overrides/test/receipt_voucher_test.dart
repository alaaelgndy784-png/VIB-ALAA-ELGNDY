import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late pw.Font font;
  setUpAll(() async {
    font=pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  });
  group('parseReceiptAmount', () {
    test('parses Arabic digits and Arabic decimal separator', () {
      expect(parseReceiptAmount('١٢٣٫٥٠'), 123.5);
    });

    test('parses Arabic thousands and decimal separators', () {
      expect(parseReceiptAmount('١٬٢٣٤٫٥٠'), 1234.5);
    });

    test('rejects invalid and non-finite values', () {
      expect(parseReceiptAmount('غير صحيح'), isNull);
      expect(parseReceiptAmount('NaN'), isNull);
      expect(parseReceiptAmount('Infinity'), isNull);
    });
  });

  test('customer payment report filters to the selected customer', () {
    final rows=[
      {'customerId':'c1','amount':25},
      {'customerId':'c2','amount':50},
      {'customerId':'c1','amount':10},
    ];
    expect(receiptRowsForCustomer(rows,'c1').map((r)=>r['amount']),[25,10]);
  });

  test('legacy receipt numbers are shown as readable references', () {
    expect(receiptDisplayNumber({'id':'abcdef123456'}),'VIB-RC--ABCDEF');
  });

  test('standalone receipt PDF contains the customer, amount and receipt reference',() async {
    final pdf=await createReceiptVoucherPdf('RC-2026-001',{
      'customerName':'عميل الاختبار','customerPhone':'01000000000','amount':125.5,
      'balanceBefore':500,'balanceAfter':374.5,'actorName':'موظف','note':'سداد مستقل',
      'receiptDate':Timestamp.fromDate(DateTime(2026,10,7,12)),'paymentMethod':'تحويل إنستا باي',
    },font);
    expect(pdf.length,greaterThan(1000));
    expect(String.fromCharCodes(pdf.take(5)),'%PDF-');
  });
}
