part of 'main.dart';

class InvoiceMovementReportRow {
  final String id, number, customer;
  final DateTime date;
  final int totalCents, paidCents, dueCents;
  final bool returned;
  final Map<String, dynamic> data;
  const InvoiceMovementReportRow({required this.id, required this.number, required this.customer,
    required this.date, required this.totalCents, required this.paidCents, required this.dueCents,
    required this.returned, required this.data});
}
class InvoiceMovementReport {
  final DateTime from, to;
  final String type;
  final List<InvoiceMovementReportRow> rows, returns;
  const InvoiceMovementReport(this.from, this.to, this.rows, this.type, this.returns);
  Iterable<InvoiceMovementReportRow> get active => rows.where((r) => !r.returned);
  int get totalCents => rows.fold(0, (v, r) => v + r.totalCents);
  int get paidCents => active.fold(0, (v, r) => v + r.paidCents);
  int get dueCents => active.fold(0, (v, r) => v + r.dueCents);
  int get returnedCount => returns.length;
  int get returnCents => returns.fold(0, (v, r) => v + r.totalCents);
  int get netCents => totalCents - returnCents;
}
DateTime movementReportBoundary(DateTime day, {bool next = false}) =>
  tz.TZDateTime(tz.getLocation('Africa/Cairo'), day.year, day.month, day.day + (next ? 1 : 0));
String movementReportDate(DateTime date) =>
  DateFormat('yyyy/MM/dd HH:mm').format(tz.TZDateTime.from(date, tz.getLocation('Africa/Cairo')));
String movementReportMoney(int cents) => '${(cents / 100).toStringAsFixed(2)} ج.م';

InvoiceMovementReport summarizeInvoiceMovement(List<Map<String, dynamic>> invoices, DateTime from, DateTime to, {String type = 'sales', List<Map<String, dynamic>> returns = const []}) {
  final sales = type == 'sales';
  final start = movementReportBoundary(from), end = movementReportBoundary(to, next: true);
  if (!end.isAfter(start)) throw StateError('تاريخ النهاية يجب أن يكون بعد البداية أو في نفس اليوم');
  int cents(dynamic value, String id) {
    if (value is! num || !value.isFinite || value < 0) throw StateError('بيانات مالية غير صحيحة في الفاتورة $id');
    return (value * 100).round();
  }
  final rows = <InvoiceMovementReportRow>[];
  for (final invoice in invoices) {
    final stamp = invoice['createdAt'];
    if (stamp is! Timestamp) continue;
    final date = stamp.toDate();
    if (date.isBefore(start) || !date.isBefore(end)) continue;
    final id = '${invoice['id'] ?? ''}';
    final total = cents(invoice['total'], id);
    final recordedDue = invoice['due'] == null ? null : cents(invoice['due'], id);
    final basePaid = invoice['paid'] != null ? cents(invoice['paid'], id)
      : recordedDue != null ? total - recordedDue : sales ? total : 0;
    final receipts = cents(invoice['receiptPaid'] ?? 0, id);
    final originalDue = recordedDue ?? total - basePaid;
    if(basePaid < 0 || basePaid > total || (basePaid + originalDue - total).abs() > 1)
      throw StateError('المدفوع والباقي لا يطابقان إجمالي الفاتورة $id');
    final returned = invoice['status'] == 'returned';
    final due = originalDue - receipts;
    if (!returned && due < 0) throw StateError('السداد يتجاوز باقي الفاتورة $id؛ راجع بياناتها');
    final name = '${invoice[sales ? 'customerName' : 'supplierName'] ?? ''}'.trim();
    rows.add(InvoiceMovementReportRow(id: id, number: '${invoice['displayNumber'] ?? id}',
      customer: name.isEmpty ? (sales ? 'بدون عميل مسجل' : 'مورد غير مسمى') : name, date: date,
      totalCents: total, paidCents: basePaid + receipts, dueCents: returned ? 0 : due,
      returned: returned, data: Map<String, dynamic>.from(invoice)));
  }
  rows.sort((a, b) {
    final order = b.date.compareTo(a.date);
    return order == 0 ? a.id.compareTo(b.id) : order;
  });
  final returnRows = returns.isEmpty ? <InvoiceMovementReportRow>[] : summarizeInvoiceMovement(
    returns.map((r) => <String,dynamic>{...r, 'paid': 0, 'due': r['total'], 'receiptPaid': 0, 'status': 'completed'}).toList(),
    from, to, type: type).rows;
  return InvoiceMovementReport(from, to, List.unmodifiable(rows), type, List.unmodifiable(returnRows));
}

