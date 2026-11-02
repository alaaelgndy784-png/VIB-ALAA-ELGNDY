part of 'main.dart';

// Customer-specific invoice withdrawals report. Reads historical sale lines,
// never modifies invoices, inventory or payments.
bool vibCustomerInvoiceMatches(String customerId, String customerName, Map<String, dynamic> invoice) {
  final recordedId = (invoice['customerId'] ?? '').toString().trim();
  if (recordedId.isNotEmpty) return recordedId == customerId;
  final recordedName = (invoice['customerName'] ?? '').toString().trim();
  return customerName.isNotEmpty && invoiceSearchText(recordedName) == invoiceSearchText(customerName);
}

List<Map<String, dynamic>> vibCustomerInvoiceLines(Map<String, dynamic> invoice) =>
    _saleReturnInvoiceItems(invoice);

class CustomerSalesReportPage extends StatefulWidget {
  const CustomerSalesReportPage({super.key});
  @override State<CustomerSalesReportPage> createState() => _CustomerSalesReportPageState();
}

class _CustomerSalesReportPageState extends State<CustomerSalesReportPage> {
  late DateTime from, to;
  late Stream<QuerySnapshot<Map<String, dynamic>>> salesStream, returnsStream;
  String? customerId;
  String customerName = '';
  bool exporting = false;

  @override void initState() {
    super.initState();
    final now = tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
    setDates(DateTime(now.year, now.month, 1), DateTime(now.year, now.month, now.day));
  }

