part of 'main.dart';

// Profit reporting is read-only. It never changes invoices, inventory or ledgers.
int _prCents(dynamic value) {
  if (value is! num || !value.isFinite) {
    throw StateError('قيمة مالية غير صحيحة في أحد سجلات الأرباح');
  }
  return (value * 100).round();
}
String _prMoney(int value) => '${(value / 100).toStringAsFixed(2)} ج.م';
String _prText(dynamic value, String fallback) {
  final result = value == null ? '' : '$value'.trim();
  return result.isEmpty || result == 'null' ? fallback : result;
}

class _ProfitEntry {
  final String invoiceId, invoiceNumber, customerKey, customerName;
  final String productKey, productName;
  final DateTime date;
  final bool isReturn, hasCost;
  final double quantity;
  final int revenue, cost;
  const _ProfitEntry({
    required this.invoiceId, required this.invoiceNumber,
    required this.customerKey, required this.customerName,
    required this.productKey, required this.productName,
    required this.date, required this.isReturn, required this.hasCost,
    required this.quantity, required this.revenue, required this.cost,
  });
  int? get profit => hasCost ? revenue - cost : null;
}

class _ProfitGroup {
  final String title;
  int revenue = 0, knownCost = 0, missingCost = 0, lineCount = 0;
  _ProfitGroup(this.title);
  void add(_ProfitEntry e) {
    revenue += e.revenue;
    knownCost += e.cost;
    lineCount++;
    if (!e.hasCost) missingCost++;
  }
  int? get profit => missingCost == 0 ? revenue - knownCost : null;
}

class _ProfitData {
  final List<_ProfitEntry> lines;
  final int expenses, salesCount, returnsCount;
  const _ProfitData(this.lines, this.expenses, this.salesCount, this.returnsCount);
  int get revenue => lines.fold<int>(0, (sum, e) => sum + e.revenue);
  int get knownCost => lines.fold<int>(0, (sum, e) => sum + e.cost);
  int get missingCost => lines.where((e) => !e.hasCost).length;
  int? get gross => missingCost == 0 ? revenue - knownCost : null;
  int? get net => gross == null ? null : gross! - expenses;

  List<_ProfitGroup> grouped(String by) {
    final groups = <String, _ProfitGroup>{};
    for (final e in lines) {
      final key = switch (by) {
        'invoice' => e.invoiceId,
        'product' => e.productKey,
        'customer' => e.customerKey,
        _ => e.invoiceId,
      };
      final name = switch (by) {
        'invoice' => 'فاتورة ${e.invoiceNumber} • ${e.customerName}',
        'product' => e.productName,
        'customer' => e.customerName,
        _ => e.invoiceNumber,
      };
      groups.putIfAbsent(key, () => _ProfitGroup(name)).add(e);
    }
    final result = groups.values.toList();
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }
}

