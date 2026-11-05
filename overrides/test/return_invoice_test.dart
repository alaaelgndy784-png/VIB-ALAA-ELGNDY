import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sales return invoice number and balances are kept stable', () {
    final record = VibReturnInvoiceEntry('sales', 'sR456789012345', {
      'total': 1200.0,
      'cashRefund': 0.0,
      'debtReduction': 1200.0,
      'balanceBefore': 5000.0,
      'balanceAfter': 3800.0,
      'customerName': 'تاجر تجربة',
    });
    expect(record.number, 'MR-SR45678901');
    expect(record.party, 'تاجر تجربة');
    expect(vibReturnSettlement(record).debt, 1200);
    expect(vibReturnSettlement(record).refunded, 0);
    expect(record.data['balanceAfter'], 3800);
  });

  test('supplier return separates refunded cash from reduced payable', () {
    final record = VibReturnInvoiceEntry('purchases', 'pr00900877abc', {
      'total': 900.0,
      'cashRefund': 300.0,
      'debtReduction': 600.0,
      'balanceBefore': 2500.0,
      'balanceAfter': 1900.0,
      'supplierName': 'مورد تجربة',
    });
    expect(record.number, startsWith('PR-'));
    expect(record.party, 'مورد تجربة');
    expect(vibReturnSettlement(record).refunded, 300);
    expect(vibReturnSettlement(record).debt, 600);
  });

  test('legacy full return can be read without adding a fictitious balance', () {
    final record = VibReturnInvoiceEntry('sales', 'legacy01', {
      'total': 150.0, 'paid': 50.0, 'due': 100.0,
      'customerName': 'عميل سابق',
    });
    final settlement = vibReturnSettlement(record);
    expect(settlement.refunded, 50);
    expect(settlement.debt, 100);
    expect(record.data.containsKey('balanceAfter'), false);
  });

  test('negative supplier balance is credit owed by supplier', () {
    expect(accountBalanceLabel(-250, supplier: true), contains('لك عند المورد'));
    expect(accountBalanceLabel(3800, supplier: false), contains('المتبقي على العميل'));
  });
}
