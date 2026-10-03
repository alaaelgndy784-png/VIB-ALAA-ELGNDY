part of 'main.dart';

class InvoiceHistoryPage extends StatefulWidget {
  final String type;
  const InvoiceHistoryPage({super.key, required this.type});
  @override State<InvoiceHistoryPage> createState() => _InvoiceHistoryPageState();
}

class _InvoiceHistoryPageState extends State<InvoiceHistoryPage> {
  late DateTime day;
  late Stream<QuerySnapshot<Map<String, dynamic>>> invoices;
  bool get sales => widget.type == 'sales';
  @override void initState() {
    super.initState();
    selectDay(DateTime.now());
  }
  void selectDay(DateTime date) {
    day = DateTime(date.year, date.month, date.day);
    final nextDay = DateTime(day.year, day.month, day.day + 1);
    invoices = db.collection(widget.type)
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(day))
      .where('createdAt', isLessThan: Timestamp.fromDate(nextDay))
      .orderBy('createdAt', descending: true).snapshots();
  }
  Future<void> pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: day,
      firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (picked != null && mounted) setState(() => selectDay(picked));
  }
  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(onPressed: pickDate, icon: const Icon(Icons.calendar_month), label: const Text('اختيار التاريخ')),
      TextButton.icon(onPressed: () => setState(() => selectDay(DateTime.now())),
        icon: const Icon(Icons.today), label: const Text('فواتير اليوم')),
    ])),
    Text('فواتير ${sales ? 'المبيعات' : 'المشتريات'} • ${DateFormat('dd/MM/yyyy').format(day)}',
      style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: invoices, builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('تعذر تحميل الفواتير؛ راجع اتصال الإنترنت وحاول مرة أخرى'));
      if (!snapshot.hasData || snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data!.docs.where((row) => visibleAfterReset(row.data())).toList();
      if (rows.isEmpty) return const Center(child: Text('لا توجد فواتير في هذا التاريخ'));
      return Column(children: [
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('عدد الفواتير: ${rows.length}')),
        Expanded(child: ListView.builder(itemCount: rows.length, itemBuilder: (context, index) {
          final row = rows[index], data = row.data();
          final number = '${data['invoiceNumber'] ?? ''}'.trim();
          final party = '${data[sales ? 'customerName' : 'supplierName'] ?? ''}'.trim();
          final total = ((data['total'] as num?) ?? 0).toStringAsFixed(2);
          final returned = data['status'] == 'returned';
          return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ListTile(
            leading: CircleAvatar(radius: 15, child: Text('${index + 1}', style: const TextStyle(fontSize: 12))),
            title: Text('فاتورة ${number.isEmpty ? row.id : number}${party.isEmpty ? '' : '\n$party'}'),
            subtitle: Text('${formatDate(data['createdAt'])}${sales ? ' • فرع: ${data['branchId'] ?? ''}' : ''}${returned ? '\nفاتورة مرتجعة' : ''}'),
            trailing: Text('$total ج.م', style: TextStyle(color: returned ? Colors.redAccent : gold, fontWeight: FontWeight.bold)),
            onTap: () => invoiceActions(context, widget.type, row.id, data),
          ));
        })),
      ]);
    })),
  ]);
}
