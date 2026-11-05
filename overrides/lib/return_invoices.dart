part of 'main.dart';

// Saved return receipts are read-only accounting documents. Printing a receipt
// never modifies the inventory, cashbox, source invoice or customer balance.
class VibReturnInvoiceEntry {
  final String type;
  final String id;
  final Map<String, dynamic> data;
  const VibReturnInvoiceEntry(this.type, this.id, this.data);
  bool get sales => type == 'sales';
  String get party => (data[sales ? 'customerName' : 'supplierName'] ?? 'غير مسجل').toString();
  String get number => (sales ? 'MR-' : 'PR-') + id.substring(0, id.length < 10 ? id.length : 10).toUpperCase();
}

double _vibReturnAmount(dynamic value) => value is num && value.isFinite
    ? value.toDouble() : 0.0;
String _vibReturnMoney(num value) => value.toStringAsFixed(2);

List<Map<String, dynamic>> _vibReturnItems(Map<String, dynamic> data) {
  final result = <Map<String, dynamic>>[];
  final raw = data['items'];
  if (raw is List) {
    for (final item in raw) {
      if (item is Map) result.add(Map<String, dynamic>.from(item));
    }
  }
  if (result.isEmpty && data['productName'] != null) {
    result.add({
      'productName': data['productName'], 'quantity': data['quantity'] ?? 0,
      'lineTotal': data['total'] ?? 0, 'unitPrice': data['unitPrice'] ?? data['unitCost'] ?? 0,
    });
  }
  return result;
}

// Older returns saved before this screen did not have a snapshot of account
// balances. Never make up a historical balance by using today's account amount.
({double refunded, double debt}) vibReturnSettlement(VibReturnInvoiceEntry entry) {
  final d = entry.data;
  if (d['cashRefund'] is num && d['debtReduction'] is num) {
    return (refunded: _vibReturnAmount(d['cashRefund']), debt: _vibReturnAmount(d['debtReduction']));
  }
  try {
    final old = returnSettlement(d, sales: entry.sales);
    return (refunded: old.cash, debt: old.debt);
  } catch (_) {
    return (refunded: 0, debt: 0);
  }
}

