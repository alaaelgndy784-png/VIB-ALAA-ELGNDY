import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('grouped purchase and sale invoices are searched at line level', () {
    final invoice = <String, dynamic>{
      'items': [
        {'productId': 'p1', 'productName': 'خلاط مطبخ',
          'quantity': 2, 'unitCost': 150, 'lineTotal': 300},
        {'productId': 'p2', 'productName': 'خرطوم شطاف',
          'quantity': 3, 'unitCost': 40, 'lineTotal': 120},
      ],
    };
    final matched = vibMatchingInvoiceProductLines(invoice,
      keyword: 'خرطوم', selectedProductId: 'p2',
      selectedProductName: 'خرطوم شطاف');
    expect(matched.length, 1);
    expect(matched.single['quantity'], 3);
    expect(vibMatchingInvoiceProductLines(invoice, keyword: 'صنف غير موجود'), isEmpty);
  });

  test('product id overrides similar names to avoid false invoices', () {
    final line = {'productId': 'new-one', 'productName': 'محبس 1 بوصة'};
    expect(vibInvoiceLineMatchesProduct(line, keyword: 'محبس',
      selectedProductId: 'old-one', selectedProductName: 'محبس 1 بوصة'), isFalse);
    expect(vibInvoiceLineMatchesProduct(line, keyword: 'محبس',
      selectedProductId: 'new-one', selectedProductName: 'اسم تم تغييره'), isTrue);
  });

  test('legacy name-only invoices match exactly when product selected', () {
    final invoice = {'items': [
      {'productName': 'مُحبس ١ بوصة', 'quantity': 2},
      {'productName': 'محبس 2 بوصة', 'quantity': 6},
    ]};
    expect(vibMatchingInvoiceProductLines(invoice, keyword: 'محبس',
      selectedProductId: 'p1', selectedProductName: 'محبس 1 بوصة'), hasLength(1));
  });

  test('legacy single-line invoice can be found without product record', () {
    final old = {'productName': 'خرطوم قديم', 'productId': 'deleted-id',
      'quantity': 5, 'unitPrice': 22, 'total': 110};
    final matched = vibMatchingInvoiceProductLines(old, keyword: 'خرطوم');
    expect(matched, hasLength(1));
    expect(matched.single['lineTotal'], 110);
    expect(vibInvoiceProductLines({'total': 500}), isEmpty);
  });

  test('amounts and quantities use values saved with invoice', () {
    const line = {'quantity': 2, 'unitCost': 155, 'lineTotal': 310};
    const old = {'quantity': '3', 'unitPrice': '15.5'};
    expect(vibInvoiceLineNumber(line['lineTotal']), 310);
    expect(vibInvoiceLineNumber(old['quantity']), 3);
    expect(vibInvoiceLineNumber('invalid'), 0);
  });
}
