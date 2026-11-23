import 'package:flutter_test/flutter_test.dart';
import 'package:vib_sales/main.dart';

void main() {
  group('Employee visit alert tracker', () {
    test('does not alert for historic server snapshot', () {
      final tracker = EmployeeVisitAlertTracker();
      expect(tracker.accept(['old-1', 'old-2']), isEmpty);
      expect(tracker.accept(['new-1', 'old-1', 'old-2']), ['new-1']);
    });

    test('ignores cached and pending snapshots', () {
      final tracker = EmployeeVisitAlertTracker();
      expect(tracker.accept(['old'], cached: true), isEmpty);
      expect(tracker.accept(['old']), isEmpty);
      expect(tracker.accept(['old', 'local'], pending: true), isEmpty);
      expect(tracker.accept(['old', 'confirmed']), ['confirmed']);
    });

    test('does not alert twice for the same visit', () {
      final tracker = EmployeeVisitAlertTracker();
      tracker.accept(['old']);
      expect(tracker.accept(['old', 'new']), ['new']);
      expect(tracker.accept(['old', 'new']), isEmpty);
    });
  });
}