Future<Uint8List> createVibReturnInvoicePdf(
    VibReturnInvoiceEntry entry, String paper, {double? currentBalance}) async {
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final doc = pw.Document();
  final thermal = paper == '80';
  final data = entry.data;
  final settled = vibReturnSettlement(entry);
  final items = _vibReturnItems(data);
  final total = _vibReturnAmount(data['total']);
  final savedAfter = data['balanceAfter'];
  final savedBefore = data['balanceBefore'];
  final sourceNumber = (data['invoiceNumber'] ?? data['internalNumber'] ??
      data['sourceInvoiceId'] ?? 'غير مسجل').toString();
  final time = data['createdAt'] is Timestamp
      ? DateFormat('dd/MM/yyyy HH:mm').format((data['createdAt'] as Timestamp).toDate())
      : 'غير مسجل';
  final black = PdfColors.black;
  final gold = const PdfColor.fromInt(0xFFC59D39);
  pw.Widget line(String left, String right, {bool strong = false}) => pw.Padding(
    padding: pw.EdgeInsets.symmetric(vertical: thermal ? 2 : 5),
    child: pw.Row(children: [
      pw.Expanded(child: pw.Text(left, style: pw.TextStyle(font: font,
          fontSize: thermal ? 8 : 10, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal))),
      pw.SizedBox(width: 4),
      pw.Text(right, style: pw.TextStyle(font: font,
          fontSize: thermal ? 8 : 10, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
    ]));
  pw.Widget title(String value, {double? size}) => pw.Center(child: pw.Text(value,
    textAlign: pw.TextAlign.center, style: pw.TextStyle(font: font,
        fontSize: size ?? (thermal ? 11 : 15), fontWeight: pw.FontWeight.bold)));
  final parts = <pw.Widget>[
    title('VIB ALAA ELGNDY', size: thermal ? 12 : 19),
    pw.SizedBox(height: 4),
    title(entry.sales ? 'فاتورة مرتجع مبيعات' : 'فاتورة مرتجع مشتريات'),
    pw.SizedBox(height: 6),
    pw.Divider(color: thermal ? black : gold),
    line('رقم فاتورة المرتجع', entry.number, strong: true),
    line('رقم الفاتورة الأصلية', sourceNumber),
    line('تاريخ المرتجع', time),
    line(entry.sales ? 'التاجر / العميل' : 'المورد', entry.party, strong: true),
    pw.Divider(color: black),
    title('بيان الأصناف المرتجعة', size: thermal ? 9 : 12),
    ...items.asMap().entries.map((row) {
      final item = row.value;
      final qty = _vibReturnAmount(item['quantity']);
      final amount = item['lineTotal'] is num ? _vibReturnAmount(item['lineTotal'])
          : qty * _vibReturnAmount(item[entry.sales ? 'unitPrice' : 'unitCost']);
      final price = qty == 0 ? 0 : amount / qty;
      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 3),
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400))),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text((row.key + 1).toString() + ' - ' + (item['productName'] ?? 'صنف').toString(),
              style: pw.TextStyle(font: font, fontSize: thermal ? 8 : 10, fontWeight: pw.FontWeight.bold)),
          line('كمية ' + _vibReturnMoney(qty) + ' × ' + _vibReturnMoney(price),
               _vibReturnMoney(amount) + ' ج.م'),
        ]),
      );
    }),
    pw.SizedBox(height: 7),
    pw.Divider(color: thermal ? black : gold, thickness: 1.4),
    line('إجمالي قيمة المرتجع', _vibReturnMoney(total) + ' ج.م', strong: true),
    line(entry.sales ? 'الخصم من مديونية التاجر' : 'تخفيض المبلغ المستحق للمورد',
        _vibReturnMoney(settled.debt) + ' ج.م'),
    line(entry.sales ? 'المبلغ النقدي المردود للتاجر' : 'المبلغ النقدي المسترد من المورد',
        _vibReturnMoney(settled.refunded) + ' ج.م'),
    if (savedBefore is num) line('رصيد الحساب قبل المرتجع',
        _vibReturnMoney(savedBefore) + ' ج.م'),
    if (savedAfter is num) ...[
      line('الرصيد بعد المرتجع', _vibReturnMoney(savedAfter) + ' ج.م', strong: true),
      line('حالة الحساب بعد المرتجع',
          accountBalanceLabel(savedAfter, supplier: !entry.sales)),
    ] else
      line('الرصيد وقت تسجيل المرتجع', 'غير محفوظ في السجل القديم'),
    if ((total - settled.debt - settled.refunded).abs() > 0.011)
      line('فرق يحتاج مراجعة تسوية الفاتورة',
          _vibReturnMoney(total - settled.debt - settled.refunded) + ' ج.م', strong: true),
    if (currentBalance != null) ...[
      pw.Divider(color: black),
      line('رصيد الحساب الحالي وقت الطباعة',
          _vibReturnMoney(currentBalance) + ' ج.م', strong: true),
      line('حالة الحساب الحالية',
          accountBalanceLabel(currentBalance, supplier: !entry.sales)),
    ],
    pw.SizedBox(height: 8),
    pw.Divider(color: black),
    title('تم إثبات هذا المرتجع مع الاحتفاظ بالفاتورة الأصلية',
        size: thermal ? 7 : 9),
  ];
  final pageTheme = pw.ThemeData.withFont(base: font, bold: font);
  if (thermal) {
    // A finite 80 mm page prevents the long blank paper tail seen with A4 layouts.
    final itemHeight = items.fold<double>(0, (n, item) {
      final name = (item['productName'] ?? '').toString();
      return n + 17 + (name.length / 24).ceil() * 5;
    });
    final heightMm = 122 + itemHeight + (currentBalance == null ? 0 : 14);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, heightMm * PdfPageFormat.mm),
      margin: const pw.EdgeInsets.all(3 * PdfPageFormat.mm),
      theme: pageTheme,
      build: (_) => pw.Directionality(textDirection: pw.TextDirection.rtl,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: parts)),
    ));
  } else {
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4, theme: pageTheme,
      margin: const pw.EdgeInsets.all(16 * PdfPageFormat.mm),
      build: (_) => [for (final part in parts)
        pw.Directionality(textDirection: pw.TextDirection.rtl, child: part)],
    ));
  }
  return doc.save();
}

