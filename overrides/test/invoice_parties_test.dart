import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  testWidgets('customer choices show right-hand numbering, adjacent name and green debt on a small phone', (tester) async {
    tester.view.physicalSize = const Size(360, 640); tester.view.devicePixelRatio = 1;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    var selected = false;
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(360, 640), viewInsets: EdgeInsets.only(bottom: 280)),
      child: Scaffold(body: Builder(builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        title: const Text('اختيار عميل مسجل'),
        content: SizedBox(width: 500, height: invoiceCustomerChoicesHeight(context), child: ListView(children: [
          InvoiceCustomerChoiceRow(number: 1, name: 'الحاج أحمد محمود بورسعيد', balance: 82502.7, onTap: () => selected = true),
          InvoiceCustomerChoiceRow(number: 2, name: 'الحاج أحمد الجمل', balance: 9, onTap: () {}),
        ])),
        actions: [TextButton(onPressed: () {}, child: const Text('إلغاء'))],
      ))),
    )));
    expect(tester.takeException(), isNull);
    final number = tester.getRect(find.text('1.'));
    final name = tester.getRect(find.text('الحاج أحمد محمود بورسعيد'));
    final debt = tester.getRect(find.text('82502.70 ج.م'));
    expect(number.left, greaterThan(name.right));
    expect(name.left, greaterThan(debt.right));
    expect(number.center.dy, closeTo(name.center.dy, 1));
    expect(debt.center.dy, closeTo(name.center.dy, 1));
    expect(tester.widget<Text>(find.text('82502.70 ج.م')).style!.color, Colors.greenAccent);
    await tester.tap(find.text('الحاج أحمد محمود بورسعيد')); await tester.pump();
    expect(selected, isTrue);
  });
  for (final supplier in [false, true]) {
    testWidgets('create ${supplier ? 'supplier' : 'customer'} before invoice save preserves draft and selects returned ID', (tester) async {
      Map<String, dynamic>? saved;
      String? selected;
      final quantity = TextEditingController(text: '24');
      final paid = TextEditingController(text: '500');
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => Column(children: [
        TextField(controller: quantity), TextField(controller: paid),
        TextButton(onPressed: () async {
          selected = await showDialog<String>(context: context, builder: (_) => AccountEntryDialog(
            supplier: supplier, onSave: (fields) async { saved = fields; return 'new-account'; }));
        }, child: const Text('إضافة حساب')),
      ])))));
      await tester.tap(find.text('إضافة حساب')); await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ الحساب')); await tester.pump();
      expect(find.text('اكتب الاسم'), findsOneWidget); expect(saved, isNull);
      await tester.enterText(find.widgetWithText(TextFormField, 'الاسم *'), '  تاجر جديد  ');
      await tester.enterText(find.widgetWithText(TextFormField, 'رقم الهاتف *'), '٠١٠ ١٢٣٤٥٦٧٨');
      await tester.enterText(find.widgetWithText(TextFormField, 'العنوان (اختياري)'), 'مدينة نصر');
      await tester.enterText(find.widgetWithText(TextFormField, 'ملاحظات (اختياري)'), 'محل أدوات صحية');
      await tester.tap(find.text('حفظ الحساب')); await tester.pumpAndSettle();
      expect(selected, 'new-account'); expect(saved!['name'], 'تاجر جديد');
      expect(saved!['phone'], '01012345678'); expect(saved!['address'], 'مدينة نصر');
      expect(saved!['note'], 'محل أدوات صحية'); expect(saved!['balance'], 0);
      expect(saved!['openingBalance'], 0); expect(saved!['active'], true);
      expect(quantity.text, '24'); expect(paid.text, '500');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox()); quantity.dispose(); paid.dispose();
    });
  }
  testWidgets('account submission disables repeat save and failed response retains all fields for retry', (tester) async {
    var calls = 0; final first = Completer<String>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AccountEntryDialog(supplier: false,
      onSave: (_) { calls++; return calls == 1 ? first.future : Future.value('confirmed'); }))));
    await tester.enterText(find.widgetWithText(TextFormField, 'الاسم *'), 'عميل تجريبي');
    await tester.enterText(find.widgetWithText(TextFormField, 'رقم الهاتف *'), '01012345678');
    await tester.tap(find.text('حفظ الحساب')); await tester.pump();
    expect(calls, 1); expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    first.completeError(StateError('network')); await tester.pumpAndSettle();
    expect(find.textContaining('تعذر حفظ الحساب'), findsOneWidget);
    expect(find.text('عميل تجريبي'), findsOneWidget); expect(find.text('01012345678'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('small phone and keyboard allow cancellation without creating an account', (tester) async {
    tester.view.physicalSize = const Size(360, 640); tester.view.devicePixelRatio = 1;
    addTearDown(() { tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio(); });
    var calls = 0; String? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () async { result = await showDialog<String>(context: context,
        builder: (_) => AccountEntryDialog(supplier: true, onSave: (_) async { calls++; return 'id'; })); },
        child: const Text('open')))), builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(viewInsets: const EdgeInsets.only(bottom: 270)), child: child!)));
    await tester.tap(find.text('open')); await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('إلغاء')); await tester.pumpAndSettle();
    expect(result, isNull); expect(calls, 0); expect(find.byType(AccountEntryDialog), findsNothing);
  });
  test('phone normalization preserves leading zero and rejects ambiguous letters', () {
    expect(accountPhone('٠١٠-١٢٣٤٥٦٧٨'), '01012345678');
    expect(accountPhone('+20 (10) 12345678'), '+201012345678');
    expect(RegExp(r'^\+?[0-9]{6,15}$').hasMatch(accountPhone('010ABC123')), isFalse);
  });
}
