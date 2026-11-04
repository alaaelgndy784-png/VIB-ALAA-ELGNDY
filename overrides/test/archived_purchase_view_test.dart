import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manager can review archived purchase invoice without reactivating it', () {
    expect(archivedPurchaseReviewAllowed('purchases',
      activeVisible: false, managerApp: true), isTrue);
    // Active invoices keep their normal action menus.
    expect(archivedPurchaseReviewAllowed('purchases',
      activeVisible: true, managerApp: true), isFalse);
  });

  test('archived invoices remain blocked on staff and for sales', () {
    expect(archivedPurchaseReviewAllowed('purchases',
      activeVisible: false, managerApp: false), isFalse);
    expect(archivedPurchaseReviewAllowed('sales',
      activeVisible: false, managerApp: true), isFalse);
  });
}
