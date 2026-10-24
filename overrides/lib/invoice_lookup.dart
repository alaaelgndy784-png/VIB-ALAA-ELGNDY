part of 'main.dart';

class MovementPeriodControls extends StatefulWidget {
  final DateTime from, to;
  final bool enabled;
  final bool compact;
  final void Function(DateTime, DateTime) onConfirm;
  const MovementPeriodControls({super.key, required this.from, required this.to,
    required this.enabled, required this.onConfirm, this.compact = false});
  @override State<MovementPeriodControls> createState() => _MovementPeriodControlsState();
}
class _MovementPeriodControlsState extends State<MovementPeriodControls> {
  late DateTime start = widget.from, end = widget.to;
  late final TextEditingController startText = TextEditingController(text: _format(start));
  late final TextEditingController endText = TextEditingController(text: _format(end));
  bool startInputValid = true, endInputValid = true;

  String _format(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
  DateTime? _parse(String value) {
    try {
      final normalized = invoiceSearchText(value);
      // People often type dates without leading zeroes (1/10/2026), and the
      // Android Arabic keyboard can enter Arabic-Indic digits. Normalize both
      // forms before validating so the apply button does not stay disabled for
      // an otherwise valid date.
      final match = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(normalized);
      if (match == null) return null;
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      final date = DateTime(year, month, day);
      if (date.year != year || date.month != month || date.day != day) return null;
      final now = tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
      if (date.year < 2000 || date.isAfter(DateTime(now.year, now.month, now.day))) return null;
      return date;
    } catch (_) { return null; }
  }
  void _editDate(bool first, String value) {
    final parsed = _parse(value);
    setState(() {
      if (first) {
        startInputValid = parsed != null;
        if (parsed != null) start = parsed;
      } else {
        endInputValid = parsed != null;
        if (parsed != null) end = parsed;
      }
    });
  }
  void _setDate(bool first, DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    setState(() {
      if (first) { start = date; startText.text = _format(date); startInputValid = true; }
      else { end = date; endText.text = _format(date); endInputValid = true; }
    });
  }
  Future<void> pick(bool first) async {
    final now = tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
    final date = await showDatePicker(context: context, initialDate: first ? start : end,
      firstDate: DateTime(2000), lastDate: DateTime(now.year, now.month, now.day),
      helpText: first ? 'من تاريخ' : 'إلى تاريخ', confirmText: 'اختيار', cancelText: 'إلغاء');
    if (date != null && mounted) _setDate(first, date);
  }
  @override void dispose() {
    startText.dispose();
    endText.dispose();
    super.dispose();
  }
  @override Widget build(BuildContext context) => Padding(padding: EdgeInsets.all(widget.compact ? 5 : 12),
    child: Column(children: [
      Row(children: [
        Expanded(child: TextField(key: const ValueKey('period-from-input'), controller: startText,
          enabled: widget.enabled, keyboardType: TextInputType.datetime, textAlign: TextAlign.center,
          style: TextStyle(fontSize: widget.compact ? 13 : 16),
          onChanged: (value) => _editDate(true, value),
          decoration: const InputDecoration(labelText: 'من تاريخ', hintText: 'يوم/شهر/سنة',
            border: OutlineInputBorder(), isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 9, horizontal: 4)))),
        const SizedBox(width: 8),
        Expanded(child: TextField(key: const ValueKey('period-to-input'), controller: endText,
          enabled: widget.enabled, keyboardType: TextInputType.datetime, textAlign: TextAlign.center,
          style: TextStyle(fontSize: widget.compact ? 13 : 16),
          onChanged: (value) => _editDate(false, value),
          decoration: const InputDecoration(labelText: 'إلى تاريخ', hintText: 'يوم/شهر/سنة',
            border: OutlineInputBorder(), isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 9, horizontal: 4)))),
      ]),
      SizedBox(height: widget.compact ? 4 : 8),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: widget.enabled ? () => pick(true) : null,
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact,
            minimumSize: Size(0, widget.compact ? 32 : 40), padding: const EdgeInsets.symmetric(horizontal: 3),
            textStyle: TextStyle(fontSize: widget.compact ? 12 : 14)),
          icon: Icon(Icons.calendar_month, size: widget.compact ? 15 : 18), label: const Text('البداية', maxLines: 1, overflow: TextOverflow.ellipsis))),
        const SizedBox(width: 6),
        Expanded(child: OutlinedButton.icon(onPressed: widget.enabled ? () => pick(false) : null,
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact,
            minimumSize: Size(0, widget.compact ? 32 : 40), padding: const EdgeInsets.symmetric(horizontal: 3),
            textStyle: TextStyle(fontSize: widget.compact ? 12 : 14)),
          icon: Icon(Icons.calendar_month, size: widget.compact ? 15 : 18), label: const Text('النهاية', maxLines: 1, overflow: TextOverflow.ellipsis))),
      ]),
      SizedBox(height: widget.compact ? 2 : 6),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (widget.compact) IconButton(tooltip: 'اليوم', visualDensity: VisualDensity.compact,
          onPressed: widget.enabled ? () {
            final now = tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
            final today = DateTime(now.year, now.month, now.day);
            setState(() { start = end = today; startText.text = endText.text = _format(today); startInputValid = endInputValid = true; });
          } : null, icon: const Icon(Icons.today, size: 20))
        else TextButton.icon(onPressed: widget.enabled ? () {
          final now = tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
          final today = DateTime(now.year, now.month, now.day);
          setState(() { start = end = today; startText.text = endText.text = _format(today); startInputValid = endInputValid = true; });
        } : null, icon: const Icon(Icons.today, size: 18), label: const Text('اليوم')),
        const SizedBox(width: 8),
        FilledButton.icon(key: const ValueKey('period-apply-button'), onPressed: widget.enabled && startInputValid && endInputValid && !end.isBefore(start)
            ? () => widget.onConfirm(start, end) : null,
          style: FilledButton.styleFrom(visualDensity: widget.compact ? VisualDensity.compact : VisualDensity.standard,
            minimumSize: Size(0, widget.compact ? 32 : 40),
            padding: const EdgeInsets.symmetric(horizontal: 10)),
          icon: const Icon(Icons.check, size: 18), label: const Text('تطبيق')),
      ]),
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
  @override Widget build(BuildContext context)=>InvoiceEditSearchFrame(type:widget.type,search:widget.search,
    onChanged:(_)=>setState((){}),results:FutureBuilder<QuerySnapshot<Map<String,dynamic>>>(future:invoices,builder:(context,snapshot){
      if(snapshot.hasError)return SingleChildScrollView(child:Text('تعذر تحميل الفواتير: ${snapshot.error}'));
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      final rows=snapshot.data!.docs.where((d)=>visibleAfterReset(d.data()) && d.data()['status']=='completed' && invoiceMatchesEditSearch(widget.type,d.id,d.data(),widget.search.text)).toList();
      if(rows.isEmpty)return const Center(child:Text('لا توجد فاتورة مطابقة للاسم أو الرقم'));
      return ListView.builder(itemCount:rows.length,itemBuilder:(context,i){
        final row=rows[i],data=row.data(),sales=widget.type=='sales';
        final blocked=invoiceHasLinkedVoucher(data);
        return InvoiceEditResultCard(key:ValueKey(row.id),party:'${data[sales ? 'customerName' : 'supplierName'] ?? ''}',
          number:invoiceDisplayNumber(widget.type,row.id,data),date:formatDate(data['createdAt']),
          amount:((data['total'] as num?) ?? 0).toStringAsFixed(2),blocked:blocked,
          onOpen:()=>Navigator.pop(context,row.id));
      });
    }));
}

