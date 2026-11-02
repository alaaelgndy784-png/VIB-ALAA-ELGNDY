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
  final String? initialProductId;
  final String initialProductName;
  const ProductInvoiceMovementPage({super.key, required this.type,
    this.initialProductId, this.initialProductName = ''});
  @override State<ProductInvoiceMovementPage> createState() => _ProductInvoiceMovementPageState();
}

class _ProductInvoiceMovementPageState extends State<ProductInvoiceMovementPage> {
  final TextEditingController _search = TextEditingController();
  String? _productId;
  String _productName = '';
  bool _allDates = true, _loading = false, _complete = false, _exporting = false;
  int _generation = 0, _readCount = 0;
  String _error = '';
  List<VibProductInvoiceHit> _hits = [];
  late DateTime _from, _to;

  bool get _sales => widget.type == 'sales';

  @override void initState() {
    super.initState();
    _productId = widget.initialProductId;
    _productName = widget.initialProductName;
    if (_productName.isNotEmpty) _search.text = _productName;
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
    if (_loading || _exporting) return;
    try {
      final snapshot = await db.collection('products').get();
      if (!mounted) return;
      final options = <VibMovementProductChoice>[
        for (final item in snapshot.docs)
          (
            id: item.id,
            name: (item.data()['name'] ?? item.id).toString(),
            code: (item.data()['code'] ?? item.data()['sku'] ??
                item.data()['barcode'] ?? item.id).toString(),
          ),
      ];
      final choice = await showVibMovementProductPicker(context, options);
      if (choice == null || !mounted) return;
      final product = options.firstWhere((element) => element.id == choice);
      setState(() {
        _productId = product.id;
        _productName = product.name;
        _search.text = product.name;
        _complete = false;
        _hits = [];
        _error = '';
      });
    } catch (error) {
      if (mounted) setState(() =>
          _error = 'تعذر تحميل أسماء الأصناف: $error');
    }
  }

  Future<void> _sharePdf() async {
    if (!_complete || _loading || _exporting || _hits.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final font = pw.Font.ttf(
        await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final report = await createVibProductInvoiceReportPdf(
        productName: _productName.isNotEmpty ? _productName : _search.text.trim(),
        type: widget.type,
        hits: _hits,
        font: font,
        from: _from,
        to: _to,
        allDates: _allDates,
      );
      await Printing.sharePdf(
        bytes: report,
        filename: 'VIB-${widget.type.toUpperCase()}-PRODUCT-INVOICES.pdf');
    } catch (error) {
      if (mounted) await showInvoiceSaveProblem(context,
        'تعذر تجهيز تقرير الفواتير: $error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
      if (_complete && _hits.isNotEmpty)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _exporting ? null : _sharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
            label: Text(_exporting ? 'جاري تجهيز التقرير...' :
              'إرسال تقرير فواتير الصنف PDF / واتساب')))),
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