// The same cent-based calculation drives all five views and their PDF exports.
// Sales remain included when marked returned; matching return documents are
// deducted on the return date, avoiding the same return being removed twice.
_ProfitData _buildProfitData(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> sales,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> returns,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> expenseRows,
  DateTime from,
  DateTime exclusiveEnd,
) {
  final lines = <_ProfitEntry>[];
  var salesCount = 0, returnsCount = 0, expenses = 0;

  void addInvoice(QueryDocumentSnapshot<Map<String, dynamic>> doc, bool returned) {
    final d = doc.data();
    if (!visibleAfterReset(d)) return;
    final stamp = d['createdAt'];
    if (stamp is! Timestamp) return;
    final date = stamp.toDate();
    if (date.isBefore(from) || !date.isBefore(exclusiveEnd)) return;
    if (returned) { returnsCount++; } else { salesCount++; }

    final total = _prCents(d['total']);
    final sourceId = returned
        ? _prText(d['sourceInvoiceId'], doc.id) : doc.id;
    final number = invoiceDisplayNumber('sales', sourceId, d);
    final customerName = _prText(d['customerName'], 'بدون عميل مسجل');
    final customerId = _prText(d['customerId'], '');
    final customerKey = customerId.isEmpty ? 'name:$customerName' : 'id:$customerId';
    final rawItems = d['items'];
    final items = <Map<String, dynamic>>[];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) items.add(Map<String, dynamic>.from(item));
      }
    }
    if (items.isEmpty) {
      items.add({
        'productId': d['productId'], 'productName': d['productName'],
        'quantity': d['quantity'], 'unitPrice': d['unitPrice'],
        'lineTotal': d['total'],
        'purchasePriceAtSale': d['purchasePriceAtSale'],
      });
    }

    final weights = <double>[];
    for (final item in items) {
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final rawLine = item['lineTotal'];
      final unit = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      final weight = rawLine is num && rawLine.isFinite
          ? rawLine.toDouble() : qty * unit;
      weights.add(weight.isFinite && weight > 0 ? weight : 0);
    }
    final sumWeights = weights.fold<double>(0, (sum, v) => sum + v);
    var used = 0;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final validQty = qty.isFinite && qty >= 0;
      final share = i == items.length - 1
        ? total - used
        : (total * (sumWeights > 0 ? weights[i] / sumWeights : 1 / items.length)).round();
      used += share;
      final rawCost = item['purchasePriceAtSale'];
      final hasCost = validQty && rawCost is num && rawCost.isFinite && rawCost >= 0;
      final cost = hasCost ? (qty * (rawCost as num).toDouble() * 100).round() : 0;
      final productName = _prText(item['productName'], 'صنف غير مسمى');
      final productId = _prText(item['productId'], '');
      lines.add(_ProfitEntry(
        invoiceId: sourceId, invoiceNumber: number,
        customerKey: customerKey, customerName: customerName,
        productKey: productId.isEmpty ? 'name:$productName' : 'id:$productId',
        productName: productName, date: date, isReturn: returned,
        hasCost: hasCost, quantity: returned ? -qty : qty,
        revenue: returned ? -share : share,
        cost: returned ? -cost : cost,
      ));
    }
  }

  for (final doc in sales) { addInvoice(doc, false); }
  for (final doc in returns) { addInvoice(doc, true); }
  for (final doc in expenseRows) {
    final d = doc.data();
    if (!visibleAfterReset(d)) continue;
    final stamp = d['createdAt'];
    if (stamp is! Timestamp) continue;
    final date = stamp.toDate();
    if (date.isBefore(from) || !date.isBefore(exclusiveEnd)) continue;
    expenses += _prCents(d['amount']);
  }
  lines.sort((a, b) => b.date.compareTo(a.date));
  return _ProfitData(lines, expenses, salesCount, returnsCount);
}

const _profitViews = <String, String>{
  'detail': 'مفصل',
  'invoice': 'حسب الفاتورة',
  'product': 'حسب الصنف',
  'customer': 'حسب العميل',
  'summary': 'إجمالي',
};
String _profitLabel(int? cents) =>
  cents == null ? 'غير مكتمل' : _prMoney(cents);

class ProfitBreakdownReport extends StatefulWidget {
  const ProfitBreakdownReport({super.key});
  @override State<ProfitBreakdownReport> createState() => _ProfitBreakdownReportState();
}

class _ProfitBreakdownReportState extends State<ProfitBreakdownReport> {
  String view = 'summary', period = 'day';
  late DateTime start, end;
  bool exporting = false;

  @override void initState() {
    super.initState();
    final now = DateTime.now();
    start = DateTime(now.year, now.month, now.day);
    end = now;
  }

  void choosePeriod(String choice) {
    final range = profitPresetRange(choice, DateTime.now());
    setState(() { period = choice; start = range.start; end = range.end; });
  }

