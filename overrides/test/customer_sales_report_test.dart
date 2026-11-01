import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeChequeTimeZones);

  test('customer id takes precedence over equal display names', () {
    expect(vibCustomerInvoiceMatches('c1', 'شركة النور',
      {'customerId': 'c1', 'customerName': 'شركة النور'}), isTrue);
    expect(vibCustomerInvoiceMatches('c1', 'شركة النور',
      {'customerId': 'c2', 'customerName': 'شركة النور'}), isFalse);
    expect(vibCustomerInvoiceMatches('c1', 'شركة النور',
      {'customerName': 'شركه النور'}), isFalse);
    expect(vibCustomerInvoiceMatches('c1', 'أحمد علي',
      {'customerName': 'احمد علي'}), isTrue);
    expect(vibCustomerInvoiceMatches('c1', '', {'customerName': ''}), isFalse);
  });

  test('sale lines include grouped and legacy invoices', () {
    final grouped = vibCustomerInvoiceLines({
      'items': [
        {'productName': 'خلاط', 'quantity': 2, 'unitPrice': 100, 'lineTotal': 200},
        {'productName': 'محبس', 'quantity': 1, 'unitPrice': 50, 'lineTotal': 50},
      ],
    });
    expect(grouped.length, 2);
    expect(grouped[1]['productName'], 'محبس');
    final old = vibCustomerInvoiceLines({
      'productName': 'خرطوم', 'quantity': 3, 'unitPrice': 30, 'total': 90,
    });
    expect(old.length, 1);
    expect(old.single['lineTotal'], 90);
  });

  test('report counts invoice, payment and same-period return separately', () {
    final invoice = {
      'id': 's1', 'displayNumber': '1223', 'customerId': 'c1',
      'customerName': 'أحمد', 'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1, 12)),
      'total': 250.0, 'paid': 50.0, 'due': 200.0,
    };
    final returned = {
      'id': 'r1', 'sourceInvoiceId': 's1', 'customerId': 'c1',
      'customerName': 'أحمد', 'createdAt': Timestamp.fromDate(DateTime.utc(2026, 11, 1, 13)),
      'total': 40.0,
    };
    final report = summarizeInvoiceMovement([invoice], DateTime(2026, 11, 1),
      DateTime(2026, 11, 1), type: 'sales', returns: [returned]);
    expect(report.rows.length, 1);
    expect(report.totalCents, 25000);
    expect(report.returnCents, 4000);
    expect(report.netCents, 21000);
    expect(report.dueCents, 20000);
  });
  test('home invoice approval badge counts only visible pending requests', () {
    expect(pendingHomeApprovalCount([
      {'status': 'pending'},
      {'status': 'pending', 'removed': true},
      {'status': 'approved'},
      {'status': 'rejected'},
      {'status': 'pending', 'managerOffline': true},
    ], sales: true), 2);
    expect(pendingHomeApprovalCount([
      {'status': 'approved'},
      {'status': 'rejected'},
    ], sales: true), 0);
  });

  test('home receipt approval badge clears after approval or rejection', () {
    expect(pendingHomeApprovalCount([
      {'status': 'pending', 'amount': 100},
      {'status': 'pending', 'amount': 200},
      {'status': 'approved', 'amount': 300},
      {'status': 'rejected', 'amount': 400},
    ], sales: false), 2);
    expect(pendingHomeApprovalCount([
      {'status': 'approved'},
      {'status': 'rejected'},
    ], sales: false), 0);
  });

}
