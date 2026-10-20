part of 'main.dart';

class StoreMovementRow {
  final String title;
  final int amountCents;
  final List<Map<String, dynamic>> entries;
  const StoreMovementRow(this.title, this.amountCents, this.entries);
}

class StoreMovementSummary {
  final DateTime from, to;
  final List<StoreMovementRow> rows;
  const StoreMovementSummary(this.from, this.to, this.rows);
  StoreMovementRow operator [](String title) => rows.firstWhere((row) => row.title == title);
}

int _storeCents(dynamic value) {
  if (value is! num || !value.isFinite) return 0;
  return (value * 100).round();
}

bool _storeInPeriod(Map<String, dynamic> row, DateTime from, DateTime to, {String dateKey = 'createdAt'}) {
  final stamp = row[dateKey];
  if (stamp is! Timestamp) return false;
  final date = stamp.toDate();
  return !date.isBefore(movementReportBoundary(from)) &&
      date.isBefore(movementReportBoundary(to, next: true)) && visibleAfterReset(row);
}

StoreMovementSummary summarizeStoreMovement({
  required DateTime from,
  required DateTime to,
  required List<Map<String, dynamic>> sales,
  required List<Map<String, dynamic>> purchases,
  required List<Map<String, dynamic>> salesReturns,
  required List<Map<String, dynamic>> purchaseReturns,
  required List<Map<String, dynamic>> expenses,
  required List<Map<String, dynamic>> movements,
  required List<Map<String, dynamic>> receipts,
  required List<Map<String, dynamic>> customers,
  required List<Map<String, dynamic>> suppliers,
  required double cashBalance,
  Set<String> cancelledReceiptIds = const {},
  Set<String> cancelledSupplierPaymentIds = const {},
}) {
  if (!movementReportBoundary(to, next: true).isAfter(movementReportBoundary(from))) {
    throw StateError('تاريخ النهاية يجب أن يكون بعد البداية أو في نفس اليوم');
  }
  final periodSales = sales.where((r) => _storeInPeriod(r, from, to)).toList();
  final periodPurchases = purchases.where((r) => _storeInPeriod(r, from, to)).toList();
  final periodSalesReturns = salesReturns.where((r) => _storeInPeriod(r, from, to)).toList();
  final periodPurchaseReturns = purchaseReturns.where((r) => _storeInPeriod(r, from, to)).toList();
  final periodExpenses = expenses.where((r) => _storeInPeriod(r, from, to)).toList();
  final periodMovements = movements.where((r) => _storeInPeriod(r, from, to)).toList();
  final periodReceipts = receipts.where((r) => _storeInPeriod(r, from, to, dateKey: 'receiptDate') &&
      !cancelledReceiptIds.contains('${r['id'] ?? ''}')).toList();
  int sum(List<Map<String, dynamic>> rows, String key) => rows.fold(0, (value, row) => value + _storeCents(row[key]));
  int positiveBalances(List<Map<String, dynamic>> rows, String key) => rows.fold(0, (value, row) {
    final cents = _storeCents(row[key]);
    return value + (cents > 0 ? cents : 0);
  });
  List<Map<String, dynamic>> withAmount(List<Map<String, dynamic>> rows, int Function(Map<String, dynamic>) amount) =>
      rows.map((row) => <String, dynamic>{...row, '_storeAmount': amount(row) / 100}).toList();
  int remainingOpening(List<Map<String, dynamic>> rows) => rows.fold(0, (value, row) {
    final balance = _storeCents(row['balance']);
    final opening = _storeCents(row['openingBalance']);
    return value + (balance > 0 && opening > 0 ? (balance < opening ? balance : opening) : 0);
  });
  int invoiceBalance(Map<String, dynamic> row) {
    final balance = _storeCents(row['balance']), opening = _storeCents(row['openingBalance']);
    return balance > 0 && balance > opening ? balance - (opening > 0 ? opening : 0) : 0;
  }
  final purchaseTotal = sum(periodPurchases, 'total');
  final purchasePaid = periodPurchases.fold(0, (value, row) => value + _storeCents(row['cashPosted'] == true ? row['paid'] : row['cashPaidPosted'] ?? row['paid']));
  final purchaseDue = sum(periodPurchases, 'due');
  final purchaseCard = periodPurchases.fold(0, (value, row) => value + _storeCents(row['cardPaid'] ?? row['cardAmount']));
  final purchaseCheque = periodPurchases.fold(0, (value, row) => value + _storeCents(row['chequePaid'] ?? row['checkAmount']));
  final salesTotal = sum(periodSales, 'total');
  final salesPaid = sum(periodSales, 'paid');
  final salesOnline = sum(periodSales, 'onlinePaid');
  final salesDue = sum(periodSales, 'due');
  final salesCash = (salesPaid - salesOnline).clamp(0, salesPaid).toInt();
  final salesCheque = sum(periodSales, 'chequePaid') + sum(periodSales, 'checkAmount');
  final supplierPayments = periodMovements.where((r) => r['accountType'] == 'suppliers' && r['kind'] == 'payment' &&
      !cancelledSupplierPaymentIds.contains('${r['id'] ?? ''}')).toList();
  final supplierVoucherPaid = sum(supplierPayments, 'amount');
  final supplierBalance = positiveBalances(suppliers, 'balance');
  final supplierOpening = remainingOpening(suppliers);
  final customerBalance = positiveBalances(customers, 'balance');
  final customerOpening = remainingOpening(customers);
  final suppliersByInvoiceBalance = withAmount(suppliers, invoiceBalance);
  final suppliersByOpening = withAmount(suppliers, (row) {
    final balance = _storeCents(row['balance']), opening = _storeCents(row['openingBalance']);
    return balance > 0 && opening > 0 ? (balance < opening ? balance : opening) : 0;
  });
  final customersByInvoiceBalance = withAmount(customers, invoiceBalance);
  final customersByOpening = withAmount(customers, (row) {
    final balance = _storeCents(row['balance']), opening = _storeCents(row['openingBalance']);
    return balance > 0 && opening > 0 ? (balance < opening ? balance : opening) : 0;
  });
  final cashPeriodMovements = periodMovements.where((r) => r['accountType'] == 'cash').toList();
  final cashPeriodDelta = cashPeriodMovements.fold(0, (value, row) {
    final delta = row['delta'];
    if (delta is num && delta.isFinite) return value + (delta * 100).round();
    return value;
  });
  final salesReturnsCents = sum(periodSalesReturns, 'total');
  final purchaseReturnsCents = sum(periodPurchaseReturns, 'total');
  final expenseCents = sum(periodExpenses, 'amount');
  final salesDiscount = periodSales.fold(0, (value, invoice) {
    final recorded = _storeCents(invoice['discountAmount'] ?? invoice['discount']);
    var discount = recorded;
    final items = invoice['items'];
    if (recorded == 0 && items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final base = (item['basePrice'] as num?)?.toDouble();
        final unit = (item['unitPrice'] as num?)?.toDouble();
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
        if (base != null && unit != null && base > unit) discount += ((base - unit) * quantity * 100).round();
      }
    }
    return value + discount;
  });
  final salesTax = sum(periodSales, 'taxAmount') + sum(periodSales, 'tax');
  int costOf(List<Map<String, dynamic>> invoices) {
    var total = 0;
    for (final invoice in invoices) {
      final items = invoice['items'];
      if (items is List && items.isNotEmpty) {
        for (final item in items) {
          if (item is! Map) continue;
          final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
          final unitCost = (item['purchasePriceAtSale'] as num?)?.toDouble() ?? (item['purchasePrice'] as num?)?.toDouble();
          if (unitCost != null) total += _storeCents(quantity * unitCost);
        }
      } else {
        final quantity = (invoice['quantity'] as num?)?.toDouble() ?? 0;
        final unitCost = (invoice['purchasePriceAtSale'] as num?)?.toDouble();
        if (unitCost != null) total += _storeCents(quantity * unitCost);
      }
    }
    return total;
  }
  final grossProfit = salesTotal - salesReturnsCents - costOf(periodSales) + costOf(periodSalesReturns);
  final rows = <StoreMovementRow>[
    StoreMovementRow('إجمالي المشتريات', purchaseTotal, periodPurchases),
    StoreMovementRow('إجمالي المشتريات نقدًا', purchasePaid, withAmount(periodPurchases, (row) => _storeCents(row['cashPosted'] == true ? row['paid'] : row['cashPaidPosted'] ?? row['paid']))),
    StoreMovementRow('إجمالي المشتريات آجل', purchaseDue, withAmount(periodPurchases, (row) => _storeCents(row['due']))),
    StoreMovementRow('إجمالي المشتريات (بطاقة)', purchaseCard, withAmount(periodPurchases, (row) => _storeCents(row['cardPaid'] ?? row['cardAmount']))),
    StoreMovementRow('إجمالي المشتريات (شيك)', purchaseCheque, withAmount(periodPurchases, (row) => _storeCents(row['chequePaid'] ?? row['checkAmount']))),
    StoreMovementRow('إجمالي مرتجع المشتريات', purchaseReturnsCents, periodPurchaseReturns),
    StoreMovementRow('إجمالي المتبقي للموردين من الفواتير', supplierBalance - supplierOpening, suppliersByInvoiceBalance),
    StoreMovementRow('إجمالي المتبقي للموردين من الأرصدة الافتتاحية', supplierOpening, suppliersByOpening),
    StoreMovementRow('إجمالي السداد للموردين', supplierVoucherPaid + purchasePaid, [
      ...withAmount(supplierPayments, (row) => _storeCents(row['amount'])),
      ...withAmount(periodPurchases, (row) => _storeCents(row['cashPosted'] == true ? row['paid'] : row['cashPaidPosted'] ?? row['paid'])),
    ]),
    StoreMovementRow('إجمالي المصروفات', expenseCents, periodExpenses),
    StoreMovementRow('إجمالي المتبقي عند العملاء من الفواتير', customerBalance - customerOpening, customersByInvoiceBalance),
    StoreMovementRow('إجمالي المتبقي عند العملاء من الأرصدة الافتتاحية', customerOpening, customersByOpening),
    StoreMovementRow('إجمالي السداد من العملاء', sum(periodReceipts, 'amount'), withAmount(periodReceipts, (row) => _storeCents(row['amount']))),
    StoreMovementRow('إجمالي الأرباح', grossProfit, periodSales),
    StoreMovementRow('إجمالي الأرباح بعد خصم المصروفات', grossProfit - expenseCents, [...periodSales, ...periodExpenses]),
    StoreMovementRow('الرصيد في الصندوق', (cashBalance * 100).round(), cashPeriodMovements),
    StoreMovementRow('حركة الصندوق خلال الفترة', cashPeriodDelta, cashPeriodMovements),
    StoreMovementRow('إجمالي المبيعات', salesTotal, periodSales),
    StoreMovementRow('إجمالي المبيعات نقدًا', salesCash, withAmount(periodSales, (row) => (_storeCents(row['paid']) - _storeCents(row['onlinePaid'])).clamp(0, _storeCents(row['paid'])).toInt())),
    StoreMovementRow('إجمالي المبيعات آجل', salesDue, withAmount(periodSales, (row) => _storeCents(row['due']))),
    StoreMovementRow('إجمالي المبيعات (بطاقة)', salesOnline, withAmount(periodSales, (row) => _storeCents(row['onlinePaid']))),
    StoreMovementRow('إجمالي المبيعات (شيك)', salesCheque, withAmount(periodSales, (row) => _storeCents(row['chequePaid']) + _storeCents(row['checkAmount']))),
    StoreMovementRow('إجمالي مرتجع المبيعات', salesReturnsCents, periodSalesReturns),
    StoreMovementRow('إجمالي الخصومات', salesDiscount, periodSales),
    StoreMovementRow('إجمالي الضرائب', salesTax, periodSales),
  ];
  return StoreMovementSummary(from, to, List.unmodifiable(rows));
}