const movementReportNote = 'إجمالي الحركة من فواتير الفترة، وصافي الحركة بعد طرح مرتجعات الفترة حسب تاريخ المرتجع حتى لو كانت الفاتورة الأصلية أقدم. المدفوع والباقي لكل فاتورة بحسب السداد المرتبط بها؛ السندات العامة لا توزع على الفواتير تلقائيًا.';
class InvoiceMovementReportPage extends StatefulWidget {
  final String type;
  const InvoiceMovementReportPage({super.key, required this.type});
  @override State<InvoiceMovementReportPage> createState() => _InvoiceMovementReportPageState();
}
class _InvoiceMovementReportPageState extends State<InvoiceMovementReportPage> {
  late DateTime from, to;
  late Stream<QuerySnapshot<Map<String, dynamic>>> invoices, returns;
  bool get sales => widget.type == 'sales';
  String get returnCollection => sales ? 'salesReturns' : 'purchaseReturns';
  bool numbering = true, exporting = false;
  String numberError = '';
  @override void initState() {
    super.initState();
    final now = tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
    from = to = DateTime(now.year, now.month, now.day);
    selectRange(from, to);
    prepareNumbers();
  }
  Future<void> prepareNumbers() async {
    setState(() { numbering = true; numberError = ''; });
    try {
      await prepareInvoiceSerials(widget.type);
      if (mounted) setState(() => numbering = false);
    } catch (e) {
      if (mounted) setState(() { numbering = false; numberError = 'تعذر تجهيز أرقام الفواتير: $e'; });
    }
  }
  void selectRange(DateTime start, DateTime finish) {
    from = start; to = finish;
    invoices = db.collection(widget.type)
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(movementReportBoundary(from)))
      .where('createdAt', isLessThan: Timestamp.fromDate(movementReportBoundary(to, next: true)))
      .orderBy('createdAt', descending: true).snapshots(includeMetadataChanges: true);
    returns = db.collection(returnCollection)
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(movementReportBoundary(from)))
      .where('createdAt', isLessThan: Timestamp.fromDate(movementReportBoundary(to, next: true)))
      .orderBy('createdAt', descending: true).snapshots(includeMetadataChanges: true);
  }
  Future<void> output(InvoiceMovementReport report, {InvoiceMovementReportRow? row}) async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      // Reconfirm the selected period on the server before generating a report.
      final query = db.collection(widget.type)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(movementReportBoundary(report.from)))
        .where('createdAt', isLessThan: Timestamp.fromDate(movementReportBoundary(report.to, next: true)))
        .orderBy('createdAt', descending: true);
      if (row != null) {
        final saved = await db.collection(widget.type).doc(row.id).get(const GetOptions(source: Source.server));
        if(saved.metadata.hasPendingWrites || saved.metadata.isFromCache) throw StateError('انتظر تأكيد الفاتورة من الخادم');
        if (!saved.exists || !visibleAfterReset(saved.data()!)) throw StateError('الفاتورة لم تعد متاحة');
        final fresh = saved.data()!;
        final stamp = fresh['createdAt'];
        if (stamp is! Timestamp || stamp.toDate().isBefore(movementReportBoundary(report.from)) ||
            !stamp.toDate().isBefore(movementReportBoundary(report.to, next: true))) throw StateError('الفاتورة خارج الفترة المختارة');
        if (mounted) await exportInvoicePdf(context, widget.type, row.id, fresh);
      } else {
        final fresh = await query.get(const GetOptions(source: Source.server));
        final freshReturns = await db.collection(returnCollection)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(movementReportBoundary(report.from)))
          .where('createdAt', isLessThan: Timestamp.fromDate(movementReportBoundary(report.to, next: true)))
          .orderBy('createdAt', descending: true).get(const GetOptions(source: Source.server));
        if(fresh.metadata.hasPendingWrites || fresh.metadata.isFromCache || freshReturns.metadata.hasPendingWrites || freshReturns.metadata.isFromCache) throw StateError('انتظر اكتمال مزامنة بيانات التقرير');
        final confirmed = summarizeInvoiceMovement(fresh.docs.where((d) => visibleAfterReset(d.data()))
          .map((d) => <String, dynamic>{...d.data(), 'id': d.id,
            'displayNumber': invoiceDisplayNumber(widget.type, d.id, d.data())}).toList(), report.from, report.to, type: widget.type,
          returns: freshReturns.docs.where((d) => visibleAfterReset(d.data()))
            .map((d) => <String,dynamic>{...d.data(), 'id': d.id,
              'displayNumber': invoiceDisplayNumber(widget.type, '${d.data()['sourceInvoiceId'] ?? d.id}', d.data())}).toList());
        if (confirmed.rows.isEmpty && confirmed.returns.isEmpty) throw StateError('لا توجد فواتير في الفترة المختارة');
        final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
        final bytes = await createInvoiceMovementReportPdf(confirmed, font);
        await Printing.sharePdf(bytes: bytes, filename: 'VIB-${sales ? 'SALES' : 'PURCHASES'}-REPORT-${DateFormat('yyyyMMdd').format(report.from)}-${DateFormat('yyyyMMdd').format(report.to)}.pdf');
      }
    } catch (e) {
      if (mounted) await showInvoiceSaveProblem(context, '$e', title: 'تعذر إرسال التقرير', button: 'رجوع للتقرير');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }
  @override Widget build(BuildContext context) => Column(children: [
    MovementPeriodControls(from: from, to: to, enabled: !exporting,
      onConfirm: (start, end) => setState(() => selectRange(start, end))),
    Text('${DateFormat('yyyy/MM/dd').format(from)} - ${DateFormat('yyyy/MM/dd').format(to)}'),
    if (numbering) const LinearProgressIndicator(),
    if (numberError.isNotEmpty) TextButton(onPressed: exporting ? null : prepareNumbers, child: Text('$numberError — إعادة المحاولة')),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: invoices, builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('تعذر تحميل تقرير الحركة؛ راجع الاتصال'));
      if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream: returns, builder: (context, returnSnapshot) {
      if (returnSnapshot.hasError) return const Center(child: Text('تعذر تحميل المرتجعات؛ لا يمكن حساب صافي الحركة'));
      if (!returnSnapshot.hasData || returnSnapshot.connectionState == ConnectionState.waiting) return const Center(child:CircularProgressIndicator());
      final InvoiceMovementReport report;
      try {
        report = summarizeInvoiceMovement(snapshot.data!.docs.where((d) => visibleAfterReset(d.data()))
          .map((d) => <String, dynamic>{...d.data(), 'id': d.id,
            'displayNumber': invoiceDisplayNumber(widget.type, d.id, d.data())}).toList(), from, to, type: widget.type,
          returns: returnSnapshot.data!.docs.where((d) => visibleAfterReset(d.data()))
            .map((d) => <String,dynamic>{...d.data(), 'id': d.id,
              'displayNumber': invoiceDisplayNumber(widget.type, '${d.data()['sourceInvoiceId'] ?? d.id}', d.data())}).toList());
      } catch (e) { return Center(child: Text('$e', textAlign: TextAlign.center)); }
      final confirmed = !snapshot.data!.metadata.isFromCache && !snapshot.data!.metadata.hasPendingWrites && !returnSnapshot.data!.metadata.isFromCache && !returnSnapshot.data!.metadata.hasPendingWrites;
      final enabled = confirmed && !numbering && numberError.isEmpty && !exporting;
      return Column(children: [
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Text('عدد الفواتير: ${report.rows.length} • مرتجعات الفترة: ${report.returnedCount}'),
          Text('الإجمالي: ${movementReportMoney(report.totalCents)}', style: const TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 19)),
          Text('مرتجعات الفترة: ${movementReportMoney(report.returnCents)}'),
          Text('صافي الحركة: ${movementReportMoney(report.netCents)}', style: const TextStyle(color: Colors.greenAccent, fontWeight:FontWeight.bold)),
          if (!confirmed) const Text('انتظر تأكيد البيانات من الخادم قبل الإرسال'),
        ]))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: FilledButton.icon(
          onPressed: !enabled || (report.rows.isEmpty && report.returns.isEmpty) ? null : () => output(report),
          icon: exporting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.share),
          label: Text(exporting ? 'جاري تجهيز PDF…' : 'إرسال التقرير كامل PDF / واتساب'))),
        const Padding(padding: EdgeInsets.all(8), child: Text(movementReportNote, style: TextStyle(fontSize: 11), textAlign: TextAlign.center)),
        if(report.returns.isNotEmpty) Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Text('مرتجعات الفترة: ${report.returns.map((r)=>'${r.number}: ${movementReportMoney(r.totalCents)}').take(3).join(' • ')}${report.returns.length>3 ? ' • باقي المرتجعات في PDF' : ''}')),
        Expanded(child: report.rows.isEmpty ? const Center(child: Text('لا توجد فواتير في الفترة المختارة')) :
          ListView.builder(itemCount: report.rows.length, itemBuilder: (context, index) {
            final row = report.rows[index];
            return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${index + 1}. فاتورة ${row.number}${row.returned ? ' • مرتجعة بالكامل' : ''}'),
              Text(row.customer, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
              Text(movementReportDate(row.date)),
              Text('الإجمالي: ${movementReportMoney(row.totalCents)}'),
              Text('المدفوع: ${movementReportMoney(row.paidCents)} • الباقي: ${movementReportMoney(row.dueCents)}'),
              Wrap(spacing: 8, children: [
                TextButton.icon(onPressed: enabled ? () => showInvoiceOverview(context, widget.type, row.id) : null,
                  icon: const Icon(Icons.receipt_long), label: const Text('عرض الفاتورة')),
                TextButton.icon(onPressed: enabled ? () => output(report, row: row) : null,
                  icon: const Icon(Icons.share), label: const Text('إرسال هذه الفاتورة PDF')),
              ]),
            ])));
          })),
      ]);
      });
    })),
  ]);
}

