import 'package:flutter_test/flutter_test.dart';
import 'package:vib_sales/sale_price_floor.dart';

void main() {
  test('does not permit a sale below the current unit cost', () {
    final message = belowCostSaleMessage(
      productName: 'شطاف ABS', unitPrice: 134.99, unitCost: 135);
    expect(message, isNotNull);
    expect(message, contains('شطاف ABS'));
    expect(message, contains('135.00'));
  });

  test('permits a sale exactly at cost or above', () {
    expect(belowCostSaleMessage(productName: 'صنف', unitPrice: 135, unitCost: 135), isNull);
    expect(belowCostSaleMessage(productName: 'صنف', unitPrice: 150, unitCost: 135), isNull);
  });

  test('rejects discount-adjusted final price below cost', () {
    // Base catalog price 150 and 20% discount: actual price 120.
    expect(belowCostSaleMessage(productName: 'صنف', unitPrice: 120, unitCost: 125), isNotNull);
  });

  test('rejects missing or invalid costs rather than permitting unchecked sale', () {
    expect(belowCostSaleMessage(productName: 'صنف', unitPrice: 10, unitCost: null), isNotNull);
    expect(belowCostSaleMessage(productName: 'صنف', unitPrice: 10, unitCost: -1), isNotNull);
    expect(belowCostSaleMessage(productName: 'صنف', unitPrice: 10, unitCost: double.nan), isNotNull);
  });
}