class StoreMovementReportPage extends StatefulWidget {
  const StoreMovementReportPage({super.key});
  @override State<StoreMovementReportPage> createState() => _StoreMovementReportPageState();
}

class _StoreMovementReportPageState extends State<StoreMovementReportPage> {
  late DateTime from, to;
  int generation = 0;
  @override void initState() {
    super.initState();
    final now = tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
    from = to = DateTime(now.year, now.month, now.day);
  }
  Future<StoreMovementSummary> load() async {
    Query<Map<String, dynamic>> periodQuery(String collection, {String field = 'createdAt'}) => db.collection(collection)
      .where(field, isGreaterThanOrEqualTo: Timestamp.fromDate(movementReportBoundary(from)))
      .where(field, isLessThan: Timestamp.fromDate(movementReportBoundary(to, next: true)));
    final snapshots = await Future.wait([
      periodQuery('sales').get(), periodQuery('purchases').get(), periodQuery('salesReturns').get(),
      periodQuery('purchaseReturns').get(), periodQuery('accountMovements').get(),
      periodQuery('receipts', field: 'receiptDate').get(), periodQuery('receipts').get(),
      db.collection('customers').get(), db.collection('suppliers').get(), db.collection('settings').doc('cash').get(),
      db.collection('voucherCancellations').get(),
    ]);
    List<Map<String, dynamic>> data(int index) => (snapshots[index] as QuerySnapshot<Map<String, dynamic>>).docs
      .where((doc) => visibleAfterReset(doc.data())).map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id}).toList();
    final movementDocs = (snapshots[4] as QuerySnapshot<Map<String, dynamic>>).docs;
    final movementRows = movementDocs.where((doc) => visibleAfterReset(doc.data())).map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id}).toList();
    final receiptRows = <String, Map<String, dynamic>>{};
    for (final index in [5, 6]) {
      for (final doc in (snapshots[index] as QuerySnapshot<Map<String, dynamic>>).docs) {
        if (visibleAfterReset(doc.data())) receiptRows[doc.id] = <String, dynamic>{...doc.data(), 'id': doc.id};
      }
    }
    // Original vouchers remain in Firestore for audit. Exclude fully cancelled
    // vouchers from paid totals, matching the dashboard's customer payments.
    final cancellations = (snapshots[10] as QuerySnapshot<Map<String, dynamic>>).docs
      .where((doc) => visibleAfterReset(doc.data())).map((doc) => doc.data());
    final cancelledReceipts = <String>{}, cancelledPayments = <String>{};
    for (final cancellation in cancellations) {
      final originalId = '${cancellation['originalId'] ?? ''}';
      if (originalId.isEmpty) continue;
      if (cancellation['type'] == 'receipt') cancelledReceipts.add(originalId);
      if (cancellation['type'] == 'supplierPayment') cancelledPayments.add(originalId);
    }
    final cash = (snapshots[9] as DocumentSnapshot<Map<String, dynamic>>).data()?['balance'];
    return summarizeStoreMovement(from: from, to: to, sales: data(0), purchases: data(1), salesReturns: data(2),
      purchaseReturns: data(3), movements: movementRows, receipts: receiptRows.values.toList(),
      expenses: movementRows.where((row) => row['accountType'] == 'expenses').toList(),
      customers: data(7), suppliers: data(8), cashBalance: cash is num ? cash.toDouble() : 0,
      cancelledReceiptIds: cancelledReceipts,
      cancelledSupplierPaymentIds: cancelledPayments);
  }
  void showDetails(StoreMovementRow row) {
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (sheet) => Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(child: SizedBox(height: MediaQuery.sizeOf(sheet).height * .72, child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Text(row.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          Text(movementReportMoney(row.amountCents), style: const TextStyle(color: gold, fontSize: 20)),
          Text('الفترة من ${DateFormat('dd/MM/yyyy').format(from)} إلى ${DateFormat('dd/MM/yyyy').format(to)}'),
        ])),
        Expanded(child: row.entries.isEmpty ? const Center(child: Text('لا توجد تفاصيل في الفترة')) : ListView.builder(
          itemCount: row.entries.length, itemBuilder: (context, index) {
            final entry = row.entries[index];
            final date = (entry['receiptDate'] ?? entry['createdAt']) as Timestamp?;
            final title = '${entry['customerName'] ?? entry['supplierName'] ?? entry['reason'] ?? entry['category'] ?? entry['name'] ?? 'حركة'}';
            final amount = entry['_storeAmount'] ?? entry['total'] ?? entry['amount'] ?? entry['balance'] ?? 0;
            return ListTile(dense: true, leading: Text('${index + 1}'), title: Text(title),
              subtitle: Text('${date == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(date.toDate())}  •  ${entry['internalNumber'] ?? entry['invoiceNumber'] ?? entry['referenceId'] ?? entry['kind'] ?? ''}'),
              trailing: Text('${(amount as num?)?.toStringAsFixed(2) ?? '0.00'} ج.م'));
          })),
      ]))),
    ));
  }
  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 4), child: Column(children: [
      MovementPeriodControls(key: ValueKey('${from.toIso8601String()}-${to.toIso8601String()}-$generation'), from: from, to: to, enabled: true, compact: true,
        onConfirm: (start, end) { setState(() { from = start; to = end; generation++; }); }),
    ])),
    Expanded(child: FutureBuilder<StoreMovementSummary>(key: ValueKey('$generation'), future: load(), builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('تعذر تحميل حركة المتجر: ${snapshot.error}', textAlign: TextAlign.center));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final summary = snapshot.data!;
      const sections = <String, List<String>>{
        'المشتريات': ['إجمالي المشتريات','إجمالي المشتريات نقدًا','إجمالي المشتريات آجل','إجمالي المشتريات (بطاقة)','إجمالي المشتريات (شيك)','إجمالي مرتجع المشتريات','إجمالي المتبقي للموردين من الفواتير','إجمالي المتبقي للموردين من الأرصدة الافتتاحية','إجمالي السداد للموردين'],
        'المصروفات': ['إجمالي المصروفات'],
        'العملاء والأرباح': ['إجمالي المتبقي عند العملاء من الفواتير','إجمالي المتبقي عند العملاء من الأرصدة الافتتاحية','إجمالي السداد من العملاء','إجمالي الأرباح','إجمالي الأرباح بعد خصم المصروفات'],
        'الصندوق': ['الرصيد في الصندوق','حركة الصندوق خلال الفترة'],
        'المبيعات': ['إجمالي المبيعات','إجمالي المبيعات نقدًا','إجمالي المبيعات آجل','إجمالي المبيعات (بطاقة)','إجمالي المبيعات (شيك)','إجمالي مرتجع المبيعات','إجمالي الخصومات','إجمالي الضرائب'],
      };
      return ListView(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), children: [
        for (final section in sections.entries) ...[
          Padding(padding: const EdgeInsetsDirectional.only(top: 10, bottom: 3), child: Text(section.key,
            style: const TextStyle(color: Colors.redAccent, fontSize: 19, fontWeight: FontWeight.bold))),
          for (final title in section.value)
            Card(child: ListTile(dense: true, title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(movementReportMoney(summary[title].amountCents), style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4), const Icon(Icons.chevron_left, color: Color(0xFF64B5F6)),
              ]), onTap: () => showDetails(summary[title]))),
        ],
        const Padding(padding: EdgeInsets.all(10), child: Text('أرصدة الصندوق والعملاء والموردين تظهر كأرصدة اليوم. باقي البنود محسوبة داخل الفترة المختارة. الأرباح تقديرية بحسب تكلفة الأصناف المحفوظة في الفواتير؛ وتظهر طرق الدفع والضرائب المسجلة فقط.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
      ]);
    })),
  ]);
}