Future<Uint8List> createInvoiceMovementReportPdf(InvoiceMovementReport report, pw.Font font) async {
  final pdf = pw.Document();
  const navy = PdfColor.fromInt(0xFF14263D), accent = PdfColor.fromInt(0xFFB58A38);
  pw.Widget cell(String value, {bool header = false, bool customer = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(5), child: pw.Text(value, textAlign: pw.TextAlign.right,
      style: pw.TextStyle(fontSize: 9, color: header ? PdfColors.white : customer ? const PdfColor.fromInt(0xFF006B3C) : PdfColors.black)));
  pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, maxPages: 1000,
    theme: pw.ThemeData.withFont(base: font, bold: font), textDirection: pw.TextDirection.rtl,
    footer: (context) => pw.Text('${context.pageNumber} / ${context.pagesCount}', textAlign: pw.TextAlign.center),
    build: (_) => [
      pw.Center(child: pw.Text('VIB للتجارة والتوزيع', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 22, color: navy))),
      pw.SizedBox(height: 8), pw.Center(child: pw.Text(report.type == 'sales' ? 'تقرير حركة المبيعات' : 'تقرير حركة المشتريات', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 18))),
      pw.Text('من ${DateFormat('yyyy/MM/dd').format(report.from)} إلى ${DateFormat('yyyy/MM/dd').format(report.to)} • توقيت القاهرة'),
      pw.Text('عدد الفواتير: ${report.rows.length} • مرتجعات الفترة: ${report.returnedCount}'),
      pw.SizedBox(height: 8),
      pw.Text('إجمالي الفواتير: ${movementReportMoney(report.totalCents)} • المرتجعات: ${movementReportMoney(report.returnCents)} • صافي الحركة: ${movementReportMoney(report.netCents)}',
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 12),
      pw.Table(border: pw.TableBorder.all(color: accent, width: .5), columnWidths: {
        0: const pw.FlexColumnWidth(1.2), 1: const pw.FlexColumnWidth(1.2), 2: const pw.FlexColumnWidth(1.2),
        3: const pw.FlexColumnWidth(1.6), 4: const pw.FlexColumnWidth(2.2), 5: const pw.FlexColumnWidth(1.2), 6: const pw.FlexColumnWidth(.5)},
        children: [
          pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: navy),
            children: ['الباقي', 'المدفوع', 'الإجمالي', 'التاريخ', report.type == 'sales' ? 'العميل / الحالة' : 'المورد / الحالة', 'رقم الفاتورة', 'م'].map((v) => cell(v, header: true)).toList()),
          for (var i = 0; i < report.rows.length; i++) pw.TableRow(children: [
            cell(movementReportMoney(report.rows[i].dueCents)), cell(movementReportMoney(report.rows[i].paidCents)),
            cell(movementReportMoney(report.rows[i].totalCents)),
            cell(DateFormat('dd/MM/yyyy').format(tz.TZDateTime.from(report.rows[i].date, tz.getLocation('Africa/Cairo')))),
            cell('${report.rows[i].customer}${report.rows[i].returned ? '\nمرتجعة بالكامل' : ''}', customer: true),
            cell(report.rows[i].number), cell('${i + 1}')]),
        ]),
      pw.SizedBox(height: 12),
      pw.Text('إجمالي الفواتير: ${movementReportMoney(report.totalCents)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.Text('مرتجعات الفترة: ${movementReportMoney(report.returnCents)} • صافي الحركة: ${movementReportMoney(report.netCents)}'),
      if(report.returns.isNotEmpty) ...[
        pw.SizedBox(height:12),pw.Text('تفاصيل مرتجعات الفترة',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),
        pw.Table(border:pw.TableBorder.all(color:accent,width:.5),children:[
          pw.TableRow(repeat:true,decoration:const pw.BoxDecoration(color:navy),
            children:['قيمة المرتجع','التاريخ',report.type=='sales' ? 'العميل' : 'المورد','الفاتورة الأصلية'].map((v)=>cell(v,header:true)).toList()),
          for(final r in report.returns)pw.TableRow(children:[
            cell(movementReportMoney(r.totalCents)),cell(movementReportDate(r.date)),cell(r.customer,customer:true),cell(r.number)]),
        ]),
      ],
      pw.SizedBox(height: 8), pw.Text(movementReportNote, style: const pw.TextStyle(fontSize: 9)),
    ]));
  return pdf.save();
}

