part of 'main.dart';

Future<void> openProductImport(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Directionality(textDirection: TextDirection.rtl, child: ProductImportScreen())));
}

Future<int> applyProductImportChunk(List<ProductImportTarget> targets, String source, String actor) => db.runTransaction<int>((tx) async {
  if (FirebaseAuth.instance.currentUser?.uid != actor) throw StateError('الحساب اتغير؛ افتح الإضافة من جديد');
  final profile = (await tx.get(db.collection('users').doc(actor))).data();
  if (profile?['role'] != 'owner' || profile?['active'] != true) throw StateError('إضافة الأصناف متاحة للمدير فقط');
  final live = <({ProductImportTarget target, Map<String, dynamic>? marker, Map<String, dynamic>? product, Map<String, dynamic>? stock})>[];
  // Every read precedes every write. Small chunks stay below transaction limits.
  for (final target in targets) {
    live.add((target: target,
      marker: (await tx.get(db.collection('settings').doc(target.markerId))).data(),
      product: (await tx.get(db.collection('products').doc(target.productId))).data(),
      stock: (await tx.get(db.collection('stock').doc('main_${target.productId}'))).data()));
  }
  final pending = live.where((item) => item.target.validateLive(item.marker, item.product, item.stock)).toList();
  final now = FieldValue.serverTimestamp();
  for (final item in pending) {
    final target = item.target, row = target.row;
    tx.set(db.collection('products').doc(target.productId), {
      'name': row.name, 'externalCode': row.code, 'purchasePrice': row.purchaseCents / 100, 'price': row.saleCents / 100,
      'active': true, if (item.product == null) 'category': 'غير مصنف', 'updatedAt': now,
    }, SetOptions(merge: true));
    // Preserve lastSaleId and other allowed existing stock fields.
    tx.set(db.collection('stock').doc('main_${target.productId}'), {
      'branchId': 'main', 'productId': target.productId, 'quantity': row.quantity,
    }, SetOptions(merge: true));
    final before = target.beforeQuantity, delta = row.quantity - before;
    if (delta != 0) {
      tx.set(db.collection('stockAdjustments').doc(target.markerId), {
        'productId': target.productId, 'productName': row.name, 'branchId': 'main',
        'before': before, 'after': row.quantity, 'delta': delta,
        'reason': 'إضافة رصيد من تقرير الأصناف', 'actorId': actor, 'createdAt': now,
      });
      tx.set(db.collection('stockMovements').doc(target.markerId), {
        'productId': target.productId, 'productName': row.name, 'branchId': 'main', 'kind': 'adjustment',
        'quantity': delta, 'balanceAfter': row.quantity, 'reason': 'إضافة رصيد من تقرير الأصناف',
        'referenceId': target.markerId, 'actorId': actor, 'createdAt': now,
      });
    }
    // Product, opening stock, ledger movement and replay marker commit together.
    tx.set(db.collection('settings').doc(target.markerId), {
      'kind': 'productImport', 'source': source, 'requestKey': target.requestKey, 'productId': target.productId,
      'actorId': actor, 'createdAt': now, 'quantityBefore': before, 'quantityAfter': row.quantity,
      'productBefore': item.product, 'stockBefore': item.stock,
    });
  }
  return pending.length;
});

