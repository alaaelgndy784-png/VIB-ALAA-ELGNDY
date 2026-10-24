part of 'main.dart';

class InvoiceHistoryPage extends StatefulWidget {
  final String type;
  const InvoiceHistoryPage({super.key, required this.type});
  @override State<InvoiceHistoryPage> createState() => _InvoiceHistoryPageState();
}

class _InvoiceHistoryPageState extends State<InvoiceHistoryPage> with WidgetsBindingObserver {
  late DateTime from, to;
  bool numbering=false;String numberError='';
  bool _showYesterdayAndToday = true;
  Timer? _dayRolloverTimer;
  late Stream<QuerySnapshot<Map<String, dynamic>>> invoices;
  final TextEditingController partySearchController = TextEditingController();
  bool _searchingByParty = false;
  String _partySearchError = '';
  bool get sales => widget.type == 'sales';

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    selectRange(DateTime(now.year, now.month, now.day - 1), DateTime(now.year, now.month, now.day), includeYesterday: true);
    _scheduleDayRollover();
    // Numbering is a background server task, never a condition for reading cached invoices.
    unawaited(prepareInvoiceSerials(widget.type).catchError((Object e) {
      if(mounted && !isTemporaryFirestoreOffline(e))setState(()=>numberError='تعذر تجهيز أرقام الفواتير: $e');
    }));
  }

  @override void dispose() {
    _dayRolloverTimer?.cancel();
    partySearchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final now = DateTime.now();
    if (_searchingByParty) {
      setState(() {});
      return;
    }
    if (_showYesterdayAndToday && !_sameDay(to, now)) {
      setState(() => selectRange(DateTime(now.year, now.month, now.day - 1), DateTime(now.year, now.month, now.day), includeYesterday: true));
    } else {
      // Rebuild so the selected day's color is recalculated after returning to the app.
      setState(() {});
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _scheduleDayRollover() {
    _dayRolloverTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _dayRolloverTimer = Timer(
      nextMidnight.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        final today = DateTime.now();
        setState(() {
          if (_showYesterdayAndToday && !_searchingByParty) {
            selectRange(DateTime(today.year, today.month, today.day - 1), today, includeYesterday: true);
          }
          // For a manually chosen date, rebuild to refresh its today/yesterday color.
        });
        _scheduleDayRollover();
      },
    );
  }

  Color _invoiceDayColor(Map<String, dynamic> data) {
    final rawDate = data['createdAt'];
    final createdAt = rawDate is Timestamp
        ? rawDate.toDate()
        : rawDate is DateTime
            ? rawDate
            : null;
    if (createdAt == null) return gold;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final invoiceDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
    if (_sameDay(invoiceDay, today)) return Colors.greenAccent;
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    if (_sameDay(invoiceDay, yesterday)) return Colors.redAccent;
    return gold;
  }

  void _setDateRangeStream() {
    final fromDay = movementReportBoundary(from);
    final nextDay = movementReportBoundary(to, next: true);
    invoices = db.collection(widget.type)
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(fromDay))
      .where('createdAt', isLessThan: Timestamp.fromDate(nextDay))
      .orderBy('createdAt', descending: true).snapshots();
  }

  void selectRange(DateTime start, DateTime end, {bool includeYesterday = false}) {
    from = DateTime(start.year, start.month, start.day);
    to = DateTime(end.year, end.month, end.day);
    _showYesterdayAndToday = includeYesterday;
    _searchingByParty = false;
    _partySearchError = '';
    partySearchController.clear();
    _setDateRangeStream();
  }

  void searchByParty() {
    final prefix = partySearchController.text.trim();
    if (prefix.isEmpty) {
      setState(() => _partySearchError = 'اكتب بداية اسم العميل أو المورد للبحث.');
      return;
    }
    if (prefix.length < 2) {
      setState(() => _partySearchError = 'اكتب أول حرفين من الاسم على الأقل لتضييق البحث.');
      return;
    }
    final field = sales ? 'customerName' : 'supplierName';
    setState(() {
      _searchingByParty = true;
      _partySearchError = '';
      invoices = db.collection(widget.type)
        .orderBy(field)
        .startAt([prefix])
        .endAt(['${prefix}${String.fromCharCode(0xF8FF)}'])
        .snapshots();
    });
  }

  void clearPartySearch() {
    setState(() {
      partySearchController.clear();
      _searchingByParty = false;
      _partySearchError = '';
      _setDateRangeStream();
    });
  }

  Widget _legend(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
  ]);

  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(children: [
        Expanded(child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34), visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            textStyle: const TextStyle(fontSize: 12)),
          onPressed: () => openVibReport(context, sales ? 'تقرير حركة المبيعات' : 'تقرير حركة المشتريات',
            InvoiceMovementReportPage(type:widget.type)),
          icon: const Icon(Icons.summarize_outlined, size: 15),
          label: const Text('تقرير الحركة', maxLines: 1, overflow: TextOverflow.ellipsis))),
        const SizedBox(width: 6),
        Expanded(child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            textStyle: const TextStyle(fontSize: 12)),
          onPressed: () { final now = DateTime.now();
            setState(() => selectRange(DateTime(now.year, now.month, now.day - 1),
              DateTime(now.year, now.month, now.day), includeYesterday:true)); },
          icon: const Icon(Icons.today, size: 15), label: const Text('اليوم وأمس', maxLines: 1))),
      ])),
    Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 4), child: Row(children: [
      Expanded(child: TextField(
        controller: partySearchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'بحث باسم ${sales ? 'العميل' : 'المورد'}',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          prefixIcon: const Icon(Icons.search, size: 19),
        ),
        onSubmitted: (_) => searchByParty(),
      )),
      const SizedBox(width: 8),
      SizedBox(height: 35, child: FilledButton.icon(
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 9),
          visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
        onPressed: searchByParty, icon: const Icon(Icons.search, size: 15),
        label: const Text('بحث'))),
      if (_searchingByParty) IconButton(tooltip: 'مسح البحث', onPressed: clearPartySearch, icon: const Icon(Icons.close)),
    ])),
    MovementPeriodControls(key:ValueKey('${from.toIso8601String()}-${to.toIso8601String()}'),from:from,to:to,enabled:true,compact:true,onConfirm:(start,end)=>setState(()=>selectRange(start,end))),
    if (_partySearchError.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(_partySearchError, style: const TextStyle(color: Colors.redAccent))),
    const SizedBox(height: 3),
    if(numbering)const Padding(padding:EdgeInsets.all(8),child:Text('جاري تجهيز الأرقام الثابتة للفواتير القديمة...')),
    if(numberError.isNotEmpty)Text(numberError,style:const TextStyle(color:Colors.redAccent)),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: invoices, builder: (context, snapshot) {
      if(numbering)return const Center(child:CircularProgressIndicator());
      if (snapshot.hasError && !snapshot.hasData) return const Center(child: Text('تعذر تحميل الفواتير؛ راجع اتصال الإنترنت وحاول مرة أخرى'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data!.docs.where((row) => visibleAfterReset(row.data())).toList();
      if (_searchingByParty) {
        rows.sort((a, b) {
          final rawA = a.data()['createdAt'], rawB = b.data()['createdAt'];
          final timeA = rawA is Timestamp ? rawA.millisecondsSinceEpoch : rawA is DateTime ? rawA.millisecondsSinceEpoch : 0;
          final timeB = rawB is Timestamp ? rawB.millisecondsSinceEpoch : rawB is DateTime ? rawB.millisecondsSinceEpoch : 0;
          return timeB.compareTo(timeA);
        });
      }
      final totalCents=rows.fold<int>(0,(sum,row){final value=row.data()['total'];if(value is! num || !value.isFinite)return sum;return sum+(value*100).round();});
      return Column(children: [
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('الفواتير: ${rows.length} • الإجمالي: ${movementReportMoney(totalCents)}',
          style: const TextStyle(color: gold, fontSize: 13, fontWeight: FontWeight.bold))),
        Expanded(child: rows.isEmpty ? const Center(child:Text('لا توجد فواتير في الفترة المختارة')) : ListView.builder(itemCount: rows.length, itemBuilder: (context, index) {
          final row = rows[index], data = row.data();
          final dayColor = _invoiceDayColor(data);
          final number=invoiceDisplayNumber(widget.type,row.id,data);
          final party = '${data[sales ? 'customerName' : 'supplierName'] ?? ''}'.trim();
          final total = ((data['total'] as num?) ?? 0).toStringAsFixed(2);
          final returned = data['status'] == 'returned';
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: dayColor.withOpacity(0.14),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: dayColor.withOpacity(0.9), width: 1.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Icon(Icons.receipt_long_outlined,color:dayColor),
              title: FutureBuilder<Map<String,dynamic>>(future: data['internalNumber'] is int || invoiceSerialCache.containsKey(serialKey(widget.type,row.id)) ? null : ensureInvoiceSerial(widget.type,row.id),builder:(context,serial)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(party.isEmpty ? (sales ? 'بدون عميل مسجل' : 'مورد غير مسمى') : party,
                  style:TextStyle(color:dayColor,fontWeight:FontWeight.bold,fontSize:16)),
                Text('رقم الفاتورة: ${invoiceDisplayNumber(widget.type,row.id,data)}'),
              ])),
              subtitle: Text('${formatDate(data['createdAt'])}${sales ? ' • فرع: ${data['branchId'] ?? ''}' : ''}${returned ? '\nفاتورة مرتجعة' : ''}'),
              trailing: Text('$total ج.م', style: TextStyle(color: returned ? Colors.redAccent : dayColor, fontWeight: FontWeight.bold)),
              onTap: () => showInvoiceOverview(context, widget.type, row.id, initialData: data),
            ),
          );
        })),
      ]);
    })),
  ]);
}