class ReturnInvoicesPage extends StatefulWidget {
  final String type;
  const ReturnInvoicesPage({super.key, this.type = 'all'});
  @override State<ReturnInvoicesPage> createState() => _ReturnInvoicesPageState();
}
class _ReturnInvoicesPageState extends State<ReturnInvoicesPage> {
  late String selectedType = widget.type;
  final search = TextEditingController();
  late Future<List<VibReturnInvoiceEntry>> records = _load();
  @override void dispose() { search.dispose(); super.dispose(); }
  Future<List<VibReturnInvoiceEntry>> _load() async {
    final types = selectedType == 'all' ? ['sales', 'purchases'] : [selectedType];
    final groups = await Future.wait(types.map((type) => db.collection(
        type == 'sales' ? 'salesReturns' : 'purchaseReturns')
        .orderBy('createdAt', descending: true).limit(300)
        .get(const GetOptions(source: Source.server))));
    final result = <VibReturnInvoiceEntry>[];
    for (var i = 0; i < groups.length; i++) {
      for (final doc in groups[i].docs) {
        if (!visibleAfterReset(doc.data())) continue;
        if (doc.data()['returnType'] == 'cancellation') continue;
        result.add(VibReturnInvoiceEntry(types[i], doc.id, doc.data()));
      }
    }
    result.sort((a,b) => (b.data['createdAt'] is Timestamp
        ? (b.data['createdAt'] as Timestamp).millisecondsSinceEpoch : 0)
        .compareTo(a.data['createdAt'] is Timestamp
        ? (a.data['createdAt'] as Timestamp).millisecondsSinceEpoch : 0));
    return result;
  }
  void reload() => setState(() { records = _load(); });
  Future<double?> _balance(VibReturnInvoiceEntry entry) async {
    final id = (entry.data[entry.sales ? 'customerId' : 'supplierId'] ?? '').toString();
    if (id.isEmpty || id == 'null') return null;
    final doc = await db.collection(entry.sales ? 'customers' : 'suppliers')
        .doc(id).get(const GetOptions(source: Source.server));
    final amount = doc.data()?['balance'];
    return amount is num ? amount.toDouble() : null;
  }
  Future<void> _print(VibReturnInvoiceEntry entry, String paper, {bool share = false}) async {
    try {
      final current = await _balance(entry);
      final pdf = await createVibReturnInvoicePdf(entry, paper, currentBalance: current);
      final fileName = 'VIB-RETURN-' + entry.number + '.pdf';
      if (share) {
        final folder = await getTemporaryDirectory();
        final file = File(folder.path + '/' + fileName);
        await file.writeAsBytes(pdf, flush: true);
        await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          text: 'فاتورة مرتجع ' + entry.number + ' - ' + entry.party);
      } else {
        await Printing.layoutPdf(name: fileName, onLayout: (_) async => pdf);
      }
    } catch (e) {
      if (mounted) await showInvoiceSaveProblem(context,
          'تعذرت طباعة فاتورة المرتجع: ' + e.toString(), title: 'خطأ الطباعة');
    }
  }
  void _details(VibReturnInvoiceEntry entry) {
    final d = entry.data, settlement = vibReturnSettlement(entry);
    showModalBottomSheet<void>(context: context, isScrollControlled: true,
      showDragHandle: true, builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text((entry.sales ? 'مرتجع مبيعات • ' : 'مرتجع مشتريات • ') + entry.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 7),
          Text((entry.sales ? 'التاجر: ' : 'المورد: ') + entry.party),
          Text('الفاتورة الأصلية: ' +
              (d['invoiceNumber'] ?? d['internalNumber'] ?? d['sourceInvoiceId'] ?? '-').toString()),
          for (final item in _vibReturnItems(d)) ListTile(
            dense: true, title: Text((item['productName'] ?? 'صنف').toString()),
            subtitle: Text('كمية: ' + (item['quantity'] ?? 0).toString()),
            trailing: Text(_vibReturnMoney(_vibReturnAmount(item['lineTotal'])) + ' ج.م')),
          const Divider(),
          Text('قيمة المرتجع: ' + _vibReturnMoney(_vibReturnAmount(d['total'])) + ' ج.م',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('الخصم من الذمة: ' + _vibReturnMoney(settlement.debt) + ' ج.م'),
          Text((entry.sales ? 'المبلغ المردود للعميل: ' : 'النقدية المستردة من المورد: ') +
              _vibReturnMoney(settlement.refunded) + ' ج.م'),
          if (d['balanceAfter'] is num) Text('الرصيد بعد المرتجع: ' +
              _vibReturnMoney(d['balanceAfter'] as num) + ' ج.م'),
          if (d['balanceAfter'] is! num)
            const Text('الرصيد وقت المرتجع غير محفوظ في الفواتير القديمة.'),
          FutureBuilder<double?>(future: _balance(entry), builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('تعذر قراءة رصيد الحساب الحالي');
            if (!snapshot.hasData) return const SizedBox.shrink();
            return Text('الرصيد الحالي وقت العرض: ' + _vibReturnMoney(snapshot.data!) +
                ' ج.م • ' + accountBalanceLabel(snapshot.data!, supplier: !entry.sales),
                style: const TextStyle(fontWeight: FontWeight.bold));
          }),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
            FilledButton.icon(onPressed: () => _print(entry, 'a4'),
                icon: const Icon(Icons.picture_as_pdf), label: const Text('طباعة A4')),
            FilledButton.icon(onPressed: () => _print(entry, '80'),
                icon: const Icon(Icons.print), label: const Text('طباعة 80 مم')),
            OutlinedButton.icon(onPressed: () => _print(entry, 'a4', share: true),
                icon: const Icon(Icons.share), label: const Text('إرسال PDF')),
          ]),
        ])))));
  }
  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(8), child: Column(children: [
      SegmentedButton<String>(segments: const [
        ButtonSegment(value: 'all', label: Text('الكل')),
        ButtonSegment(value: 'sales', label: Text('التجار')),
        ButtonSegment(value: 'purchases', label: Text('الموردين')),
      ], selected: {selectedType}, onSelectionChanged: (values) {
        setState(() { selectedType = values.first; records = _load(); });
      }),
      const SizedBox(height: 8),
      TextField(controller: search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true, border: const OutlineInputBorder(),
            labelText: 'بحث باسم التاجر أو المورد أو رقم الفاتورة',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(icon: const Icon(Icons.refresh), onPressed: reload))),
    ])),
    Expanded(child: FutureBuilder<List<VibReturnInvoiceEntry>>(
      future: records, builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('تعذر تحميل فواتير المرتجع: ' +
            snapshot.error.toString()));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final q = invoiceSearchText(search.text);
        final rows = snapshot.data!.where((entry) {
          final invoice = (entry.data['invoiceNumber'] ?? entry.data['internalNumber'] ??
              entry.data['sourceInvoiceId'] ?? '').toString();
          return q.isEmpty || invoiceSearchText(
              entry.party + ' ' + entry.number + ' ' + invoice).contains(q);
        }).toList();
        if (rows.isEmpty) return const Center(child: Text('مفيش فواتير مرتجع مطابقة للبحث'));
        return RefreshIndicator(onRefresh: () async {
          final next = _load(); setState(() => records = next); await next;
        }, child: ListView.builder(itemCount: rows.length, itemBuilder: (context, index) {
          final entry = rows[index], total = _vibReturnAmount(entry.data['total']);
          return Card(child: ListTile(
            leading: Icon(entry.sales ? Icons.assignment_return : Icons.assignment_return_outlined),
            title: Text(entry.party + ' • ' + entry.number),
            subtitle: Text((entry.sales ? 'مرتجع تاجر' : 'مرتجع مورد') +
                ' | ' + formatDate(entry.data['createdAt']) +
                ' | ' + _vibReturnItems(entry.data).length.toString() + ' صنف'),
            trailing: Text(_vibReturnMoney(total) + ' ج.م',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () => _details(entry),
          ));
        }));
      },
    )),
  ]);
}