  void setDates(DateTime first, DateTime last) {
    from = first;
    to = last;
    salesStream = db.collection('sales')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(movementReportBoundary(from)))
        .where('createdAt', isLessThan: Timestamp.fromDate(movementReportBoundary(to, next: true)))
        .orderBy('createdAt', descending: true).snapshots(includeMetadataChanges: true);
    returnsStream = db.collection('salesReturns')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(movementReportBoundary(from)))
        .where('createdAt', isLessThan: Timestamp.fromDate(movementReportBoundary(to, next: true)))
        .orderBy('createdAt', descending: true).snapshots(includeMetadataChanges: true);
  }

  Future<void> selectCustomer() async {
    if (exporting) return;
    final search = TextEditingController();
    final found = await showModalBottomSheet<MapEntry<String, String>>(
      context: context, isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, refresh) =>
        SafeArea(child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
          child: SizedBox(height: MediaQuery.sizeOf(sheet).height * .72, child: Column(children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('اختيار العميل', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(controller: search, autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث باسم العميل'),
                onChanged: (_) => refresh(() {}))),
            Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('customers').snapshots(),
              builder: (sheet, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('تعذر تحميل العملاء'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final needle = invoiceSearchText(search.text);
                final choices = snapshot.data!.docs.where((d) {
                  final name = (d.data()['name'] ?? '').toString().trim();
                  return name.isNotEmpty && invoiceSearchText(name).contains(needle);
                }).toList()..sort((a,b) => (a.data()['name'] ?? '').toString()
                    .compareTo((b.data()['name'] ?? '').toString()));
                if (choices.isEmpty) return const Center(child: Text('لا يوجد عميل بهذا الاسم'));
                return ListView.builder(itemCount: choices.length, itemBuilder: (sheet, index) {
                  final doc = choices[index];
                  final name = (doc.data()['name'] ?? '').toString().trim();
                  return ListTile(title: Text(name), onTap: () =>
                    Navigator.pop(sheet, MapEntry(doc.id, name)));
                });
              },
            )),
          ])),
        )),
      ),
    );
    search.dispose();
    if (found != null && mounted) setState(() {
      customerId = found.key;
      customerName = found.value;
    });
  }

  InvoiceMovementReport buildReport(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> invoices,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> returns,
      String id, String name) {
    List<Map<String, dynamic>> matches(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      docs.where((d) => visibleAfterReset(d.data()) && vibCustomerInvoiceMatches(id, name, d.data()))
        .map((d) => <String, dynamic>{...d.data(), 'id': d.id,
          'displayNumber': invoiceDisplayNumber('sales',
              (d.data()['sourceInvoiceId'] ?? d.id).toString(), d.data())}).toList();
    return summarizeInvoiceMovement(matches(invoices), from, to, type: 'sales', returns: matches(returns));
  }

  Future<void> shareReport() async {
    final id = customerId;
    final name = customerName;
    if (id == null || exporting) return;
    setState(() => exporting = true);
    try {
      final start = Timestamp.fromDate(movementReportBoundary(from));
      final end = Timestamp.fromDate(movementReportBoundary(to, next: true));
      final invoiceQuery = db.collection('sales').where('createdAt', isGreaterThanOrEqualTo: start)
          .where('createdAt', isLessThan: end).orderBy('createdAt', descending: true);
      final returnsQuery = db.collection('salesReturns').where('createdAt', isGreaterThanOrEqualTo: start)
          .where('createdAt', isLessThan: end).orderBy('createdAt', descending: true);
      final invoices = await invoiceQuery.get(const GetOptions(source: Source.server));
      final returns = await returnsQuery.get(const GetOptions(source: Source.server));
      if (invoices.metadata.isFromCache || returns.metadata.isFromCache ||
          invoices.metadata.hasPendingWrites || returns.metadata.hasPendingWrites) {
        throw StateError('انتظر اكتمال المزامنة قبل إرسال التقرير');
      }
      final report = buildReport(invoices.docs, returns.docs, id, name);
      if (report.rows.isEmpty && report.returns.isEmpty) throw StateError('لا توجد حركات لهذا العميل في الفترة');
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final bytes = await createCustomerSalesReportPdf(name, report, font);
      await Printing.sharePdf(bytes: bytes,
        filename: 'VIB-CUSTOMER-SALES-' + DateFormat('yyyyMMdd').format(from) + '-' +
          DateFormat('yyyyMMdd').format(to) + '.pdf');
    } catch (e) {
      if (mounted) await showInvoiceSaveProblem(context, '$e',
          title: 'تعذر إرسال تقرير مسحوبات العميل', button: 'رجوع للتقرير');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
      child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: exporting ? null : selectCustomer,
        icon: const Icon(Icons.person_search),
        label: Text(customerId == null ? 'اختر العميل' : customerName,
          maxLines: 1, overflow: TextOverflow.ellipsis)))),
    MovementPeriodControls(key: ValueKey(from.toIso8601String() + to.toIso8601String()),
      compact: true, from: from, to: to, enabled: !exporting,
      onConfirm: (first, last) => setState(() => setDates(first, last))),
    if (customerId == null) const Expanded(child: Center(child:
      Text('اختار اسم العميل والفترة عشان تظهر كل فواتيره ومسحوباته'))),
    if (customerId != null) Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: salesStream, builder: (context, saleSnapshot) {
        if (saleSnapshot.hasError) return const Center(child: Text('تعذر تحميل الفواتير'));
        if (!saleSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: returnsStream,
          builder: (context, returnSnapshot) {
            if (returnSnapshot.hasError) return const Center(child: Text('تعذر تحميل المرتجعات'));
            if (!returnSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            final InvoiceMovementReport report;
            try {
              report = buildReport(saleSnapshot.data!.docs, returnSnapshot.data!.docs,
                customerId!, customerName);
            } catch (e) {
              return Center(child: Text('راجع بيانات التقرير: $e'));
            }
            final verified = !saleSnapshot.data!.metadata.isFromCache &&
              !saleSnapshot.data!.metadata.hasPendingWrites &&
              !returnSnapshot.data!.metadata.isFromCache &&
              !returnSnapshot.data!.metadata.hasPendingWrites;
            return Column(children: [
              Card(child: Padding(padding: const EdgeInsets.all(9), child: Column(children: [
                Text('عدد الفواتير: ' + report.rows.length.toString() +
                  ' • مرتجعات الفترة: ' + report.returnedCount.toString()),
                Text('إجمالي المسحوبات: ' + movementReportMoney(report.totalCents),
                  style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
                Text('المرتجعات: ' + movementReportMoney(report.returnCents)),
                Text('صافي الحركة: ' + movementReportMoney(report.netCents),
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                Text('المدفوع المرتبط بالفواتير: ' + movementReportMoney(report.paidCents) +
                  ' • الباقي: ' + movementReportMoney(report.dueCents)),
                if (!verified) const Text('البيانات محلية؛ إرسال PDF متاح بعد المزامنة',
                  style: TextStyle(fontSize: 11)),
              ]))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: verified && !exporting && (report.rows.isNotEmpty || report.returns.isNotEmpty)
                    ? shareReport : null,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(exporting ? 'جاري تجهيز PDF' : 'إرسال تقرير العميل PDF / واتساب')))),
              Expanded(child: report.rows.isEmpty ? Center(child:
                Text(report.returns.isEmpty ? 'لا توجد فواتير للعميل في الفترة' : 'لا توجد فواتير؛ توجد مرتجعات في الفترة')) :
                ListView.builder(itemCount: report.rows.length, itemBuilder: (context, index) {
                  final row = report.rows[index];
                  final items = vibCustomerInvoiceLines(row.data);
                  return Card(child: ExpansionTile(
                    title: Text('فاتورة ' + row.number + (row.returned ? ' • مرتجعة بالكامل' : '')),
                    subtitle: Text(movementReportDate(row.date) + ' • ' + movementReportMoney(row.totalCents)),
                    children: [
                      for (final item in items) ListTile(
                        dense: true,
                        title: Text((item['productName'] ?? 'صنف غير مسمى').toString()),
                        subtitle: Text('كمية: ' + (item['quantity'] ?? 0).toString() +
                          ' • سعر: ' + (item['unitPrice'] ?? 0).toString()),
                        trailing: Text(((item['lineTotal'] as num?)?.toDouble() ??
                          (((item['quantity'] as num?) ?? 0) * ((item['unitPrice'] as num?) ?? 0)).toDouble())
                          .toStringAsFixed(2) + ' ج.م')),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('المدفوع: ' + movementReportMoney(row.paidCents) +
                          ' • الباقي: ' + movementReportMoney(row.dueCents))),
                      TextButton.icon(onPressed: () => showInvoiceOverview(context, 'sales', row.id),
                        icon: const Icon(Icons.receipt_long), label: const Text('عرض الفاتورة')),
                    ],
                  ));
                })),
              if (report.returns.isNotEmpty) Padding(padding: const EdgeInsets.all(6),
                child: Text('مرتجعات الفترة: ' + report.returns.map((r) =>
                  r.number + ' (' + movementReportMoney(r.totalCents) + ')').join(' • '),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Text('السندات العامة غير الموزعة على الفواتير ليست ضمن المدفوع.',
                  style: TextStyle(fontSize: 10), textAlign: TextAlign.center)),
            ]);
          });
      })),
  ]);
}