class DebtReportRow {
  final String id, name;
  final int balanceCents;
  final bool inactive;
  const DebtReportRow(this.id, this.name, this.balanceCents, this.inactive);
}
class DebtReport {
  final List<DebtReportRow> rows;
  const DebtReport(this.rows);
  List<DebtReportRow> get debtors => rows.where((r) => r.balanceCents > 0).toList();
  List<DebtReportRow> get creditors => rows.where((r) => r.balanceCents < 0).toList();
  int get debtCents => debtors.fold(0, (v, r) => v + r.balanceCents);
  int get creditCents => creditors.fold(0, (v, r) => v - r.balanceCents);
}
DebtReport summarizeDebts(List<Map<String,dynamic>> accounts) {
  final rows = <DebtReportRow>[];
  for(final a in accounts) {
    final balance = a['balance'] ?? 0;
    if(balance is! num || !balance.isFinite) throw StateError('رصيد غير صحيح للحساب ${a['name'] ?? a['id']}');
    final cents = (balance * 100).round();
    if(cents == 0) continue;
    rows.add(DebtReportRow('${a['id'] ?? ''}', '${a['name'] ?? ''}'.trim().isEmpty ? 'حساب غير مسمى' : '${a['name']}',
      cents, a['active'] == false));
  }
  rows.sort((a,b) { final order = a.name.compareTo(b.name); return order == 0 ? a.id.compareTo(b.id) : order; });
  return DebtReport(List.unmodifiable(rows));
}
void openVibReport(BuildContext context, String title, Widget page) =>
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl,
    child: Theme(data:managerTheme(context),child:Scaffold(appBar:AppBar(title:Text(title)),body:SafeArea(child:page))))));

