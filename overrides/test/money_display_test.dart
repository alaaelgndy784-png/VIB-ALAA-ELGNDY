import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  test('invoice money display rounds binary floating point tails to two piastres', () {
    expect(vibVoucherMoney(3499.9800000000005), '3,499.98');
    expect(vibVoucherMoney(8700.0), '8,700.00');
    expect(vibVoucherMoney(12199.9800000000005), '12,199.98');
    expect(vibVoucherMoney(0.0), '0.00');
    expect(vibVoucherMoney(-34.125), '-34.13');
    expect(vibVoucherMoney(null), '0.00');
    expect(vibVoucherMoney(3499.9800000000005, missing:'—'), '3,499.98');
  });
}
