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
  test('receipt, approval and cancellation money is always exactly two decimals', () {
    final legacy = <String, dynamic>{
      'amount': 3499.9800000000005,
      'balanceBefore': 27244.889999999992,
      'balanceAfter': 69638.70000000001,
    };
    expect(vibReceiptCurrency(legacy['amount']), '3,499.98 ج.م');
    expect(vibReceiptCurrency(legacy['balanceBefore']), '27,244.89 ج.م');
    expect(vibReceiptCurrency(legacy['balanceAfter']), '69,638.70 ج.م');
    expect(vibReceiptCurrency(100.0), '100.00 ج.م');
    expect(vibReceiptCurrency(0.1 + 0.2), '0.30 ج.م');
    // A formatting operation must never change saved voucher data.
    expect(legacy['amount'], 3499.9800000000005);
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

  group('historic supplier payment numeric registry', () {
    test('loads saved serials and ignores invalid values', () {
      final map = readSupplierPaymentLegacyRegistry({
        'numbers': {'old-1': 8, 'old-2': 9, 'bad': -5, 'other': 'ABC'}
      });
      expect(map, {'old-1': 8, 'old-2': 9});
      expect(readSupplierPaymentLegacyRegistry(null), isEmpty);
    });

    test('legacy numbering only changes the displayed serial, not accounting', () {
      final old = <String,dynamic>{
        'accountType':'suppliers','kind':'payment','amount':17700,
        'balanceBefore':17700,'balanceAfter':0,
        'cashBefore':22000,'cashAfter':4300,
        'accountName':'تاجر اختباري',
        'createdAt':Timestamp.fromDate(DateTime(2026,11,1)),
      };
      final numbered = supplierPaymentWithLegacySerial('abcdEF',old,{'abcdEF':25});
      expect(supplierPaymentVoucherDisplayNumber(numbered),'25');
      expect(numbered['amount'],17700);
      expect(numbered['balanceBefore'],17700);
      expect(numbered['balanceAfter'],0);
      expect(numbered['cashBefore'],22000);
      expect(numbered['cashAfter'],4300);
      expect(old.containsKey('paymentNumber'),isFalse);
      final report = supplierPaymentReportRow('abcdEF',numbered);
      expect(report['receiptNumber'],'25');
      expect(supplierPaymentVoucherDisplayNumber(
        supplierPaymentWithLegacySerial('new',{'paymentNumber':7},{'new':30})),'7');
      expect(supplierPaymentVoucherDisplayNumber(
        supplierPaymentWithLegacySerial('missing',old,{})),'سابق بدون ترقيم');
    });

    test('backfill avoids numbers already assigned to new slips', () {
      final maxNumber = supplierPaymentMaxSerial(
        [{'paymentNumber':1},{'paymentNumber':2},{'kind':'payment'}],
        {'old1':20,'old2':21}, 18);
      expect(maxNumber,21);
      expect(nextSupplierPaymentVoucherNumber(maxNumber),22);
    });

    test('legacy mapped slip prints to both A4 and 80mm PDF', () async {
      final old = <String,dynamic>{
        'accountName':'مورد قديم','amount':125,'balanceBefore':500,
        'balanceAfter':375,'cashBefore':1000,'cashAfter':875,
        'createdAt':Timestamp.fromDate(DateTime(2026,11,1,12))};
      final mapped=supplierPaymentWithLegacySerial('randomLetters',old,{'randomLetters':19});
      for(final thermal in [false,true]) {
        final bytes=await createSupplierPaymentVoucherPdf('randomLetters',mapped,font,thermal:thermal);
        expect(String.fromCharCodes(bytes.take(5)),'%PDF-');
        expect(bytes.length,greaterThan(1000));
      }
    });
  });

  group('supplier payment voucher sequential numbers', () {
    test('first payment is 1 and each saved voucher increments once', () {
      expect(nextSupplierPaymentVoucherNumber(null), 1);
      expect(nextSupplierPaymentVoucherNumber(1), 2);
      expect(nextSupplierPaymentVoucherNumber(18), 19);
      expect(() => nextSupplierPaymentVoucherNumber(-1), throwsStateError);
      expect(() => nextSupplierPaymentVoucherNumber('abc'), throwsStateError);
    });

    test('shows only numeric serial and never random internal document id', () {
      expect(supplierPaymentVoucherDisplayNumber({'paymentNumber': 1}), '1');
      expect(supplierPaymentVoucherDisplayNumber({'paymentNumber': 22}), '22');
      expect(supplierPaymentVoucherDisplayNumber({'paymentNumber': '23'}), '23');
      expect(supplierPaymentVoucherDisplayNumber({'id': 'eLM3qQfkT9'}), 'سابق بدون ترقيم');
      final supplierReport=supplierPaymentReportRow('eLM3qQfkT9', {
        'paymentNumber': 5, 'accountId':'s1','accountName':'تاجر اختباري',
        'amount': 80,'createdAt':Timestamp.fromDate(DateTime(2026,11,15))});
      expect(supplierReport['receiptNumber'],'5');
      expect(receiptDisplayNumber(supplierReport),'5');
    });

    test('supplier payment PDF generates for a numeric voucher on A4 and thermal', () async {
      final payment={'paymentNumber': 14,'accountName':'مورد تجريبي',
        'supplierPhone':'01000000000','amount':175.5,
        'balanceBefore':350,'balanceAfter':174.5,'cashBefore':700,
        'cashAfter':524.5,'actorName':'المدير','note':'سداد دفعة',
        'createdAt':Timestamp.fromDate(DateTime(2026,11,15,10))};
      for(final thermal in [false,true]) {
        final bytes=await createSupplierPaymentVoucherPdf('eLM3qQfkT9', payment, font, thermal: thermal);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
      }
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