  Future<void> chooseDate(bool from) async {
    final old = from ? start : end;
    final date = await showDatePicker(context: context,
      initialDate: old, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context,
      initialTime: TimeOfDay.fromDateTime(old));
    if (time == null || !mounted) return;
    final chosen = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      period = 'custom';
      if (from) { start = chosen; } else { end = chosen; }
    });
  }

  String pretty(DateTime d) => DateFormat('dd/MM/yyyy HH:mm').format(d);

  Future<void> shareReport() async {
    if (exporting || !profitQueryEnd(end).isAfter(start)) return;
    setState(() => exporting = true);
    try {
      final from = start, until = profitQueryEnd(end), selectedView = view;
      // PDF uses a fresh server snapshot; never silently export cached totals.
      final all = await Future.wait<QuerySnapshot<Map<String, dynamic>>>([
        db.collection('sales')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('createdAt', isLessThan: Timestamp.fromDate(until))
          .get(const GetOptions(source: Source.server)),
        db.collection('salesReturns')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('createdAt', isLessThan: Timestamp.fromDate(until))
          .get(const GetOptions(source: Source.server)),
        db.collection('accountMovements')
          .where('accountType', isEqualTo: 'expenses')
          .get(const GetOptions(source: Source.server)),
      ]);
      final report = _buildProfitData(
        all[0].docs, all[1].docs, all[2].docs, from, until);
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final pdf = await _profitPdf(report, selectedView, from, end, font);
      await Printing.sharePdf(bytes: pdf, filename:
        'VIB-PROFIT-$selectedView-${DateFormat('yyyyMMdd').format(from)}-${DateFormat('yyyyMMdd').format(end)}.pdf');
    } catch (e) {
      if (mounted) await showInvoiceSaveProblem(context, '$e',
        title: 'تعذر إرسال تقرير الأرباح', button: 'رجوع للتقرير');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Widget amount(String label, String value, {bool strong = false}) =>
    Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: vibBlue,
          fontWeight: strong ? FontWeight.bold : FontWeight.normal))),
        Text(value, style: TextStyle(color: vibNeon,
          fontWeight: strong ? FontWeight.bold : FontWeight.normal)),
      ]));

  Widget content(_ProfitData data) {
    final rows = <Widget>[
      amount('صافي المبيعات بعد المرتجعات', _prMoney(data.revenue)),
      amount('تكلفة البضاعة المعروفة', _prMoney(data.knownCost)),
      amount('إجمالي الربح قبل المصروفات', _profitLabel(data.gross)),
      if (view == 'summary') amount('المصروفات', _prMoney(data.expenses)),
      if (view == 'summary') amount('صافي الربح بعد المصروفات', _profitLabel(data.net), strong: true),
      if (view == 'summary') amount('فواتير البيع / المرتجعات',
        '${data.salesCount} / ${data.returnsCount}'),
      if (data.missingCost > 0)
        Padding(padding: const EdgeInsets.all(8),
          child: Text('تنبيه: ${data.missingCost} بند تكلفة شرائه وقت البيع غير مسجلة. الأرباح المرتبطة به غير مكتملة، ولن تُستخدم تكلفة اليوم بدلًا منها.',
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
      const Divider(),
    ];
    if (view == 'summary') {
      rows.add(const Padding(padding: EdgeInsets.all(8),
        child: Text('الأرباح محسوبة من تكلفة وقت البيع، والمرتجعات محسوبة بتاريخ إرجاعها.')));
    } else if (view == 'detail') {
      for (final e in data.lines) {
        rows.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e.productName} • ${e.customerName}', maxLines: 1,
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${e.isReturn ? 'مرتجع' : 'بيع'} • فاتورة ${e.invoiceNumber} • ${pretty(e.date)} • الكمية ${e.quantity.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
            Text('مبيعات: ${_prMoney(e.revenue)}  |  تكلفة: ${e.hasCost ? _prMoney(e.cost) : 'غير معروفة'}  |  ربح: ${_profitLabel(e.profit)}',
              style: const TextStyle(fontSize: 12, color: vibNeon)),
            const Divider(height: 7),
          ])));
      }
    } else {
      final groups = data.grouped(view);
      for (final g in groups) {
        rows.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('مبيعات: ${_prMoney(g.revenue)}  |  تكلفة: ${_prMoney(g.knownCost)}',
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text('الربح: ${_profitLabel(g.profit)}${g.missingCost > 0 ? ' • تكلفة غير مكتملة' : ''}',
              style: const TextStyle(fontSize: 12, color: vibNeon)),
            const Divider(height: 8),
          ])));
      }
    }
    if (data.lines.isEmpty) {
      rows.add(const Center(child: Padding(padding: EdgeInsets.all(16),
        child: Text('لا توجد مبيعات أو مرتجعات في الفترة المحددة'))));
    }
    if (view != 'summary') {
      rows.add(const Padding(padding: EdgeInsets.all(8),
        child: Text('المصروفات لا توزّع على فاتورة أو صنف أو عميل؛ تظهر منفصلة في تقرير الإجمالي.',
          style: TextStyle(fontSize: 11, color: Colors.white70))));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(8, 4, 8, 12), children: rows);
  }

  @override Widget build(BuildContext context) {
    final queryEnd = profitQueryEnd(end);
    final valid = queryEnd.isAfter(start);
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 5, runSpacing: 5, children: [
          for (final item in _profitViews.entries)
            ChoiceChip(label: Text(item.value, style: const TextStyle(fontSize: 12)),
              selected: view == item.key,
              onSelected: (_) => setState(() => view = item.key)),
        ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
        child: DropdownButtonFormField<String>(
          value: period, isExpanded: true,
          decoration: const InputDecoration(labelText: 'الفترة', isDense: true),
          items: const [
            DropdownMenuItem(value: 'day', child: Text('اليوم')),
            DropdownMenuItem(value: 'twoDays', child: Text('يومين')),
            DropdownMenuItem(value: 'threeDays', child: Text('3 أيام')),
            DropdownMenuItem(value: 'week', child: Text('أسبوع')),
            DropdownMenuItem(value: 'month', child: Text('شهر')),
            DropdownMenuItem(value: 'year', child: Text('سنة')),
            DropdownMenuItem(value: 'custom', child: Text('من تاريخ إلى تاريخ')),
          ],
          onChanged: (v) { if (v != null && v != 'custom') choosePeriod(v);
            else if (v == 'custom') setState(() => period = v); })),
      Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 3),
        child: Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => chooseDate(true),
            child: Text('من ${pretty(start)}', style: const TextStyle(fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis))),
          const SizedBox(width: 5),
          Expanded(child: OutlinedButton(
            onPressed: () => chooseDate(false),
            child: Text('إلى ${pretty(end)}', style: const TextStyle(fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis))),
        ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: !valid || exporting ? null : shareReport,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(exporting ? 'جاري تجهيز PDF…' : 'إرسال التقرير PDF / واتساب')))),
      if (!valid) const Expanded(child: Center(
        child: Text('وقت النهاية لازم يكون بعد وقت البداية')))
      else Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('sales')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThan: Timestamp.fromDate(queryEnd)).snapshots(),
        builder: (context, sales) {
          if (sales.hasError) return const Center(child: Text('تعذر تحميل المبيعات'));
          if (!sales.hasData) return const Center(child: CircularProgressIndicator());
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('salesReturns')
              .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
              .where('createdAt', isLessThan: Timestamp.fromDate(queryEnd)).snapshots(),
            builder: (context, returns) {
              if (returns.hasError) return const Center(child: Text('تعذر تحميل المرتجعات'));
              if (!returns.hasData) return const Center(child: CircularProgressIndicator());
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db.collection('accountMovements')
                  .where('accountType', isEqualTo: 'expenses').snapshots(),
                builder: (context, expense) {
                  if (expense.hasError) return const Center(child: Text('تعذر تحميل المصروفات'));
                  if (!expense.hasData) return const Center(child: CircularProgressIndicator());
                  try {
                    return content(_buildProfitData(
                      sales.data!.docs, returns.data!.docs,
                      expense.data!.docs, start, queryEnd));
                  } catch (e) {
                    return Center(child: Text('تعذر حساب التقرير: $e'));
                  }
                });
            });
        })),
    ]);
  }
}