void selectInvoiceNumberText(TextEditingController controller) =>
  controller.selection=TextSelection(baseOffset:0,extentOffset:controller.text.length);

class InvoiceEditSearchFrame extends StatelessWidget {
  final String type;
  final TextEditingController search;
  final ValueChanged<String> onChanged;
  final Widget results;
  const InvoiceEditSearchFrame({super.key,required this.type,required this.search,required this.onChanged,required this.results});
  @override Widget build(BuildContext context)=>Dialog(
    insetPadding:const EdgeInsets.symmetric(horizontal:12,vertical:16),
    child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:680),child:LayoutBuilder(builder:(context,constraints)=>
      SizedBox(width:double.infinity,height:constraints.maxHeight.clamp(0.0,560.0).toDouble(),child:Padding(
        padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text(type=='sales' ? 'تعديل فاتورة مبيعات' : 'تعديل فاتورة مشتريات',
            maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          TextField(controller:search,autofocus:false,onChanged:onChanged,style:const TextStyle(fontSize:14),
            decoration:InputDecoration(labelText:type=='sales' ? 'اسم العميل أو رقم الفاتورة' : 'اسم المورد أو رقم الفاتورة',
              prefixIcon:const Icon(Icons.search,size:20),isDense:true,border:const OutlineInputBorder(),
              contentPadding:const EdgeInsets.symmetric(horizontal:10,vertical:10))),
          const SizedBox(height:6),
          const Text('اختر الفاتورة من النتائج. المرتبطة بسند لا تقبل التعديل.',
            maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:11)),
          const SizedBox(height:6),Expanded(child:results),
          Align(alignment:AlignmentDirectional.centerEnd,child:TextButton(
            onPressed:()=>Navigator.pop(context),child:const Text('إلغاء'))),
        ]))))));
}

