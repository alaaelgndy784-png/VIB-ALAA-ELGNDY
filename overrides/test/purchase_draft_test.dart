import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/purchase_draft.dart';

Map<String, dynamic> example(int n) => {
  'version': 1, 'kind': 'purchase', 'id': 'stablePurchaseDocumentId123',
  'supplierId': 'supplierA', 'credit': true, 'paid': '3000',
  'invoice': 'supplier-12', 'note': 'طلبية كبيرة', 'markup': '2.5',
  'items': [for (var i = 0; i < n; i++)
    {'id': 'product'+i.toString(), 'quantity': '12', 'cost': '173.55',
     'sellingPrice': '211.00', 'sellingPriceEdited': true,
     'discountPercent': 0.0, 'baseCost': 173.55}],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('50 items and the original ID survive restart and retry', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = PurchaseDraftStore(prefs, userId: 'manager', owner: true);
    final save = PurchaseDraftAutosave(store);
    await save.save(example(50));
    await save.stop(clear: false);
    final restored = store.read()!;
    expect(restored['id'], 'stablePurchaseDocumentId123');
    expect(restored['paid'], '3000');
    expect(restored['supplierId'], 'supplierA');
    expect(restored['markup'], '2.5');
    expect((restored['items'] as List).length, 50);
    expect((restored['items'] as List).last['cost'], '173.55');
    expect((restored['items'] as List).last['sellingPrice'], '211.00');
    expect((restored['items'] as List).last['sellingPriceEdited'], isTrue);
    final retry = PurchaseDraftAutosave(store);
    await retry.save(restored);
    expect(store.read()!['id'], restored['id']);
    await retry.stop(clear: true);
    expect(store.read(), isNull);
  });
  test('manager and staff drafts have separate keys', () async {
    final prefs = await SharedPreferences.getInstance();
    final a = PurchaseDraftStore(prefs, userId: 'same', owner: true);
    final b = PurchaseDraftStore(prefs, userId: 'same', owner: false);
    await a.persist(jsonEncode(example(1)));
    expect(a.key, isNot(b.key));
    expect(a.read(), isNotNull);
    expect(b.read(), isNull);
  });
  test('corrupted and oversized drafts are rejected', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = PurchaseDraftStore(prefs, userId: 'bad', owner: true);
    await store.persist('invalid json');
    expect(store.read(), isNull);
    await store.persist(jsonEncode(example(1)..['id'] = 'bad/id'));
    expect(store.read(), isNull);
    await store.persist(jsonEncode(example(51)));
    expect(store.read(), isNull);
  });
  test('untouched empty invoice creates no draft', () {
    final draft = example(0);
    draft.addAll({'supplierId':'', 'invoice':'', 'note':'', 'markup':''});
    expect(PurchaseDraftStore.hasInput(draft), isFalse);
    expect(PurchaseDraftStore.hasInput(example(1)), isTrue);
  });
}
