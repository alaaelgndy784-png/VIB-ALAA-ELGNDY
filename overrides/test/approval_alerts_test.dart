import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('historical requests and offline snapshots are silent', () {
    final alerts = ApprovalAlertTracker();
    const old = <String, Map<String, dynamic>>{
      'old': {'status': 'pending', 'customerName': 'A'},
    };
    expect(alerts.accept('sales', old, cached: true), isEmpty);
    expect(alerts.accept('sales', old), isEmpty);
    expect(alerts.accept('sales', old), isEmpty);
    const later = <String, Map<String, dynamic>>{
      'old': {'status': 'pending'},
      'new': {'status': 'pending'},
    };
    expect(alerts.accept('sales', later, pending: true), isEmpty);
    expect(alerts.accept('sales', later), ['new']);
    expect(alerts.accept('sales', later), isEmpty);
  });

  test('sale and receipt approvals are independent', () {
    final alerts = ApprovalAlertTracker();
    expect(alerts.accept('sales', {}), isEmpty);
    expect(alerts.accept('receipts', {}), isEmpty);
    expect(alerts.accept('sales', {
      'sale-one': {'status': 'pending'},
      'sale-old-draft': {'status': 'rejected'},
    }), ['sale-one']);
    expect(alerts.accept('receipts', {
      'receipt-one': {'status': 'pending'},
    }), ['receipt-one']);
    expect(alerts.accept('sales', {
      'sale-one': {'status': 'approved'},
    }), isEmpty);
    expect(alerts.accept('sales', {
      'sale-one': {'status': 'pending'},
    }), ['sale-one']);
  });

  test('hidden employee sales and finished vouchers do not notify', () {
    final alerts = ApprovalAlertTracker();
    alerts.accept('sales', {});
    alerts.accept('receipts', {});
    expect(alerts.accept('sales', {
      'hidden': {'status': 'pending', 'removed': true},
    }), isEmpty);
    expect(alerts.accept('receipts', {
      'approved': {'status': 'approved'},
      'rejected': {'status': 'rejected'},
    }), isEmpty);
  });
}