class InvoiceEditResultCard extends StatelessWidget {
  final String party,number,date,amount;
  final bool blocked;
  final VoidCallback onOpen;
  const InvoiceEditResultCard({super.key,required this.party,required this.number,required this.date,
    required this.amount,required this.blocked,required this.onOpen});
  @override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.symmetric(vertical:3),
    child:InkWell(onTap:blocked ? null : onOpen,child:Padding(padding:const EdgeInsets.all(9),
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[Icon(blocked ? Icons.lock_outline : Icons.receipt_long_outlined,size:19,color:gold),
          const SizedBox(width:6),Expanded(child:Text(party.isEmpty ? 'بدون اسم مسجل' : party,
            maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.greenAccent,fontSize:14,fontWeight:FontWeight.bold)))]),
        const SizedBox(height:4),
        Wrap(spacing:12,runSpacing:2,children:[
          Text('رقم الفاتورة: $number',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12)),
          Text('$amount ج.م',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:gold,fontSize:12,fontWeight:FontWeight.bold)),
        ]),
        Text(date,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11)),
        if(blocked) const Text('مرتبطة بسند — التعديل ممنوع',maxLines:2,overflow:TextOverflow.ellipsis,
          style:TextStyle(fontSize:11,color:Colors.redAccent)),
      ]))));
}

bool invoiceHasLinkedVoucher(Map<String,dynamic> data) =>
  ['receiptId','paymentId','supplierPaymentId','voucherId'].any((key)=>'${data[key] ?? ''}'.trim().isNotEmpty) || ((data['receiptPaid'] as num?) ?? 0)>0;

