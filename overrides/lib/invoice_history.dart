part of 'main.dart';

class InvoiceHistoryPage extends StatefulWidget {
  final String type;
  const InvoiceHistoryPage({super.key, required this.type});
  @override State<InvoiceHistoryPage> createState() => _InvoiceHistoryPageState();
}

class _InvoiceHistoryPageState extends State<InvoiceHistoryPage> with WidgetsBindingObserver {
  late DateTime day;
  bool numbering=true;String numberError='';
  bool _showYesterdayAndToday = true;
  Timer? _dayRolloverTimer;
  late Stream<QuerySnapshot<Map<String, dynamic>>> invoices;
  bool get sales => widget.type == 'sales';

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    selectDay(DateTime.now(), includeYesterday: true);
    _scheduleDayRollover();
    prepareInvoiceSerials(widget.type).then((_){if(mounted)setState(()=>numbering=false);}).catchError((Object e){if(mounted)setState((){numbering=false;numberError='تعذر تجهيز أرقام الفواتير: $e';});});
  }

  @override void dispose() {
    _dayRolloverTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final now = DateTime.now();
    if (_showYesterdayAndToday && !_sameDay(day, now)) {
      setState(() => selectDay(now, includeYesterday: true));
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
          if (_showYesterdayAndToday) {
            selectDay(today, includeYesterday: true);
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

  void selectDay(DateTime date, {bool includeYesterday = false}) {
    day = DateTime(date.year, date.month, date.day);
    _showYesterdayAndToday = includeYesterday;
    final fromDay = includeYesterday
        ? DateTime(day.year, day.month, day.day - 1)
        : day;
    final nextDay = DateTime(day.year, day.month, day.day + 1);
    invoices = db.collection(widget.type)
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(fromDay))
      .where('createdAt', isLessThan: Timestamp.fromDate(nextDay))
      .orderBy('createdAt', descending: true).snapshots();
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: day,
      firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (picked != null && mounted) setState(() => selectDay(picked));
  }

  Widget _legend(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
  ]);

  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(onPressed: () => openVibReport(context, sales ? 'تقرير حركة المبيعات' : 'تقرير حركة المشتريات',
        InvoiceMovementReportPage(type:widget.type)), icon:const Icon(Icons.summarize_outlined),label:Text(sales ? 'تقرير حركة المبيعات' : 'تقرير حركة المشتريات')),
      OutlinedButton.icon(onPressed: pickDate, icon: const Icon(Icons.calendar_month), label: const Text('اختيار التاريخ')),
      TextButton.icon(onPressed: () => setState(() => selectDay(DateTime.now(), includeYesterday: true)),
        icon: const Icon(Icons.today), label: const Text('فواتير اليوم')),
    ])),
    Text(_showYesterdayAndToday
        ? 'فواتير ${sales ? 'المبيعات' : 'المشتريات'} • امبارح واليوم'
        : 'فواتير ${sales ? 'المبيعات' : 'المشتريات'} • ${DateFormat('dd/MM/yyyy').format(day)}',
      style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
    if (_showYesterdayAndToday)
      Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: Wrap(spacing: 16, children: [
        _legend(Colors.greenAccent, 'النهارده'),
        _legend(Colors.redAccent, 'امبارح'),
      ])),
    const SizedBox(height: 8),
    if(numbering)const Padding(padding:EdgeInsets.all(8),child:Text('جاري تجهيز الأرقام الثابتة للفواتير القديمة...')),
    if(numberError.isNotEmpty)Text(numberError,style:const TextStyle(color:Colors.redAccent)),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: invoices, builder: (context, snapshot) {
      if(numbering)return const Center(child:CircularProgressIndicator());
      if (snapshot.hasError) return const Center(child: Text('تعذر تحميل الفواتير؛ راجع اتصال الإنترنت وحاول مرة أخرى'));
      if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data!.docs.where((row) => visibleAfterReset(row.data())).toList();
      if (rows.isEmpty) return const Center(child: Text('لا توجد فواتير في هذا التاريخ'));
      return Column(children: [
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('عدد الفواتير: ${rows.length}')),
        Expanded(child: ListView.builder(itemCount: rows.length, itemBuilder: (context, index) {
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
              onTap: () => invoiceActions(context, widget.type, row.id, data),
            ),
          );
        })),
      ]);
    })),
  ]);
}