Future<Uint8List> createCustomerSalesReportPdf(
    String customerName, InvoiceMovementReport report, pw.Font font) async {
  final pdf = pw.Document();
  const navy = PdfColor.fromInt(0xFF14263D);
  pw.Widget cell(String text, {bool heading = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(4),
    child: pw.Text(text, textAlign: pw.TextAlign.right,
      style: pw.TextStyle(fontSize: 9, color: heading ? PdfColors.white : PdfColors.black)));
  pw.Widget itemTable(Map<String, dynamic> data) {
    final items = vibCustomerInvoiceLines(data);
    return pw.Table(border: pw.TableBorder.all(width: .4), children: [
      pw.TableRow(decoration: const pw.BoxDecoration(color: navy),
        children: ['الصنف', 'الكمية', 'سعر الوحدة', 'الإجمالي'].map((t) => cell(t, heading: true)).toList()),
      for (final item in items) pw.TableRow(children: [
        cell((item['productName'] ?? 'صنف غير مسمى').toString()),
        cell((item['quantity'] ?? 0).toString()),
        cell((item['unitPrice'] ?? 0).toString()),
        cell((((item['lineTotal'] as num?)?.toDouble() ??
          (((item['quantity'] as num?) ?? 0) * ((item['unitPrice'] as num?) ?? 0)).toDouble()))
          .toStringAsFixed(2)),
      ]),
    ]);
  }
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4, maxPages: 1000,
    theme: pw.ThemeData.withFont(base: font, bold: font),
    textDirection: pw.TextDirection.rtl,
    footer: (context) => pw.Text(context.pageNumber.toString() + ' / ' + context.pagesCount.toString()),
    build: (context) => [
      pw.Center(child: pw.Text('VIB للتجارة والتوزيع', style: pw.TextStyle(fontSize: 20, color: navy))),
      pw.Center(child: pw.Text('تقرير مسحوبات عميل', style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold))),
      pw.Text('العميل: ' + customerName),
      pw.Text('من ' + DateFormat('dd/MM/yyyy').format(report.from) + ' إلى ' + DateFormat('dd/MM/yyyy').format(report.to)),
      pw.Text('الفواتير: ' + report.rows.length.toString() +
        ' • إجمالي: ' + movementReportMoney(report.totalCents) +
        ' • المرتجعات: ' + movementReportMoney(report.returnCents) +
        ' • صافي الحركة: ' + movementReportMoney(report.netCents)),
      pw.SizedBox(height: 10),
      // Every sale starts on a fresh page. Long item tables can flow across
      // pages, but a different invoice must never start on the same page.
      for (var i = 0; i < report.rows.length; i++) ...[
        if (i > 0) pw.NewPage(),
        pw.Text('فاتورة ' + report.rows[i].number + ' | ' + movementReportDate(report.rows[i].date) +
          (report.rows[i].returned ? ' | مرتجعة بالكامل' : ''),
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        itemTable(report.rows[i].data),
        pw.Text('إجمالي الفاتورة: ' + movementReportMoney(report.rows[i].totalCents) +
          ' | مدفوع: ' + movementReportMoney(report.rows[i].paidCents) +
          ' | باقي: ' + movementReportMoney(report.rows[i].dueCents)),
        pw.SizedBox(height: 10),
      ],
      if (report.returns.isNotEmpty) ...[
        // Keep returns separate from the last sales invoice too.
        if (report.rows.isNotEmpty) pw.NewPage(),
        pw.Text('المرتجعات خلال الفترة', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        for (var i = 0; i < report.returns.length; i++) ...[
          if (i > 0) pw.NewPage(),
          pw.Text('مرتجع فاتورة ' + report.returns[i].number + ' | ' + movementReportDate(report.returns[i].date) +
            ' | ' + movementReportMoney(report.returns[i].totalCents)),
          itemTable(report.returns[i].data),
          pw.SizedBox(height: 8),
        ],
      ],
      pw.Text('المدفوع مرتبط بالفواتير فقط؛ السندات العامة لا توزع تلقائيًا.',
        style: const pw.TextStyle(fontSize: 9)),
    ]));
  return pdf.save();
}