bool saleReceiptBlocksEdit(Map<String,dynamic> invoice,String receiptId,Map<String,dynamic> receipt,
    {Set<String> cancelledReceiptIds=const {}}) {
  if(cancelledReceiptIds.contains(receiptId)) return false;
  final linked='${receipt['invoiceId'] ?? ''}';
  if(linked.isNotEmpty) return linked=='${invoice['id'] ?? ''}';
  final created=invoice['createdAt'] as Timestamp?,at=receipt['createdAt'] as Timestamp?;
  return created==null || at==null || at.compareTo(created)>=0;
}
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
  // An edited older purchase must NEVER replace the cost of a newer purchase.
  // Fetch server records from this invoice's original date to identify the
  // most recent invoice for every affected item; unreadable history means
  // no automatic cost update (manual inventory correction remains available).
  final lastSourceDate = preflight['createdAt'];
  final newestCosts = <String, LastPurchaseUnitCost>{};
  if (lastSourceDate is Timestamp) {
    final recent = await db.collection('purchases')
      .where('createdAt', isGreaterThanOrEqualTo: lastSourceDate)
      .get(const GetOptions(source: Source.server));
    if (recent.metadata.isFromCache || recent.metadata.hasPendingWrites) {
      throw StateError('تعذر تأكيد تاريخ آخر شراء من السيرفر');
    }
    newestCosts.addAll(latestPurchaseUnitCosts([
      for (final invoice in recent.docs)
        <String, dynamic>{
          ...invoice.data(),
          'id': invoice.id,
          'createdAt': (invoice.data()['createdAt'] as Timestamp?)?.toDate(),
        },
    ]));
  }
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
      final q = line['quantity'] as int;
      final price = (line['unitPrice'] as num).toDouble();
      if (product == null || q <= 0 || q > 1000000 || !price.isFinite || price < 0 || newQuantities.containsKey(p)) throw Exception('راجع الأصناف والأسعار والكميات');
      if (product['active'] != true && !oldQuantities.containsKey(p)) throw Exception('الصنف غير نشط');
      newQuantities[p] = q;
      items.add({'productId': p, 'productName': product['name'], 'quantity': q, 'unitCost': price,
        'lineTotal': q * price});
    }
    total = purchaseEditTotalCents(items);
    // Apply cost corrections only to an item whose amended invoice is still
    // the last recorded purchase. Sales prices and historic sales costs stay
    // unchanged. A newer purchase or explicit manual correction takes priority.
    final originalCosts = <String, double>{};
    for (final row in original) {
      final productId = '${row['productId'] ?? ''}';
      final value = row['unitCost'];
      if (value is num && value.isFinite && value >= 0) {
        originalCosts[productId] = value.toDouble();
      }
    }
    final refreshedCosts = <String, double>{};
    for (final row in items) {
      final productId = row['productId'] as String;
      final cost = (row['unitCost'] as num).toDouble();
      final oldCost = originalCosts[productId];
      final product = products[productId]!.data()!;
      final explicitCorrection = product['purchasePriceCorrectedAt'];
      final lastPurchaseAt = product['lastPurchaseAt'];
      if (shouldSyncEditedPurchaseCost(
        invoiceId: id,
        latestInvoiceId: newestCosts[productId]?.invoiceId,
        previousInvoiceCost: oldCost,
        correctedInvoiceCost: cost,
        currentProductCost: product['purchasePrice'] as num?,
        productLastPurchaseId: product['lastPurchaseId'] as String?,
        manualCorrectionAt: explicitCorrection is Timestamp ? explicitCorrection.toDate() : null,
        lastPurchaseRecordedAt: lastPurchaseAt is Timestamp ? lastPurchaseAt.toDate() : null,
        originalInvoiceAt: lastSourceDate is Timestamp ? lastSourceDate.toDate() : null,
      )) refreshedCosts[productId] = cost;
    }
    final paid = cents(payment), due = total - paid;
    if (items.isEmpty || items.length > 50 || total > 1000000000000 || !payment.isFinite || paid < 0 || due < 0) throw Exception('راجع المدفوع وبنود الفاتورة');
    if (due > 0 && (customer == null || customer['active'] == false)) throw Exception('الفاتورة الآجلة تحتاج موردًا نشطًا');
    final debtDelta = due - cents(old['due']);
    final cashDelta = purchaseEditCashDelta(old,paid);
    final cashBefore = cents((cash?['balance'] as num?) ?? 0), balanceBefore = cents((customer?['balance'] as num?) ?? 0);
    if(cashDelta<0 && cashBefore+cashDelta<0) throw StateError('رصيد الصندوق لا يكفي لفارق المدفوع');
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
    for (final entry in refreshedCosts.entries) {
      tx.update(products[entry.key]!.reference, {
        'purchasePrice': entry.value,
        'lastPurchaseId': id,
        if (lastSourceDate is Timestamp) 'lastPurchaseAt': lastSourceDate,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    tx.update(ref, {'items': items, 'itemCount': items.length, 'cashPaidPosted': paid / 100,
      'total': total / 100, 'paid': paid / 100, 'due': due / 100, 'paymentStatus': due > 0 ? 'credit' : 'cash',
      'revision': revision + 1, 'updatedAt': FieldValue.serverTimestamp(), 'lastEditedBy': actor,
      'productId': items.length == 1 ? items.first['productId'] : '', 'productName': items.length == 1 ? items.first['productName'] : '',
      'quantity': items.length == 1 ? items.first['quantity'] : 0, 'unitCost': items.length == 1 ? items.first['unitCost'] : 0});
    tx.set(edit, {'invoiceId': id, 'invoiceType': 'purchases',
      'updatedProductCosts': refreshedCosts, 'beforeItems': original, 'afterItems': items,
      'totalBefore': old['total'], 'totalAfter': total / 100, 'paidBefore': old['paid'], 'paidAfter': paid / 100,
      'revision': revision + 1, 'requestKey': key, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
  });
}


int purchaseEditTotalCents(List<Map<String,dynamic>> items) {
  var total=0.0;
  for(final item in items) {
    final value=(item['lineTotal'] as num).toDouble();
    if(!value.isFinite || value<0)throw StateError('إجمالي البند غير صحيح');
    total+=value;
  }
  if(!total.isFinite || total>10000000000)throw StateError('إجمالي الفاتورة غير صحيح');
  return (total*100).round();
}