class DebtReportPage extends StatefulWidget {
  final bool suppliers;
  const DebtReportPage({super.key, required this.suppliers});
  @override State<DebtReportPage> createState() => _DebtReportPageState();
}
class _DebtReportPageState extends State<DebtReportPage> {
  late final Stream<QuerySnapshot<Map<String,dynamic>>> accounts;
  bool exporting = false;
  String get collection => widget.suppliers ? 'suppliers' : 'customers';
  String get title => widget.suppliers ? 'تقرير ذمم الموردين' : 'تقرير ذمم العملاء';
  @override void initState() { super.initState();accounts=db.collection(collection).snapshots(includeMetadataChanges:true); }
  Future<void> output() async {
    if(exporting)return;
    setState(()=>exporting=true);
    try {
      final snapshot=await db.collection(collection).get(const GetOptions(source:Source.server));
      if(snapshot.metadata.hasPendingWrites || snapshot.metadata.isFromCache) throw StateError('انتظر تأكيد الأرصدة من الخادم');
      final report=summarizeDebts(snapshot.docs.map((d)=><String,dynamic>{...d.data(),'id':d.id}).toList());
      final font=pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final bytes=await createDebtReportPdf(report,font,suppliers:widget.suppliers,asOf:DateTime.now());
      await Printing.sharePdf(bytes:bytes,filename:'VIB-${widget.suppliers ? 'SUPPLIERS' : 'CUSTOMERS'}-DEBTS-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.pdf');
    } catch(e) {if(mounted)await showInvoiceSaveProblem(context,'$e',title:'تعذر إرسال تقرير الذمم',button:'رجوع للتقرير');}
    finally {if(mounted)setState(()=>exporting=false);}
  }
  @override Widget build(BuildContext context)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:accounts,builder:(context,snapshot) {
    if(snapshot.hasError)return const Center(child:Text('تعذر تحميل تقرير الذمم؛ راجع الاتصال'));
    if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
    final DebtReport report;
    try { report=summarizeDebts(snapshot.data!.docs.map((d)=><String,dynamic>{...d.data(),'id':d.id}).toList()); }
    catch(e){return Center(child:Text('$e',textAlign:TextAlign.center));}
    final confirmed=!snapshot.data!.metadata.isFromCache && !snapshot.data!.metadata.hasPendingWrites;
    final debts=report.debtors, credits=report.creditors;
    return Column(children:[
      Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
        Text(widget.suppliers ? 'إجمالي الدين عليك للموردين' : 'إجمالي الدين على العملاء',
          style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
        Text(movementReportMoney(report.debtCents),style:const TextStyle(color:Colors.greenAccent,fontSize:24,fontWeight:FontWeight.bold)),
        Text('عدد أصحاب الدين: ${debts.length}'),
        Text('${widget.suppliers ? 'أرصدة لك عند الموردين' : 'أرصدة للعملاء عندك'}: ${movementReportMoney(report.creditCents)}'),
        const Text('الأرصدة الدائنة منفصلة ولا تقلل إجمالي الدين. التقرير للأرصدة الحالية وقت الإرسال.',textAlign:TextAlign.center,style:TextStyle(fontSize:12)),
        if(!confirmed)const Text('انتظر تأكيد الأرصدة من الخادم قبل الإرسال'),
      ]))),
      FilledButton.icon(onPressed:confirmed && !exporting ? output : null,
        icon:exporting ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.share),
        label:Text(exporting ? 'جاري تجهيز PDF…' : 'إرسال تقرير الذمم PDF / واتساب')),
      Expanded(child:ListView.builder(itemCount:debts.length + credits.length + 2,itemBuilder:(context,index) {
        if(index==0)return ListTile(title:Text(debts.isEmpty ? 'لا توجد ديون حالية' : 'أصحاب الدين',style:const TextStyle(color:gold,fontWeight:FontWeight.bold)));
        if(index<=debts.length) {
          final row=debts[index-1];
          return ListTile(leading:Text('$index'),title:Text(row.name,style:const TextStyle(color:Colors.greenAccent)),
            subtitle:row.inactive ? const Text('حساب غير نشط وله رصيد قائم') : null,
            trailing:Text(movementReportMoney(row.balanceCents)));
        }
        if(index==debts.length+1)return ListTile(title:Text(widget.suppliers ? 'أرصدة لك عند الموردين' : 'أرصدة للعملاء عندك',style:const TextStyle(color:gold,fontWeight:FontWeight.bold)));
        final row=credits[index-debts.length-2];
        return ListTile(title:Text(row.name),trailing:Text(movementReportMoney(-row.balanceCents)),
          subtitle:row.inactive ? const Text('حساب غير نشط وله رصيد قائم') : null);
      })),
    ]);
  });
}
Future<Uint8List> createDebtReportPdf(DebtReport report,pw.Font font,{required bool suppliers,required DateTime asOf}) async {
  final pdf=pw.Document();
  const navy=PdfColor.fromInt(0xFF14263D),accent=PdfColor.fromInt(0xFFB58A38);
  pw.Widget cell(String v,{bool header=false})=>pw.Padding(padding:const pw.EdgeInsets.all(6),
    child:pw.Text(v,textAlign:pw.TextAlign.right,style:pw.TextStyle(fontSize:10,color:header ? PdfColors.white : PdfColors.black)));
  pw.Widget table(List<DebtReportRow> rows,{bool credit=false})=>pw.Table(
    border:pw.TableBorder.all(color:accent,width:.5),columnWidths:{0:const pw.FlexColumnWidth(2),1:const pw.FlexColumnWidth(5),2:const pw.FlexColumnWidth(.5)},
    children:[
      pw.TableRow(repeat:true,decoration:const pw.BoxDecoration(color:navy),children:[credit ? 'الرصيد الدائن' : 'الدين',suppliers ? 'المورد' : 'العميل','م'].map((v)=>cell(v,header:true)).toList()),
      for(var i=0;i<rows.length;i++)pw.TableRow(children:[cell(movementReportMoney(credit ? -rows[i].balanceCents : rows[i].balanceCents)),
        cell('${rows[i].name}${rows[i].inactive ? ' (غير نشط)' : ''}'),cell('${i+1}')]),
    ]);
  pdf.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,maxPages:1000,
    theme:pw.ThemeData.withFont(base:font,bold:font),textDirection:pw.TextDirection.rtl,
    footer:(c)=>pw.Text('${c.pageNumber} / ${c.pagesCount}',textAlign:pw.TextAlign.center),
    build:(_)=>[
      pw.Center(child:pw.Text('VIB للتجارة والتوزيع',textAlign:pw.TextAlign.center,style:pw.TextStyle(fontSize:22,color:navy))),
      pw.SizedBox(height:10),pw.Center(child:pw.Text(suppliers ? 'تقرير ذمم الموردين' : 'تقرير ذمم العملاء',textAlign:pw.TextAlign.center,style:pw.TextStyle(fontSize:18))),
      pw.Text('الأرصدة الحالية حتى ${movementReportDate(asOf)} • توقيت القاهرة'),
      pw.Text('${suppliers ? 'إجمالي الدين عليك للموردين' : 'إجمالي الدين على العملاء'}: ${movementReportMoney(report.debtCents)}',
        style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:14)),
      pw.Text('عدد أصحاب الدين: ${report.debtors.length}'),pw.SizedBox(height:12),
      if(report.debtors.isNotEmpty)table(report.debtors)else pw.Text('لا توجد ديون حالية'),
      pw.SizedBox(height:10),pw.Text('إجمالي الدين: ${movementReportMoney(report.debtCents)}',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),
      pw.SizedBox(height:14),pw.Text('${suppliers ? 'أرصدة لك عند الموردين' : 'أرصدة للعملاء عندك'}: ${movementReportMoney(report.creditCents)}'),
      if(report.creditors.isNotEmpty)table(report.creditors,credit:true),
      pw.SizedBox(height:10),pw.Text('الأرصدة الدائنة معروضة منفصلة ولا تخصم من إجمالي الدين. يشمل التقرير الحسابات غير النشطة ذات الرصيد القائم.'),
    ]));
  return pdf.save();
}

