part of 'main.dart';

class MovementPeriodControls extends StatefulWidget {
  final DateTime from, to;
  final bool enabled;
  final void Function(DateTime, DateTime) onConfirm;
  const MovementPeriodControls({super.key, required this.from, required this.to,
    required this.enabled, required this.onConfirm});
  @override State<MovementPeriodControls> createState() => _MovementPeriodControlsState();
}
class _MovementPeriodControlsState extends State<MovementPeriodControls> {
  late DateTime start = widget.from, end = widget.to;
  Future<void> pick(bool first) async {
    final now = tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
    final date = await showDatePicker(context: context, initialDate: first ? start : end,
      firstDate: DateTime(2000), lastDate: DateTime(now.year, now.month, now.day),
      helpText: first ? 'من تاريخ' : 'إلى تاريخ', confirmText: 'اختيار', cancelText: 'إلغاء');
    if (date != null && mounted) setState(() { if (first) start = date; else end = date; });
  }
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(12),
    child: Column(children: [Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(onPressed: widget.enabled ? () => pick(true) : null,
        icon: const Icon(Icons.calendar_month), label: Text('من: ${DateFormat('dd/MM/yyyy').format(start)}')),
      OutlinedButton.icon(onPressed: widget.enabled ? () => pick(false) : null,
        icon: const Icon(Icons.calendar_month), label: Text('إلى: ${DateFormat('dd/MM/yyyy').format(end)}')),
      FilledButton.icon(onPressed: widget.enabled && !end.isBefore(start) ? () => widget.onConfirm(start, end) : null,
        icon: const Icon(Icons.check), label: const Text('موافق')),
      TextButton.icon(onPressed: widget.enabled ? () => setState(() {
        final now = tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
        start = end = DateTime(now.year, now.month, now.day);
      }) : null, icon: const Icon(Icons.today), label: const Text('اليوم')),
    ]), if(end.isBefore(start)) const Text('تاريخ النهاية يجب أن يكون بعد البداية أو نفس اليوم', style: TextStyle(color: Colors.redAccent)),
      const Text('اختر البداية والنهاية ثم اضغط موافق لعرض إجمالي الفترة، شامل يوم النهاية.'),
    ]));
}

String invoiceSearchText(String value) {
  const arabic = '٠١٢٣٤٥٦٧٨٩', eastern = '۰۱۲۳۴۵۶۷۸۹';
  var text = value.toLowerCase().trim();
  for (var i=0;i<10;i++) { text=text.replaceAll(arabic[i], '$i').replaceAll(eastern[i], '$i'); }
  return text.replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ى','ي').replaceAll(RegExp(r'[\u064B-\u065F\u0640]'), '').replaceAll(RegExp(r'\s+'), ' ');
}
bool invoiceMatchesEditSearch(String type, String id, Map<String,dynamic> data, String query) {
  final needle=invoiceSearchText(query);
  if(needle.isEmpty) return true;
  final number=invoiceSearchText(invoiceDisplayNumber(type,id,data));
  final numeric=RegExp(r'^\d+$').hasMatch(needle);
  final internal='${data['internalNumber'] ?? ''}';
  if(numeric) return int.tryParse(internal)==int.tryParse(needle) || int.tryParse(number)==int.tryParse(needle) || number==needle || number.endsWith('-$needle') || invoiceSearchText(id)==needle;
  return invoiceSearchText('${data[type=='sales' ? 'customerName' : 'supplierName'] ?? ''}').contains(needle) || number.contains(needle) || invoiceSearchText(id)==needle;
}

