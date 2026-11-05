import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> line(String group, String supplier, String product, {
    double total = 100, double paid = 40, int qty = 1,
  }) => {
    'scanGroupId': group,
    'supplierId': supplier,
    'supplierName': 'مورد اختبار',
    'invoiceNumber': 'INV-011',
    'productId': product,
    'productName': product,
    'quantity': qty,
    'unitCost': total / qty,
    'total': total,
    'paid': paid,
    'due': total - paid,
    'status': 'completed',
  };

  test('old camera purchase lines join by scanGroupId without losing totals', () {
    final rows = [
      VibPurchaseRow('a', line('scan-1', 'supplier-1', 'خلاط', total: 120, paid: 100)),
      VibPurchaseRow('b', line('scan-1', 'supplier-1', 'محبس', total: 330, paid: 50, qty: 3)),
    ];
    final groups = vibGroupLegacyPurchases(rows);
    expect(groups, hasLength(1));
    expect(groups.single.grouped, isTrue);
    expect(groups.single.data['items'], hasLength(2));
    expect(groups.single.data['total'], 450);
    expect(groups.single.data['paid'], 150);
    expect(groups.single.data['due'], 300);
    expect(groups.single.data['internalNumber'], isNull);
    expect(groups.single.sources.map((r) => r.id), ['a', 'b']);
    expect(rows.first.data['items'], isNull); // no changes to source docs
  });

  test('same supplier and reference but separate scanned batches stay separate', () {
    final groups = vibGroupLegacyPurchases([
      VibPurchaseRow('a', line('scan-1', 'supplier-1', 'خلاط')),
      VibPurchaseRow('b', line('scan-2', 'supplier-1', 'محبس')),
    ]);
    expect(groups, hasLength(2));
  });

  test('different suppliers never merge even if scan id repeats', () {
    final groups = vibGroupLegacyPurchases([
      VibPurchaseRow('a', line('scan-1', 'supplier-1', 'خلاط')),
      VibPurchaseRow('b', line('scan-1', 'supplier-2', 'محبس')),
    ]);
    expect(groups, hasLength(2));
  });

  test('modern complete grouped invoice and unlinked legacy invoice stay separate', () {
    final modern = line('scan-1', 'supplier-1', 'خلاط')
      ..['items'] = [{'productName': 'خلاط', 'quantity': 1, 'unitCost': 100, 'lineTotal': 100}];
    final unlinked = line('', 'supplier-1', 'محبس');
    final groups = vibGroupLegacyPurchases([
      VibPurchaseRow('a', modern),
      VibPurchaseRow('b', line('scan-1', 'supplier-1', 'خرطوم')),
      VibPurchaseRow('c', unlinked),
    ]);
    expect(groups, hasLength(3));
  });

  test('incomplete historical payment disables invented settlement PDF', () {
    final incomplete = line('scan-1', 'supplier-1', 'خلاط')
      ..remove('paid')..remove('due');
    final group = vibGroupLegacyPurchases([
      VibPurchaseRow('a', incomplete),
      VibPurchaseRow('b', line('scan-1', 'supplier-1', 'محبس')),
    ]).single;
    expect(group.completeSettlement, isFalse);
    expect(group.data.containsKey('due'), isFalse);
    expect(group.data.containsKey('paid'), isFalse);
    expect(group.data['total'], 200);
  });
}
