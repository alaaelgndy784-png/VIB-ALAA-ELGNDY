part of 'main.dart';

// Read-only invoice line tracing. Historical grouped invoices and older single-
// item invoices are both supported. No inventory, balance or invoice writes.
String vibInvoiceProductSearchText(String value) => invoiceSearchText(value);

List<Map<String, dynamic>> vibInvoiceProductLines(Map<String, dynamic> invoice) {
  final raw = invoice['items'];
  if (raw is List && raw.isNotEmpty) {
    return raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }
  if (invoice['productId'] == null && invoice['productName'] == null) {
    return const [];
  }
  return [<String, dynamic>{
    'productId': invoice['productId'],
    'productName': invoice['productName'],
    'quantity': invoice['quantity'] ?? 0,
    'unitPrice': invoice['unitPrice'] ?? 0,
    'unitCost': invoice['unitCost'] ?? 0,
    'lineTotal': invoice['lineTotal'] ?? invoice['total'] ?? 0,
  }];
}

bool vibInvoiceLineMatchesProduct(Map<String, dynamic> line, {
  required String keyword,
  String? selectedProductId,
  String selectedProductName = '',
}) {
  final id = (line['productId'] ?? '').toString().trim();
  final name = vibInvoiceProductSearchText((line['productName'] ?? '').toString());
  final query = vibInvoiceProductSearchText(keyword);
  if (selectedProductId != null && selectedProductId.isNotEmpty) {
    if (id.isNotEmpty && id != 'null') return id == selectedProductId;
    final oldName = vibInvoiceProductSearchText(selectedProductName);
    // Match legacy name-only invoices precisely, never by a similar substring.
    return oldName.isNotEmpty && name == oldName;
  }
  return query.isNotEmpty &&
      (name.contains(query) || id.toLowerCase().contains(keyword.trim().toLowerCase()));
}

List<Map<String, dynamic>> vibMatchingInvoiceProductLines(
  Map<String, dynamic> invoice, {
  required String keyword,
  String? selectedProductId,
  String selectedProductName = '',
}) => vibInvoiceProductLines(invoice).where((row) => vibInvoiceLineMatchesProduct(
      row, keyword: keyword, selectedProductId: selectedProductId,
      selectedProductName: selectedProductName)).toList();

double vibInvoiceLineNumber(dynamic value) {
  if (value is num) return value.isFinite ? value.toDouble() : 0;
  return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
}

class VibProductInvoiceHit {
  final String id, number, party, type;
  final DateTime? date;
  final Map<String, dynamic> invoice, item;
  const VibProductInvoiceHit({required this.id, required this.number, required this.party,
    required this.type, required this.date, required this.invoice, required this.item});
  double get quantity => vibInvoiceLineNumber(item['quantity']);
  double get price => vibInvoiceLineNumber(item[type == 'sales' ? 'unitPrice' : 'unitCost']);
  double get total => item['lineTotal'] == null
      ? quantity * price : vibInvoiceLineNumber(item['lineTotal']);
}

class ProductInvoiceMovementPage extends StatefulWidget {
  final String type;
  const ProductInvoiceMovementPage({super.key, required this.type});
  @override State<ProductInvoiceMovementPage> createState() => _ProductInvoiceMovementPageState();
}

class _ProductInvoiceMovementPageState extends State<ProductInvoiceMovementPage> {
  final TextEditingController _search = TextEditingController();
  String? _productId;
  String _productName = '';
  bool _allDates = true, _loading = false, _complete = false;
  int _generation = 0, _readCount = 0;
  String _error = '';
  List<VibProductInvoiceHit> _hits = [];
  late DateTime _from, _to;

  bool get _sales => widget.type == 'sales';

