part of 'main.dart';

// Explicitly read ONLY the customers collection for the customer selector.
// Old sales without customerId are matched only by exact saved customerName;
// a sale belonging to a different known customerId is never attributed by name.
bool _customerWithdrawalMatches(Map<String, dynamic> data, String customerId, String customerName) {
  if (customerId.trim().isEmpty) return false;
  final savedId = '${data['customerId'] ?? ''}'.trim();
  if (savedId.isNotEmpty) return savedId == customerId;
  final savedName = '${data['customerName'] ?? ''}'.trim();
  return savedName.isNotEmpty && savedName == customerName.trim();
}

class CustomerSalesWithdrawalsPage extends StatefulWidget {
  const CustomerSalesWithdrawalsPage({super.key});
  @override State<CustomerSalesWithdrawalsPage> createState() => _CustomerSalesWithdrawalsPageState();
}

class _CustomerSalesWithdrawalsPageState extends State<CustomerSalesWithdrawalsPage> {
  late DateTime from, to;
  String customerId = '', customerName = '';
  bool exporting = false;

  @override void initState() {
    super.initState();
    final now = tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
    from = to = DateTime(now.year, now.month, now.day);
  }

  Future<void> _chooseCustomer() async {
    // The shared sales customer picker reads db.collection('customers') only,
    // excluding suppliers even when their names are identical.
    final id = await selectRegisteredCustomer(context);
    if (id == null || !mounted) return;
    try {
      final doc = await db.collection('customers').doc(id).get();
      if (!mounted) return;
      final name = '${doc.data()?['name'] ?? ''}'.trim();
      if (!doc.exists || doc.data()?['active'] == false || name.isEmpty) {
        throw StateError('العميل غير موجود أو غير نشط');
      }
      setState(() { customerId = id; customerName = name; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر اختيار العميل: $e')));
    }
  }

  Query<Map<String, dynamic>> _periodQuery(String collection) =>
    db.collection(collection)
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(movementReportBoundary(from)))
      .where('createdAt', isLessThan: Timestamp.fromDate(movementReportBoundary(to, next: true)))
      .orderBy('createdAt', descending: true);

  InvoiceMovementReport _summary(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> invoiceDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> returnDocs,
  ) {
    final selectedSales = invoiceDocs.where((doc) =>
      visibleAfterReset(doc.data()) &&
      _customerWithdrawalMatches(doc.data(), customerId, customerName)).toList();
    final matchingInvoiceIds = selectedSales.map((doc) => doc.id).toSet();
    final selectedReturns = returnDocs.where((doc) {
      final data = doc.data();
      if (!visibleAfterReset(data)) return false;
      if (_customerWithdrawalMatches(data, customerId, customerName)) return true;
      // Older returns may have a sourceInvoiceId but no customer fields.
      return matchingInvoiceIds.contains('${data['sourceInvoiceId'] ?? ''}');
    }).toList();
    return summarizeInvoiceMovement(
      selectedSales.map((doc) => <String, dynamic>{
        ...doc.data(), 'id': doc.id,
        'displayNumber': invoiceDisplayNumber('sales', doc.id, doc.data()),
      }).toList(), from, to, type: 'sales',
      returns: selectedReturns.map((doc) => <String, dynamic>{
        ...doc.data(), 'id': doc.id,
        'displayNumber': invoiceDisplayNumber(
          'sales', '${doc.data()['sourceInvoiceId'] ?? doc.id}', doc.data()),
      }).toList(),
    );
  }

  Future<void> _shareReport() async {
    if (customerId.isEmpty || exporting) return;
    setState(() => exporting = true);
    try {
      // Never export old cached invoice data without rechecking the server.
      final serverSales = await _periodQuery('sales').get(const GetOptions(source: Source.server));
      final serverReturns = await _periodQuery('salesReturns').get(const GetOptions(source: Source.server));
      if (serverSales.metadata.isFromCache || serverSales.metadata.hasPendingWrites ||
          serverReturns.metadata.isFromCache || serverReturns.metadata.hasPendingWrites) {
        throw StateError('التقرير لم يتأكد من الخادم، حاول بعد المزامنة');
      }
      final report = _summary(serverSales.docs, serverReturns.docs);
      if (report.rows.isEmpty && report.returns.isEmpty) {
        throw StateError('لا توجد مسحوبات لهذا العميل في الفترة المختارة');
      }
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final bytes = await createInvoiceMovementReportPdf(report, font,
        reportTitle: 'تقرير مسحوبات عميل', reportCustomer: customerName);
      await Printing.sharePdf(bytes: bytes, filename:
        'VIB-CUSTOMER-SALES-${DateFormat('yyyyMMdd').format(from)}-${DateFormat('yyyyMMdd').format(to)}.pdf');
    } catch (e) {
      if (mounted) await showInvoiceSaveProblem(context, '$e',
        title: 'تعذر إرسال تقرير المسحوبات', button: 'رجوع');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 5), child:
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        key: const ValueKey('withdrawals-customers-only-button'),
        onPressed: exporting ? null : _chooseCustomer,
        icon: const Icon(Icons.person_search),
        label: Text(customerId.isEmpty ? 'اختر العميل (العملاء فقط)' : customerName,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      ))),
    MovementPeriodControls(
      from: from, to: to, enabled: !exporting,
      onConfirm: (start, end) => setState(() { from = start; to = end; }),
    ),
    if (customerId.isEmpty) const Expanded(
      child: Center(child: Text('اختار عميل من قائمة العملاء لعرض كل فواتيره خلال الفترة. الموردون مش ظاهرين هنا.'))),
    if (customerId.isNotEmpty) Expanded(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _periodQuery('sales').snapshots(includeMetadataChanges: true),
        builder: (context, invoicesSnap) {
          if (invoicesSnap.hasError) return const Center(child: Text('تعذر تحميل فواتير العميل'));
          if (!invoicesSnap.hasData) return const Center(child: CircularProgressIndicator());
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _periodQuery('salesReturns').snapshots(includeMetadataChanges: true),
            builder: (context, returnsSnap) {
              if (returnsSnap.hasError) return const Center(child: Text('تعذر تحميل مرتجعات العميل'));
              if (!returnsSnap.hasData) return const Center(child: CircularProgressIndicator());
              final InvoiceMovementReport report;
              try {
                report = _summary(invoicesSnap.data!.docs, returnsSnap.data!.docs);
              } catch (e) {
                return Center(child: Text('تعذر حساب المسحوبات: $e', textAlign: TextAlign.center));
              }
              final confirmed = !invoicesSnap.data!.metadata.isFromCache &&
                !invoicesSnap.data!.metadata.hasPendingWrites &&
                !returnsSnap.data!.metadata.isFromCache &&
                !returnsSnap.data!.metadata.hasPendingWrites;
              return Column(children: [
                Card(child: Padding(padding: const EdgeInsets.all(10),
                  child: Column(children: [
                    Text(customerName, style: const TextStyle(
                      color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, fontSize: 17)),
                    Text('من ${DateFormat('dd/MM/yyyy').format(from)} إلى ${DateFormat('dd/MM/yyyy').format(to)}'),
                    Text('عدد الفواتير: ${report.rows.length}'),
                    Text('إجمالي المسحوبات: ${movementReportMoney(report.totalCents)}',
                      style: const TextStyle(color: gold, fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('المرتجعات: ${movementReportMoney(report.returnCents)}'),
                    Text('الصافي: ${movementReportMoney(report.netCents)}',
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    if (!confirmed) const Text('البيانات من الذاكرة أو تنتظر المزامنة',
                      style: TextStyle(color: Colors.orangeAccent)),
                  ]),
                )),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(width: double.infinity, child: FilledButton.icon(
                    onPressed: !confirmed || exporting ||
                        (report.rows.isEmpty && report.returns.isEmpty) ? null : _shareReport,
                    icon: const Icon(Icons.share),
                    label: Text(exporting ? 'جاري تجهيز التقرير' : 'إرسال تقرير العميل PDF / واتساب'),
                  ))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  child: Text('يتم ربط الفواتير بحساب العميل. الفواتير القديمة التي بلا معرف عميل تُطابق بالاسم المسجل حرفيًا.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white70))),
                Expanded(child: report.rows.isEmpty
                  ? const Center(child: Text('لا توجد فواتير لهذا العميل في الفترة المختارة'))
                  : ListView.builder(itemCount: report.rows.length, itemBuilder: (context, index) {
                    final row = report.rows[index];
                    final raw = row.data['items'];
                    final items = raw is List ? raw : const [];
                    return Card(child: ExpansionTile(
                      title: Text('${index + 1}. فاتورة ${row.number}'),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(movementReportDate(row.date)),
                        Text('الإجمالي ${movementReportMoney(row.totalCents)}' +
                          (row.returned ? ' • مرتجعة بالكامل' : ''),
                          style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
                      ]),
                      children: [
                        for (final item in items)
                          if (item is Map)
                            ListTile(dense: true,
                              title: Text('${item['productName'] ?? item['name'] ?? item['productId'] ?? 'صنف'}'),
                              subtitle: Text('الكمية: ${item['quantity'] ?? 0}')),
                        Text('المدفوع: ${movementReportMoney(row.paidCents)} • الباقي: ${movementReportMoney(row.dueCents)}'),
                        TextButton.icon(onPressed: () =>
                          showInvoiceOverview(context, 'sales', row.id),
                          icon: const Icon(Icons.receipt_long), label: const Text('عرض الفاتورة كاملة')),
                      ],
                    ));
                  })),
              ]);
            },
          );
        },
      ),
    ),
  ]);
}
