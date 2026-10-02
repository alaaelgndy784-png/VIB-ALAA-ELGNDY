import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final brand = <String, dynamic>{'companyName': 'VIB للتجارة والتوزيع', 'address': 'عنوان الشركة - مثال توضيحي',
    'phone': '01000000000', 'phone2': '01100000000', 'invoiceFooter': 'شكراً لتعاملكم معنا - نموذج توضيحي للطباعة'};
  final rows = [
    {'productName': 'حنفية غسالة تركي', 'quantity': 2, 'unitPrice': 175, 'lineTotal': 350},
    {'productName': 'حنفية نصف بوصة الحياة', 'quantity': 3, 'unitPrice': 195, 'lineTotal': 585},
    {'productName': 'طاسة دش الحياة مقاس 20 × 20', 'quantity': 1, 'unitPrice': 325, 'lineTotal': 325},
  ];
  for (final paper in ['a4','80']) {
    for (final long in [false,true]) {
      test('$paper ${long ? 'long invoice pagination' : 'brand and totals'}', () async {
        final items = long ? List.generate(50, (i) => {...rows[i % 3], 'productName': '${rows[i % 3]['productName']} - صنف إضافي رقم ${i + 1}'}) : rows;
        final total = items.fold<double>(0, (sum, row) => sum + (row['lineTotal'] as num).toDouble());
        final bytes = await createInvoicePdf('sales', 'VIB-DEMO-2026', {'items': items, 'total': total, 'paid': 500,
          'due': total - 500, 'customerName': 'عميل تجريبي', 'customerPhone': '01200000000',
          'customerPreviousBalance': 200, 'customerBalanceAfter': total - 300,
          'status': 'completed', 'createdAt': null}, paperChoice: paper, settingsOverride: brand);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        expect(bytes.length, greaterThan(1000));
        Directory('dist').createSync(recursive: true);
        File('dist/VIB-INVOICE-${paper.toUpperCase()}${long ? '-LONG' : ''}.pdf').writeAsBytesSync(bytes);
      });
    }
  }
}