class ProductImportScreen extends StatefulWidget {
  const ProductImportScreen({super.key});
  @override State<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends State<ProductImportScreen> {
  ProductImportFile? file;
  List<ProductImportTarget> targets = [];
  String? actor;
  String message = '', fileName = '';
  bool busy = false, finished = false;
  int processed = 0;

  Future<void> chooseFile() async {
    if (busy) return;
    setState(() { busy = true; message = ''; finished = false; processed = 0; targets = []; file = null; });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('سجل دخول المدير أولًا');
      final profile = (await db.collection('users').doc(uid).get(const GetOptions(source: Source.server))).data();
      if (profile?['role'] != 'owner' || profile?['active'] != true) throw StateError('إضافة الأصناف متاحة للمدير فقط');
      final selected = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (selected == null) return;
      final picked = selected.files.single;
      if (picked.size > 5000000) throw const FormatException('اختر ملف أصناف أصغر من 5 ميجابايت');
      final bytes = picked.bytes ?? (picked.path == null ? null : await File(picked.path!).readAsBytes());
      if (bytes == null) throw const FormatException('تعذر قراءة الملف');
      final parsed = ProductImportFile.parse(utf8.decode(bytes));
      final snapshots = await Future.wait([
        db.collection('products').get(const GetOptions(source: Source.server)),
        db.collection('stock').where('branchId', isEqualTo: 'main').get(const GetOptions(source: Source.server)),
        db.collection('settings').where('kind', isEqualTo: 'productImport').get(const GetOptions(source: Source.server)),
      ]);
      final plan = planProductImport(parsed, {for (final d in snapshots[0].docs) d.id: d.data()},
        {for (final d in snapshots[1].docs) d.id: d.data()}, {for (final d in snapshots[2].docs) d.id: d.data()});
      if (!mounted) return;
      setState(() { file = parsed; targets = plan; actor = uid; fileName = picked.name; });
    } catch (e) {
      if (mounted) setState(() => message = 'تعذر تجهيز الإضافة: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> addProducts() async {
    if (busy || finished || file == null || actor == null || targets.isEmpty) return;
    final archived = targets.where((t) => t.requiresReactivation).toList();
    if (archived.isNotEmpty) {
      final confirmed = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('إعادة تفعيل الأصناف المؤرشفة'),
        content: SizedBox(width: double.maxFinite, height: 300, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('يوجد ${archived.length} صنف مؤرشف في الملف. سيتم تفعيله بنفس كوده وسجله القديم، وتحديث الأسعار والرصيد طبقًا للمراجعة.'),
          const SizedBox(height: 12),
          Flexible(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: archived.map((t) => ListTile(dense: true, title: Text(t.row.name))).toList()))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع للمراجعة')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تفعيل الأصناف واستكمال الإضافة')),
        ],
      ));
      if (confirmed != true || !mounted) return;
    }
    setState(() { busy = true; processed = 0; message = ''; });
    try {
      for (var start = 0; start < targets.length; start += 20) {
        final end = start + 20 < targets.length ? start + 20 : targets.length;
        await applyProductImportChunk(targets.sublist(start, end), file!.source, actor!);
        if (!mounted) return;
        setState(() => processed = end);
      }
      if (mounted) setState(() { finished = true; message = 'تمت إضافة ومراجعة ${targets.length} صنفًا بنجاح'; });
    } catch (e) {
      if (mounted) setState(() => message = 'توقفت الإضافة بعد مراجعة $processed من ${targets.length} صنفًا: $e\nاختر نفس الملف مرة أخرى لاستكمال الباقي؛ الأصناف المسجلة لن تتكرر.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override Widget build(BuildContext context) {
    final remaining = targets.where((t) => !t.alreadyApplied).toList();
    return PopScope(canPop: !busy, child: Scaffold(
      appBar: AppBar(title: const Text('إضافة الأصناف من ملف'), automaticallyImplyLeading: !busy),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OutlinedButton.icon(onPressed: busy ? null : chooseFile, icon: const Icon(Icons.folder_open), label: const Text('اختيار ملف الأصناف')),
          if (fileName.isNotEmpty) Text(fileName, textAlign: TextAlign.center, maxLines: 2),
          if (targets.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${targets.length} صنف • جديد: ${remaining.where((t) => t.productBefore == null).length} • موجود: ${remaining.where((t) => t.productBefore != null).length} • سبق إضافته: ${targets.length - remaining.length}', style: const TextStyle(color: gold)),
            if (remaining.any((t) => t.requiresReactivation)) Text('أصناف مؤرشفة سيعاد تفعيلها: ${remaining.where((t) => t.requiresReactivation).length}', style: const TextStyle(color: Colors.orangeAccent)),
            Text('كمية صفر: ${targets.where((t) => t.row.quantity == 0).length} • كمية سالبة: ${targets.where((t) => t.row.quantity < 0).length}'),
            const Text('سعر البيع = سعر الشراء + 10%. يظهر الرصيد الحالي ثم رصيد التقرير؛ الإضافة تسجل فرق الرصيد وتحدث الأسعار.'),
          ],
          if (busy) ...[const SizedBox(height: 8), LinearProgressIndicator(value: targets.isEmpty ? null : processed / targets.length), Text(targets.isEmpty ? 'جارٍ قراءة الملف ومراجعة الأصناف…' : 'مراجعة $processed / ${targets.length}')],
          if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(message, style: TextStyle(color: finished ? Colors.greenAccent : Colors.redAccent))),
        ])),
        Expanded(child: targets.isEmpty ? const Center(child: Text('اختر ملف الأصناف المجهّز لإضافته إلى البرنامج')) : ListView.builder(
          itemCount: targets.length, itemBuilder: (context, index) {
            final t = targets[index], r = t.row;
            return ListTile(title: Text('${index + 1}. ${r.name}'), subtitle: Text('شراء ${(r.purchaseCents / 100).toStringAsFixed(2)} • بيع ${(r.saleCents / 100).toStringAsFixed(2)} ج.م\n${t.alreadyApplied ? 'سبق إضافته؛ الرصيد الحالي محفوظ' : 'الرصيد: ${t.beforeQuantity} ← ${r.quantity}${t.requiresReactivation ? '\nصنف مؤرشف — سيعاد تفعيله بنفس السجل' : ''}'}'),
              trailing: t.alreadyApplied ? const Icon(Icons.check_circle, color: Colors.green) : null);
          })),
        Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: busy || finished || targets.isEmpty ? null : addProducts,
          icon: const Icon(Icons.playlist_add_check), label: Text(finished ? 'تمت الإضافة' : 'إضافة الأصناف والكميات')))),
      ])),
    ));
  }
}
