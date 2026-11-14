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
  group('vibVoucherMoney', () {
    test('formats old floating-point balances to exactly two piastres', () {
      expect(vibVoucherMoney(27244.889999999992), '27,244.89');
      expect(vibVoucherMoney(69638.70000000001), '69,638.70');
      expect(vibVoucherMoney(10713.27999999999), '10,713.28');
      expect(vibVoucherMoney(4000), '4,000.00');
      expect(vibVoucherMoney(0.1 + 0.2), '0.30');
    });
    test('handles missing, invalid and string values without corrupting data', () {
      expect(vibVoucherMoney(null), '0.00');
      expect(vibVoucherMoney(null, missing: 'غير مسجل'), 'غير مسجل');
      expect(vibVoucherMoney('1250.5'), '1,250.50');
      expect(vibVoucherMoney(double.nan, missing: '…'), '…');
    });
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

  group('saleReceiptBlocksEdit', () {
    final invoice={'id':'sale-1','createdAt':Timestamp.fromDate(DateTime(2026,10,1))};
    final receiptDate=Timestamp.fromDate(DateTime(2026,10,2));
    test('an active receipt linked to this invoice blocks editing', () {
      expect(saleReceiptBlocksEdit(invoice,'r1',{'invoiceId':'sale-1','createdAt':receiptDate}),isTrue);
    });
    test('a cancelled linked receipt no longer blocks editing', () {
      expect(saleReceiptBlocksEdit(invoice,'r1',{'invoiceId':'sale-1','createdAt':receiptDate},cancelledReceiptIds:{'r1'}),isFalse);
    });
    test('a cancelled general receipt no longer blocks editing', () {
      expect(saleReceiptBlocksEdit(invoice,'r2',{'createdAt':receiptDate},cancelledReceiptIds:{'r2'}),isFalse);
    });
    test('an active general receipt after the invoice still blocks editing', () {
      expect(saleReceiptBlocksEdit(invoice,'r3',{'createdAt':receiptDate}),isTrue);
    });
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