  @override void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
  }

  @override void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _selectProduct() async {
    final filter = TextEditingController();
    final chosen = await showModalBottomSheet<MapEntry<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, refresh) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
          child: SizedBox(height: MediaQuery.sizeOf(sheet).height * .7,
            child: Column(children: [
              const Padding(padding: EdgeInsets.all(10),
                child: Text('اختيار صنف من المخزون', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                child: TextField(controller: filter,
                  decoration: const InputDecoration(labelText: 'بحث بالاسم أو الكود',
                    prefixIcon: Icon(Icons.search)),
                  onChanged: (_) => refresh(() {}))),
              Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db.collection('products').snapshots(),
                builder: (sheet, snap) {
                  if (snap.hasError) return const Center(child: Text('تعذر قراءة سجل الأصناف'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final text = vibInvoiceProductSearchText(filter.text);
                  final products = snap.data!.docs.where((p) {
                    final name = (p.data()['name'] ?? '').toString();
                    return vibInvoiceProductSearchText(name).contains(text) ||
                        p.id.toLowerCase().contains(filter.text.trim().toLowerCase());
                  }).toList()..sort((a, b) =>
                    (a.data()['name'] ?? '').toString().compareTo(
                      (b.data()['name'] ?? '').toString()));
                  if (products.isEmpty) return const Center(child:
                    Text('الصنف غير موجود هنا؛ ارجع وابحث بالاسم المكتوب في الفاتورة القديمة'));
                  return ListView.builder(itemCount: products.length, itemBuilder: (sheet, index) {
                    final p = products[index];
                    final name = (p.data()['name'] ?? p.id).toString();
                    return ListTile(
                      title: Text(name, maxLines: 2),
                      subtitle: Text('كود الصنف: ' + p.id),
                      onTap: () => Navigator.pop(sheet, MapEntry(p.id, name)));
                  });
                },
              )),
            ]),
          ),
        ),
      )),
    );
    filter.dispose();
    if (chosen != null && mounted) setState(() {
      _productId = chosen.key;
      _productName = chosen.value;
      _search.text = chosen.value;
      _complete = false;
      _hits = [];
    });
  }

  Future<void> _findInvoices() async {
    final keyword = _search.text.trim();
    final selectedId = _productId;
    final selectedName = _productName;
    if (keyword.isEmpty && selectedId == null) {
      setState(() => _error = 'اختار الصنف أو اكتب اسمه أو كوده الأول.');
      return;
    }
    final version = ++_generation;
    final allDates = _allDates;
    final from = _from, to = _to;
    setState(() {
      _loading = true; _complete = false; _readCount = 0;
      _hits = []; _error = '';
    });
    final matches = <VibProductInvoiceHit>[];
    DocumentSnapshot<Map<String, dynamic>>? last;
    try {
      Query<Map<String, dynamic>> query;
      if (allDates) {
        // Document-ID paging also finds older invoices without createdAt.
        query = db.collection(widget.type).orderBy(FieldPath.documentId).limit(150);
      } else {
        query = db.collection(widget.type)
            .where('createdAt', isGreaterThanOrEqualTo:
                Timestamp.fromDate(movementReportBoundary(from)))
            .where('createdAt', isLessThan:
                Timestamp.fromDate(movementReportBoundary(to, next: true)))
            .orderBy('createdAt', descending: true).limit(150);
      }
      while (true) {
        final page = await (last == null ? query : query.startAfterDocument(last))
            .get(const GetOptions(source: Source.server));
        if (!mounted || version != _generation) return;
        if (page.metadata.isFromCache || page.metadata.hasPendingWrites) {
          throw StateError('البيانات غير متزامنة؛ اتصل بالإنترنت لإكمال البحث في الفواتير القديمة');
        }
        for (final doc in page.docs) {
          final invoice = doc.data();
          final timestamp = invoice['createdAt'];
          final date = timestamp is Timestamp ? timestamp.toDate()
              : timestamp is DateTime ? timestamp : null;
          final rows = vibMatchingInvoiceProductLines(invoice,
              keyword: keyword, selectedProductId: selectedId,
              selectedProductName: selectedName);
          for (final item in rows) {
            matches.add(VibProductInvoiceHit(
              id: doc.id, number: invoiceDisplayNumber(widget.type, doc.id, invoice),
              party: (invoice[_sales ? 'customerName' : 'supplierName'] ?? 'غير مسجل').toString(),
              type: widget.type, date: date, invoice: invoice, item: item));
          }
        }
        matches.sort((a, b) => (b.date?.millisecondsSinceEpoch ?? 0)
            .compareTo(a.date?.millisecondsSinceEpoch ?? 0));
        setState(() {
          _readCount += page.docs.length;
          _hits = List.of(matches);
        });
        if (page.docs.length < 150) break;
        last = page.docs.last;
      }
      if (mounted && version == _generation) {
        setState(() { _loading = false; _complete = true; });
      }
    } catch (e) {
      if (mounted && version == _generation) setState(() {
        _loading = false;
        _complete = false;
        _error = 'لم يكتمل فحص كل الفواتير: ' + e.toString() +
            '. النتائج الظاهرة جزئية، وليست تأكيدًا بعدم وجود الفاتورة.';
      });
    }
  }

  @override Widget build(BuildContext context) {
    final uniqueInvoices = _hits.map((h) => h.id).toSet().length;
    final totalQty = _hits.fold<double>(0, (sum, h) => sum + h.quantity);
    final totalValue = _hits.fold<double>(0, (sum, h) => sum + h.total);
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 3),
        child: Row(children: [
          Expanded(child: TextField(controller: _search, enabled: !_loading,
            decoration: const InputDecoration(
              labelText: 'اسم الصنف أو كوده في الفاتورة',
              prefixIcon: Icon(Icons.inventory_2_outlined),
              isDense: true),
            onChanged: (_) {
              setState(() { _productId = null; _productName = ''; _complete = false; _hits = []; });
            },
            onSubmitted: (_) => _findInvoices())),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: _loading ? null : _selectProduct,
            child: const Text('اختيار صنف')),
        ])),
      CheckboxListTile(
        dense: true,
        title: const Text('البحث في كل الفواتير من أول التسجيل'),
        subtitle: const Text('يمكن تضييق الفترة لتسريع البحث وتقليل قراءة البيانات',
          style: TextStyle(fontSize: 11)),
        value: _allDates,
        onChanged: _loading ? null : (value) => setState(() {
          _allDates = value ?? true; _complete = false; _hits = [];
        })),
      if (!_allDates) MovementPeriodControls(
        key: ValueKey(_from.toIso8601String() + _to.toIso8601String()),
        from: _from, to: _to, compact: true, enabled: !_loading,
        onConfirm: (from, to) => setState(() { _from = from; _to = to; _complete = false; _hits = []; })),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _loading ? () => setState(() {
            ++_generation; _loading = false; _complete = false;
            _error = 'تم إيقاف الفحص، النتائج المعروضة جزئية فقط.';
          }) : _findInvoices,
          icon: Icon(_loading ? Icons.stop_circle_outlined : Icons.search),
          label: Text(_loading ? 'إيقاف الفحص' : 'بحث عن كل فواتير الصنف')))),
      if (_loading) const LinearProgressIndicator(),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text('تم فحص ' + _readCount.toString() + ' فاتورة' +
          (_complete ? ' بالكامل' : ' • الفحص غير مكتمل') +
          ' • فواتير مطابقة: ' + uniqueInvoices.toString(),
          style: const TextStyle(color: gold, fontSize: 12))),
      if (_complete && _hits.isNotEmpty)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Text('كمية البنود بالفواتير: ' + totalQty.toStringAsFixed(0) +
            ' • قيمتها: ' + totalValue.toStringAsFixed(2) +
            ' ج.م (قبل خصم المرتجعات والإلغاءات)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
      if (_error.isNotEmpty) Padding(padding: const EdgeInsets.all(8),
        child: Text(_error, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
      Expanded(child: _hits.isEmpty ? Center(child: Text(_complete
          ? 'مفيش فاتورة فيها الصنف ده في الفترة المختارة'
          : _loading ? 'جاري البحث بين بنود الفواتير القديمة...'
          : 'اختار صنف واضغط بحث. التقرير يفتح أصل الفاتورة، مش بس حركة المخزن.'))
        : ListView.builder(itemCount: _hits.length, itemBuilder: (context, index) {
          final hit = _hits[index];
          final status = (hit.invoice['status'] ?? '').toString();
          final statusText = status == 'cancelled' ? ' • ملغاة'
              : status == 'returned' ? ' • مرتجعة' : '';
          return Card(child: ListTile(
            title: Text('فاتورة ' + hit.number + statusText,
              style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
            subtitle: Text(
              (hit.date == null ? 'تاريخ غير مسجل' :
                DateFormat('dd/MM/yyyy HH:mm').format(hit.date!)) +
              ' • ' + (_sales ? 'العميل: ' : 'المورد: ') + hit.party +
              '\nالصنف: ' + (hit.item['productName'] ?? '').toString() +
              ' • الكمية: ' + hit.quantity.toStringAsFixed(0) +
              '\nسعر الوحدة: ' + hit.price.toStringAsFixed(2) +
              ' • إجمالي البند: ' + hit.total.toStringAsFixed(2) + ' ج.م'),
            trailing: const Icon(Icons.open_in_new, size: 19),
            onTap: () => showInvoiceOverview(context, widget.type, hit.id,
              initialData: hit.invoice),
          ));
        })),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text('التقرير للبحث عن الفواتير الأصلية، ويعرض قيم البنود وقت التسجيل. لا يغير المخزون أو الحسابات.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.white70))),
    ]);
  }
}