Future<Uint8List> _profitPdf(
  _ProfitData report, String view, DateTime from, DateTime to, pw.Font font) async {
  final pdf = pw.Document();
  const navy = PdfColor.fromInt(0xFF14263D);
  const goldPdf = PdfColor.fromInt(0xFFB58A38);
  pw.Widget cell(String value, {bool heading = false}) =>
    pw.Padding(padding: const pw.EdgeInsets.all(4),
      child: pw.Text(value, textAlign: pw.TextAlign.right,
        style: pw.TextStyle(fontSize: view == 'detail' ? 7 : 9,
          color: heading ? PdfColors.white : PdfColors.black)));
  final header = view == 'detail'
      ? ['الربح', 'التكلفة', 'المبيعات', 'الكمية', 'الصنف', 'العميل', 'الفاتورة', 'التاريخ']
      : ['الربح', 'التكلفة', 'المبيعات', _profitViews[view] ?? 'البند'];
  final rows = <List<String>>[];
  if (view == 'detail') {
    for (final e in report.lines) {
      rows.add([
        _profitLabel(e.profit), e.hasCost ? _prMoney(e.cost) : 'غير معروف',
        _prMoney(e.revenue), e.quantity.toStringAsFixed(2), e.productName,
        e.customerName, '${e.isReturn ? 'مرتجع ' : ''}${e.invoiceNumber}',
        DateFormat('dd/MM/yyyy HH:mm').format(e.date),
      ]);
    }
  } else if (view != 'summary') {
    for (final g in report.grouped(view)) {
      rows.add([_profitLabel(g.profit),
        g.missingCost > 0 ? 'غير مكتملة' : _prMoney(g.knownCost),
        _prMoney(g.revenue), g.title]);
    }
  }
  pdf.addPage(pw.MultiPage(
    pageFormat: view == 'detail' ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    maxPages: 1000, textDirection: pw.TextDirection.rtl,
    theme: pw.ThemeData.withFont(base: font, bold: font),
    footer: (ctx) => pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
      textAlign: pw.TextAlign.center),
    build: (_) => [
      pw.Center(child: pw.Text('VIB للتجارة والتوزيع',
        style: pw.TextStyle(fontSize: 20, color: navy, fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text('تقرير الأرباح — ${_profitViews[view] ?? 'إجمالي'}',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 8),
      pw.Text('من ${DateFormat('dd/MM/yyyy HH:mm').format(from)} إلى ${DateFormat('dd/MM/yyyy HH:mm').format(to)}'),
      pw.Text('فواتير: ${report.salesCount} • مرتجعات: ${report.returnsCount}'),
      pw.SizedBox(height: 6),
      pw.Text('صافي المبيعات: ${_prMoney(report.revenue)} • تكلفة البضاعة المعروفة: ${_prMoney(report.knownCost)}'),
      pw.Text('الربح قبل المصروفات: ${_profitLabel(report.gross)} • المصروفات: ${_prMoney(report.expenses)}'),
      pw.Text('صافي الربح بعد المصروفات: ${_profitLabel(report.net)}',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      if (report.missingCost > 0) pw.Text('تنبيه: ${report.missingCost} بند تكلفة وقت البيع غير معروفة؛ الأرباح غير مكتملة.'),
      pw.SizedBox(height: 12),
      if (view != 'summary') pw.Table(
        border: pw.TableBorder.all(color: goldPdf, width: .5),
        children: [
          pw.TableRow(repeat: true,
            decoration: const pw.BoxDecoration(color: navy),
            children: header.map((s) => cell(s, heading: true)).toList()),
          for (final values in rows)
            pw.TableRow(children: values.map((v) => cell(v)).toList()),
        ]),
      if (view != 'summary') pw.SizedBox(height: 8),
      pw.Text('المصروفات تُخصم من الإجمالي، ولا تُوزّع على الفواتير أو الأصناف أو العملاء.',
        style: const pw.TextStyle(fontSize: 9)),
    ],
  ));
  return pdf.save();
}
