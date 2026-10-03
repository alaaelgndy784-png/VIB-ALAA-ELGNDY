import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vib_sales/product_import_data.dart';

const source = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, dynamic> row(String code, String name, String quantity, {String cost = '10.05', String sale = '11.06'}) =>
  {'code': code, 'name': name, 'quantity': quantity, 'purchasePrice': cost, 'price': sale};
String payload(List<Map<String, dynamic>> rows) => jsonEncode({'schema': 'VIB Products Review', 'version': 1, 'sourceSha256': source, 'markupPercent': 10, 'products': rows});

void main() {
  test('Zero, negative and positive counts and half-up 10 percent survive parsing', () {
    final file = ProductImportFile.parse(payload([row('a', 'منتج صفر', '0.00'), row('b', 'منتج سالب', '-7'), row('c', 'منتج موجب', '12')]));
    expect(file.rows.map((r) => r.quantity), [0, -7, 12]);
    expect(file.rows.first.purchaseCents, 1005);
    expect(file.rows.first.saleCents, 1106);
    expect(ProductImportFile.parse(payload([row('d', 'منتج بلا تكلفة', '0', cost: '0.00', sale: '0.00')])).rows.single.saleCents, 0);
  });
  test('Reject fractional quantities, nonfinite prices, wrong markup and duplicate codes before writes', () {
    for (final invalid in [
      [row('a', 'أ', '11.92')], [row('a', 'أ', '1', cost: 'NaN')],
      [row('a', 'أ', '1', sale: '11.05')], [row('a', 'أ', '1'), row('a', 'ب', '2')],
      [row('a', '  نفس الاسم  ', '1'), row('b', 'نفس الاسم', '2')],
      [row('a', 'أ', '1000001')],
    ]) { expect(() => ProductImportFile.parse(payload(invalid)), throwsFormatException); }
    final pending = jsonDecode(payload([row('a', 'أ', '0')])) as Map<String, dynamic>;
    pending['pendingQuantityReview'] = {'quantity': '11.92'};
    expect(() => ProductImportFile.parse(jsonEncode(pending)), throwsFormatException);
  });
  test('Match the existing exact name and keep its id; new codes get stable ids', () {
    final f = ProductImportFile.parse(payload([row('a', 'صنف قديم', '-3'), row('b', 'صنف جديد', '0')]));
    final products = {'original': <String, dynamic>{'name': 'صنف  قديم', 'active': true, 'price': 8.0, 'purchasePrice': 7.0, 'category': 'النحاسات'}};
    final stock = {'main_original': <String, dynamic>{'branchId': 'main', 'productId': 'original', 'quantity': 5, 'lastSaleId': 'sale-existing'}};
    final p = planProductImport(f, products, stock, {});
    expect(p.map((t) => t.productId), ['original', 'import_b']);
    expect(p.first.beforeQuantity, 5);
    expect(p.first.row.quantity - p.first.beforeQuantity, -8);
    expect(p.first.validateLive(null, products['original'], stock['main_original']), isTrue);
    expect(products['original']!['category'], 'النحاسات');
  });
  test('Reject conflicting code/name mappings, archived items and duplicate names', () {
    final f = ProductImportFile.parse(payload([row('a', 'صنف', '0')]));
    for (final products in [
      {'old': <String, dynamic>{'name': 'صنف', 'active': false}},
      {'old': <String, dynamic>{'name': 'صنف', 'externalCode': 'b'}},
      {'one': <String, dynamic>{'name': 'صنف'}, 'two': <String, dynamic>{'name': 'صنف'}},
      {'one': <String, dynamic>{'name': 'اسم مختلف', 'externalCode': 'a'}},
    ]) { expect(() => planProductImport(f, products, {}, {}), throwsStateError); }
  });
  test('Concurrent sales or price edits after preview block stock replacement', () {
    final f = ProductImportFile.parse(payload([row('a', 'صنف', '12')]));
    final oldProduct = <String, dynamic>{'name': 'صنف', 'price': 20.0};
    final oldStock = <String, dynamic>{'branchId': 'main', 'productId': 'id', 'quantity': 10};
    final t = planProductImport(f, {'id': oldProduct}, {'main_id': oldStock}, {}).single;
    expect(() => t.validateLive(null, oldProduct, {...oldStock, 'quantity': 9}), throwsStateError);
    expect(() => t.validateLive(null, {...oldProduct, 'price': 25.0}, oldStock), throwsStateError);
    final newTarget = planProductImport(f, {}, {}, {}).single;
    expect(() => newTarget.validateLive(null, {'name': 'صنف'}, null), throwsStateError);
  });
  test('Retry after interrupted import skips posted rows without overwriting subsequent sales', () {
    final f = ProductImportFile.parse(payload([row('a', 'صنف أول', '12'), row('b', 'صنف ثاني', '-2')]));
    final initial = planProductImport(f, {}, {}, {});
    final marker = <String, dynamic>{'productId': initial.first.productId, 'requestKey': initial.first.requestKey};
    final product = <String, dynamic>{'name': 'صنف أول', 'externalCode': 'a', 'active': true};
    final stock = <String, dynamic>{'branchId': 'main', 'productId': initial.first.productId, 'quantity': 9, 'lastSaleId': 'later-sale'};
    final resumed = planProductImport(f, {initial.first.productId: product}, {'main_${initial.first.productId}': stock}, {initial.first.markerId: marker});
    expect(resumed.first.alreadyApplied, isTrue);
    expect(resumed.first.validateLive(marker, product, stock), isFalse);
    expect(resumed.last.alreadyApplied, isFalse);
    expect(resumed.last.validateLive(null, null, null), isTrue);
    expect(() => resumed.first.validateLive({...marker, 'requestKey': 'different'}, product, stock), throwsStateError);
    expect(() => planProductImport(ProductImportFile.parse(payload([row('a', 'صنف أول', '0')])), {initial.first.productId: product}, {'main_${initial.first.productId}': stock}, {initial.first.markerId: marker}), throwsStateError);
  });
}
