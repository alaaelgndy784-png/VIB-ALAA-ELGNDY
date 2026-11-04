import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sales, purchases, receipts and profit use unambiguous symbols', () {
    final icons = <IconData>[
      dashboardSalesIcon,
      dashboardPurchasesIcon,
      dashboardPaymentsIcon,
      dashboardProfitsIcon,
    ];
    expect(icons.toSet().length, 4);
    expect(dashboardSalesIcon, Icons.point_of_sale_rounded);
    expect(dashboardPurchasesIcon, Icons.shopping_cart_rounded);
    expect(dashboardPaymentsIcon, Icons.payments_rounded);
    expect(dashboardProfitsIcon, Icons.trending_up_rounded);
  });

  testWidgets('dashboard financial symbol appears in its own outlined tile',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(
        child: vibDashboardMetricIcon(dashboardSalesIcon, Colors.green),
      )),
    ));
    expect(find.byIcon(Icons.point_of_sale_rounded), findsOneWidget);
    final widgets = tester.widgetList<Container>(find.byType(Container));
    expect(widgets.any((container) =>
      container.constraints?.maxWidth == 34 ||
      container.decoration is BoxDecoration), isTrue);
  });
}