Future<void> findInvoiceForEdit(BuildContext context, String type) async {
  final search=TextEditingController();
  final sales=type=='sales';
  String? selected;
  try {
    selected=await showDialog<String>(context:context,builder:(dialog)=>_InvoiceEditSearchDialog(type:type,search:search));
  } finally { search.dispose(); }
  if(selected!=null && context.mounted) await appendInvoiceDialog(context,type,selected,replaceSale:sales,replacePurchase:!sales);
}
class _InvoiceEditSearchDialog extends StatefulWidget {
  final String type;
  final TextEditingController search;
  const _InvoiceEditSearchDialog({required this.type,required this.search});
  @override State<_InvoiceEditSearchDialog> createState()=>_InvoiceEditSearchDialogState();
}
class _InvoiceEditSearchDialogState extends State<_InvoiceEditSearchDialog> {
  late final Future<QuerySnapshot<Map<String,dynamic>>> invoices=load();
  Future<QuerySnapshot<Map<String,dynamic>>> load() async {
    await prepareInvoiceSerials(widget.type);
    final result=await db.collection(widget.type).orderBy('createdAt',descending:true).get(const GetOptions(source:Source.server));
    if(result.metadata.isFromCache || result.metadata.hasPendingWrites) throw StateError('انتظر تأكيد الفواتير من الخادم');
    return result;
  }
  @override Widget build(BuildContext context)=>AlertDialog(
    title:Text(widget.type=='sales' ? 'تعديل فاتورة مبيعات' : 'تعديل فاتورة مشتريات'),
    content:SizedBox(width:620,height:MediaQuery.sizeOf(context).height*.55,child:Column(children:[
      TextField(controller:widget.search,autofocus:true,onChanged:(_)=>setState((){}),decoration:InputDecoration(
        labelText:widget.type=='sales' ? 'اسم العميل أو رقم الفاتورة' : 'اسم المورد أو رقم الفاتورة',prefixIcon:const Icon(Icons.search))),
      const SizedBox(height:8), const Text('اختر الفاتورة من النتائج. الفاتورة المرتبطة بسند لا تقبل التعديل.'),
      Expanded(child:FutureBuilder<QuerySnapshot<Map<String,dynamic>>>(future:invoices,builder:(context,snapshot){
        if(snapshot.hasError)return Center(child:Text('تعذر تحميل الفواتير: ${snapshot.error}'));
        if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
        final rows=snapshot.data!.docs.where((d)=>visibleAfterReset(d.data()) && d.data()['status']=='completed' && invoiceMatchesEditSearch(widget.type,d.id,d.data(),widget.search.text)).toList();
        if(rows.isEmpty)return const Center(child:Text('لا توجد فاتورة مطابقة للاسم أو الرقم'));
        return ListView.builder(itemCount:rows.length,itemBuilder:(context,i){
          final row=rows[i],data=row.data(),sales=widget.type=='sales';
          final blocked=invoiceHasLinkedVoucher(data);
          return ListTile(leading:Icon(blocked ? Icons.lock_outline : Icons.receipt_long_outlined),
            title:Text('${data[sales ? 'customerName' : 'supplierName'] ?? ''}',style:const TextStyle(color:Colors.greenAccent)),
            subtitle:Text('رقم الفاتورة: ${invoiceDisplayNumber(widget.type,row.id,data)}\n${formatDate(data['createdAt'])}${blocked ? '\nمرتبطة بسند — التعديل ممنوع' : ''}'),
            trailing:Text('${money((data['total'] as num?) ?? 0)} ج.م'),enabled:!blocked,
            onTap:blocked ? null : ()=>Navigator.pop(context,row.id));
        });
      })),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('إلغاء'))]);
}

bool invoiceHasLinkedVoucher(Map<String,dynamic> data) =>
  ['receiptId','paymentId','supplierPaymentId','voucherId'].any((key)=>'${data[key] ?? ''}'.trim().isNotEmpty) || ((data['receiptPaid'] as num?) ?? 0)>0;
List<Map<String,dynamic>> purchaseItems(Map<String,dynamic> data) => data['items'] is List && (data['items'] as List).isNotEmpty
  ? (data['items'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList()
  : [{'productId':data['productId'],'productName':data['productName'],'quantity':data['quantity'],'unitCost':data['unitCost'],'lineTotal':data['total']}];
bool purchaseVoucherBlocksEdit(Map<String,dynamic> invoice,Map<String,dynamic> voucher) {
  if(voucher['kind']!='payment' || voucher['accountType']!='suppliers') return false;
  final linked='${voucher['invoiceId'] ?? ''}';
  if(linked.isNotEmpty) return linked==invoice['id'];
  final created=invoice['createdAt'] as Timestamp?,at=voucher['createdAt'] as Timestamp?;
  return created==null || at==null || at.compareTo(created)>=0;
}
Future<void> assertPurchaseEditable(Map<String,dynamic> data) async {
  if(invoiceHasLinkedVoucher(data)) throw StateError('الفاتورة مرتبطة بسند ولا يمكن تعديلها');
  final id='${data['supplierId'] ?? ''}';
  if(id.isEmpty)return;
  final result=await db.collection('accountMovements').where('accountId',isEqualTo:id).get(const GetOptions(source:Source.server));
  if(result.docs.any((d)=>purchaseVoucherBlocksEdit(data,d.data()))) throw StateError('يوجد سند صرف مرتبط بالفاتورة أو سداد عام للمورد؛ راجع توزيع السند قبل التعديل');
}

int purchaseEditStockDelta(int oldQuantity,int newQuantity)=>newQuantity-oldQuantity;
int purchaseEditCashDelta(Map<String,dynamic> old,int newPaidCents) {
  final posted=old['cashPosted']==true ? (old['paid'] as num?) ?? 0 : (old['cashPaidPosted'] as num?) ?? 0;
  if(!posted.toDouble().isFinite || posted<0) throw StateError('قيمة الصندوق السابقة غير صحيحة');
  return (posted*100).round()-newPaidCents;
}

Future<void> replacePurchaseLocally(String id, int revision, String requestId,
    List<Map<String, dynamic>> replacements, double payment) async {
  int cents(num value) => (value * 100).round();
  final actor = FirebaseAuth.instance.currentUser!.uid;
  final ref = db.collection('purchases').doc(id), edit = db.collection('invoiceEdits').doc(requestId);
  final key = jsonEncode({'id': id, 'revision': revision, 'items': replacements, 'paid': payment});
  final preflight = (await ref.get()).data();
  if (preflight == null) throw Exception('رقم الفاتورة غير موجود');
  final preSupplierId='${preflight['supplierId'] ?? ''}';
  final preSupplier=preSupplierId.isEmpty ? null : (await db.collection('suppliers').doc(preSupplierId).get(const GetOptions(source:Source.server))).data();
  await assertPurchaseEditable({...preflight, 'id': id});
  await db.runTransaction((tx) async {
    final profile = (await tx.get(db.collection('users').doc(actor))).data();
    if (profile?['role'] != 'owner' || profile?['active'] != true) throw Exception('تعديل الفاتورة متاح للمدير فقط');
    final saved = (await tx.get(edit)).data();
    if (saved != null) {
      if (saved['requestKey'] != key || saved['actorId'] != actor) throw Exception('طلب تعديل مختلف');
      return;
    }
    final old = (await tx.get(ref)).data();
    if (old == null || old['status'] != 'completed' || (old['revision'] ?? 0) != revision) throw Exception('الفاتورة غير متاحة أو اتعدلت؛ افتحها من جديد');
    if(invoiceHasLinkedVoucher(old)) throw StateError('الفاتورة مرتبطة بسند ولا يمكن تعديلها');
    if (old['paid'] is! num || old['due'] is! num || cents(old['total']) - cents(old['paid']) != cents(old['due'])) throw Exception('الفاتورة القديمة تحتاج مراجعة المدفوع والباقي');
    final customerId = '${old['supplierId'] ?? ''}';
    final customerRef = customerId.isEmpty ? null : db.collection('suppliers').doc(customerId);
    final customer = customerRef == null ? null : (await tx.get(customerRef)).data();
    if(customerId!=preSupplierId || customer?['balance']!=preSupplier?['balance'] || customer?['updatedAt']!=preSupplier?['updatedAt']) {
      throw StateError('حساب المورد اتغير أثناء المراجعة؛ افتح الفاتورة من جديد للتحقق من السندات');
    }
    final cashRef = db.collection('settings').doc('cash');
    final cash = (await tx.get(cashRef)).data();
    final original = purchaseItems(old), oldQuantities = <String, int>{};
    for (final item in original) {
      final p = '${item['productId']}'; oldQuantities[p] = (oldQuantities[p] ?? 0) + (item['quantity'] as num).toInt();
    }
    final ids = {...oldQuantities.keys, ...replacements.map((x) => '${x['productId']}')};
    const stockBranch = 'main';
    final stocks = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    final products = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final p in ids) {
      stocks[p] = await tx.get(db.collection('stock').doc('${stockBranch}_$p'));
      products[p] = await tx.get(db.collection('products').doc(p));
    }
    final items = <Map<String, dynamic>>[], newQuantities = <String, int>{};
    var total = 0;
    for (final line in replacements) {
      final p = '${line['productId']}', product = products[p]!.data();
      final q = line['quantity'] as int, price = cents(line['unitPrice']);
      if (product == null || q <= 0 || q > 1000000 || price < 0 || newQuantities.containsKey(p)) throw Exception('راجع الأصناف والأسعار والكميات');
      if (product['active'] != true && !oldQuantities.containsKey(p)) throw Exception('الصنف غير نشط');
      newQuantities[p] = q; total += q * price;
      items.add({'productId': p, 'productName': product['name'], 'quantity': q, 'unitCost': price / 100,
        'lineTotal': q * price / 100});
    }
    final paid = cents(payment), due = total - paid;
    if (items.isEmpty || items.length > 50 || total > 1000000000000 || !payment.isFinite || paid < 0 || due < 0) throw Exception('راجع المدفوع وبنود الفاتورة');
    if (due > 0 && (customer == null || customer['active'] == false)) throw Exception('الفاتورة الآجلة تحتاج موردًا نشطًا');
    final debtDelta = due - cents(old['due']);
    final cashDelta = purchaseEditCashDelta(old,paid);
    final cashBefore = cents((cash?['balance'] as num?) ?? 0), balanceBefore = cents((customer?['balance'] as num?) ?? 0);
    if(cashBefore+cashDelta<0) throw StateError('رصيد الصندوق لا يكفي لفارق المدفوع');
    if (customer != null && balanceBefore + debtDelta < 0) throw Exception('التعديل يتعارض مع سداد المورد');
    for (final p in ids) {
      final before = (stocks[p]!.data()?['quantity'] as num?)?.toInt() ?? 0;
      final delta = purchaseEditStockDelta(oldQuantities[p] ?? 0,newQuantities[p] ?? 0), after = before + delta;
      if (after < 0) throw Exception('المخزون غير كافٍ للصنف ${products[p]!.data()?['name']}');
      if (delta == 0) continue;
      tx.set(stocks[p]!.reference, {'branchId': stockBranch, 'productId': p, 'quantity': after, 'lastPurchaseId': id}, SetOptions(merge: true));
      tx.set(db.collection('stockMovements').doc('${requestId}_$p'), {'productId': p, 'productName': products[p]!.data()?['name'],
        'branchId': stockBranch, 'kind': 'purchaseCorrection', 'quantity': delta, 'balanceAfter': after,
        'referenceId': id, 'editId': requestId, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
    }
    if (customerRef != null && debtDelta != 0) {
      tx.update(customerRef, {'balance': (balanceBefore + debtDelta) / 100, 'updatedAt': FieldValue.serverTimestamp()});
      tx.set(db.collection('accountMovements').doc('${requestId}_supplier'), {'accountType': 'suppliers', 'accountId': customerId,
        'accountName': customer?['name'] ?? '', 'kind': 'purchaseCorrection', 'amount': debtDelta / 100,
        'balanceBefore': balanceBefore / 100, 'balanceAfter': (balanceBefore + debtDelta) / 100,
        'referenceId': id, 'editId': requestId, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
    }
    if (cashDelta != 0) {
      tx.set(cashRef, {'balance': (cashBefore + cashDelta) / 100, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      tx.set(db.collection('accountMovements').doc('${requestId}_cash'), {'accountType': 'cash', 'accountId': customerId,
        'accountName': customer?['name'] ?? '', 'kind': 'purchaseCorrection', 'amount': cashDelta.abs() / 100, 'delta': cashDelta / 100,
        'balanceBefore': cashBefore / 100, 'balanceAfter': (cashBefore + cashDelta) / 100,
        'referenceId': id, 'editId': requestId, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
    }
    tx.update(ref, {'items': items, 'itemCount': items.length, 'cashPaidPosted': paid / 100,
      'total': total / 100, 'paid': paid / 100, 'due': due / 100, 'paymentStatus': due > 0 ? 'credit' : 'cash',
      'revision': revision + 1, 'updatedAt': FieldValue.serverTimestamp(), 'lastEditedBy': actor,
      'productId': items.length == 1 ? items.first['productId'] : '', 'productName': items.length == 1 ? items.first['productName'] : '',
      'quantity': items.length == 1 ? items.first['quantity'] : 0, 'unitCost': items.length == 1 ? items.first['unitCost'] : 0});
    tx.set(edit, {'invoiceId': id, 'invoiceType': 'purchases', 'beforeItems': original, 'afterItems': items,
      'totalBefore': old['total'], 'totalAfter': total / 100, 'paidBefore': old['paid'], 'paidAfter': paid / 100,
      'revision': revision + 1, 'requestKey': key, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
  });
}