class InvoiceOverviewContent extends StatelessWidget {
  final String type, id;
  final Map<String,dynamic> data;
  const InvoiceOverviewContent({super.key,required this.type,required this.id,required this.data});
  @override Widget build(BuildContext context) {
    final sales=type=='sales';
    final name='${data[sales ? 'customerName' : 'supplierName'] ?? ''}'.trim();
    final items=((data['items'] as List?) ?? []).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
    if(items.isEmpty)items.add({'productName':data['productName'] ?? '', 'quantity':data['quantity'] ?? 0,
      sales ? 'unitPrice' : 'unitCost':data[sales ? 'unitPrice' : 'unitCost'] ?? 0,'lineTotal':data['total'] ?? 0});
    String money(dynamic v)=>((v as num?) ?? 0).toStringAsFixed(2);
    final paid=(data['paid'] as num?) ?? (sales ? (data['total'] as num?) ?? 0 : 0);
    final receipt=(data['receiptPaid'] as num?) ?? 0;
    final due=(data['due'] as num?) ?? ((data['total'] as num?) ?? 0)-paid;
    return ListView(shrinkWrap:true,children:[
      Text(name.isEmpty ? (sales ? 'بدون عميل مسجل' : 'مورد غير مسمى') : name,
        style:const TextStyle(color:Colors.greenAccent,fontWeight:FontWeight.bold,fontSize:18)),
      Text('رقم الفاتورة: ${invoiceDisplayNumber(type,id,data)}'),
      Text(formatDate(data['createdAt'])),
      for(var i=0;i<items.length;i++)Card(child:Padding(padding:const EdgeInsets.all(10),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text('${i+1}. ${items[i]['productName'] ?? ''}',style:const TextStyle(fontWeight:FontWeight.bold)),
          Text('العدد: ${items[i]['quantity'] ?? 0} • السعر: ${money(items[i][sales ? 'unitPrice' : 'unitCost'])}'),
          Text('إجمالي البند: ${money(items[i]['lineTotal'] ?? (((items[i]['quantity'] as num?) ?? 0) * ((items[i][sales ? 'unitPrice' : 'unitCost'] as num?) ?? 0)))} ج.م'),
        ]))),
      Text('الإجمالي: ${money(data['total'])} ج.م',style:const TextStyle(color:gold,fontWeight:FontWeight.bold)),
      Text('المدفوع مع السداد المرتبط: ${money(paid+receipt)} ج.م'),
      Text(data['status']=='returned' ? 'الفاتورة مرتجعة بالكامل' : 'باقي الفاتورة: ${money(due-receipt)} ج.م'),
    ]);
  }
}
Future<void> showInvoiceOverview(BuildContext context,String type,String id) async {
  try {
    final row=await db.collection(type).doc(id).get(const GetOptions(source:Source.server));
    if(!row.exists || !visibleAfterReset(row.data()!))throw StateError('الفاتورة غير متاحة');
    if(row.metadata.hasPendingWrites)throw StateError('انتظر تأكيد الفاتورة من الخادم');
    final data=await numberedInvoiceData(type,id,row.data()!);
    if(!context.mounted)return;
    final choice=await showDialog<String>(context:context,builder:(c)=>Directionality(textDirection:TextDirection.rtl,
      child:AlertDialog(title:Text(type=='sales' ? 'تفاصيل فاتورة المبيعات' : 'تفاصيل فاتورة المشتريات'),
        content:SizedBox(width:540,height:MediaQuery.sizeOf(c).height*.55,
          child:InvoiceOverviewContent(type:type,id:id,data:data)),
        actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق')),
          FilledButton.icon(onPressed:()=>Navigator.pop(c,'share'),icon:const Icon(Icons.share),label:const Text('إرسال PDF'))])));
    if(choice=='share' && context.mounted)await exportInvoicePdf(context,type,id,data);
  } catch(e){if(context.mounted)await showInvoiceSaveProblem(context,'$e',title:'تعذر عرض الفاتورة',button:'رجوع');}
}

