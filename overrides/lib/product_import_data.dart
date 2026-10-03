import 'dart:convert';

String importName(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

int importMoney(dynamic value) {
  final text = '$value';
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
    throw const FormatException('السعر يجب أن يكون موجبًا أو صفرًا وبحد أقصى منزلتين عشريتين');
  }
  final parts = text.split('.');
  final cents = int.parse(parts[0]) * 100 + int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  if (cents > 100000000000) throw const FormatException('السعر خارج الحد المسموح');
  return cents;
}

class ImportProductRow {
  final String code, name;
  final int purchaseCents, saleCents, quantity;
  const ImportProductRow(this.code, this.name, this.purchaseCents, this.saleCents, this.quantity);
  Map<String, dynamic> get values => {'code': code, 'name': name, 'purchasePrice': purchaseCents / 100, 'price': saleCents / 100, 'quantity': quantity};
}

class ProductImportFile {
  final String source;
  final List<ImportProductRow> rows;
  const ProductImportFile(this.source, this.rows);
  factory ProductImportFile.parse(String text) {
    final dynamic payload = jsonDecode(text);
    if (payload is! Map || payload['schema'] != 'VIB Products Review' || payload['version'] != 1 || payload['markupPercent'] != 10 || payload['products'] is! List) {
      throw const FormatException('اختر ملف أصناف VIB بزيادة بيع 10%');
    }
    if (payload['pendingQuantityReview'] != null) throw const FormatException('توجد كمية تحتاج مراجعة في الملف');
    final source = '${payload['sourceSha256'] ?? ''}';
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(source)) throw const FormatException('معرف الملف غير صالح');
    final raw = payload['products'] as List;
    if (raw.isEmpty || raw.length > 5000) throw const FormatException('عدد الأصناف غير صالح');
    final codes = <String>{}, names = <String>{}, rows = <ImportProductRow>[];
    for (final item in raw) {
      if (item is! Map) throw const FormatException('بند غير صالح');
      final code = '${item['code'] ?? ''}', name = importName('${item['name'] ?? ''}');
      if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(code) || name.isEmpty || name.length > 500 || !codes.add(code) || !names.add(name)) {
        throw FormatException('اسم أو كود مكرر أو غير صالح: $name');
      }
      final qText = '${item['quantity']}';
      if (!RegExp(r'^-?\d+(\.0+)?$').hasMatch(qText)) throw FormatException('الكمية يجب أن تكون عدد قطع صحيحًا: $name');
      final quantity = int.parse(qText.split('.').first);
      if (quantity.abs() > 1000000) throw FormatException('كمية خارج الحد المسموح: $name');
      final cost = importMoney(item['purchasePrice']), sale = importMoney(item['price']);
      if (sale != (cost * 110 + 50) ~/ 100) throw FormatException('سعر البيع لا يساوي الشراء بزيادة 10%: $name');
      rows.add(ImportProductRow(code, name, cost, sale, quantity));
    }
    return ProductImportFile(source, List.unmodifiable(rows));
  }
}

bool importSame(dynamic a, dynamic b) {
  if (a is Map && b is Map) return a.length == b.length && a.keys.every((k) => b.containsKey(k) && importSame(a[k], b[k]));
  if (a is List && b is List) return a.length == b.length && List.generate(a.length, (i) => i).every((i) => importSame(a[i], b[i]));
  return a == b;
}

class ProductImportTarget {
  final ImportProductRow row;
  final String productId, markerId, requestKey;
  final Map<String, dynamic>? productBefore, stockBefore;
  final bool alreadyApplied;
  const ProductImportTarget({required this.row, required this.productId, required this.markerId, required this.requestKey,
    required this.productBefore, required this.stockBefore, required this.alreadyApplied});
  int get beforeQuantity => (stockBefore?['quantity'] as num?)?.toInt() ?? 0;
  // Replay succeeds before checking stock: later sales must never be overwritten.
  bool validateLive(Map<String, dynamic>? marker, Map<String, dynamic>? product, Map<String, dynamic>? stock) {
    if (marker != null) {
      if (marker['requestKey'] != requestKey || marker['productId'] != productId) throw StateError('تم استيراد هذا الكود ببيانات مختلفة: ${row.name}');
      return false;
    }
    if (alreadyApplied) throw StateError('سجل الإضافة غير موجود؛ أعد قراءة الملف');
    if (!importSame(productBefore, product) || !importSame(stockBefore, stock)) throw StateError('الصنف أو رصيده اتغير أثناء المراجعة: ${row.name}. أعد قراءة الملف');
    return true;
  }
}

List<ProductImportTarget> planProductImport(ProductImportFile file, Map<String, Map<String, dynamic>> products,
    Map<String, Map<String, dynamic>> stocks, Map<String, Map<String, dynamic>> markers) {
  final byCode = <String, Set<String>>{}, byName = <String, Set<String>>{};
  for (final entry in products.entries) {
    byName.putIfAbsent(importName('${entry.value['name'] ?? ''}'), () => {}).add(entry.key);
    for (final key in ['code', 'barcode', 'externalCode']) {
      final value = '${entry.value[key] ?? ''}'.trim();
      if (value.isNotEmpty) byCode.putIfAbsent(value, () => {}).add(entry.key);
    }
  }
  final used = <String>{}, targets = <ProductImportTarget>[];
  for (final row in file.rows) {
    final markerId = 'productImport_${file.source}_${row.code}';
    final requestKey = jsonEncode({'source': file.source, ...row.values});
    final marker = markers[markerId];
    String id;
    if (marker != null) {
      id = '${marker['productId'] ?? ''}';
      if (marker['requestKey'] != requestKey || id.isEmpty || id.contains('/')) throw StateError('هذا الكود سبق إضافته ببيانات مختلفة: ${row.name}');
    } else {
      final codes = byCode[row.code] ?? <String>{}, names = byName[row.name] ?? <String>{};
      if (codes.length > 1 || names.length > 1 || (codes.isNotEmpty && names.isNotEmpty && codes.single != names.single)) {
        throw StateError('يوجد تكرار للصنف يحتاج مراجعة: ${row.name}');
      }
      id = codes.isNotEmpty ? codes.single : names.isNotEmpty ? names.single : 'import_${row.code}';
      final existing = products[id];
      if (existing != null) {
        if (importName('${existing['name'] ?? ''}') != row.name) throw StateError('الكود مرتبط باسم مختلف: ${row.name}');
        final oldCodes = ['code', 'barcode', 'externalCode'].map((k) => '${existing[k] ?? ''}'.trim()).where((v) => v.isNotEmpty);
        if (oldCodes.any((v) => v != row.code)) throw StateError('الاسم مرتبط بكود مختلف: ${row.name}');
        if (existing['active'] == false) throw StateError('الصنف مؤرشف ويحتاج مراجعة: ${row.name}');
      }
    }
    if (!used.add(id)) throw StateError('بندان مرتبطان بنفس الصنف: ${row.name}');
    final stock = stocks['main_$id'];
    if (stock != null && (stock['quantity'] is! int || stock['branchId'] != 'main' || stock['productId'] != id)) throw StateError('الرصيد الحالي غير صالح: ${row.name}');
    targets.add(ProductImportTarget(row: row, productId: id, markerId: markerId, requestKey: requestKey,
      productBefore: products[id], stockBefore: stock, alreadyApplied: marker != null));
  }
  return targets;
}
