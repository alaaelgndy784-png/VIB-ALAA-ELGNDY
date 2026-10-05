part of 'main.dart';

typedef SaleEntry = ({String id, String name, int qty, double price, double? cost, double discount, double basePrice});

// The owner commits stock, accounts, invoice number and approval in one transaction.
Future<Map<String,dynamic>> commitGroupedSale({required bool owner, required String branchId,
  required List<SaleEntry> entries, required double total, required double payment,
  required bool credit, required String customerId,
  required DocumentReference<Map<String,dynamic>> saleRef,
  String invoiceNote='', bool allowShortage=false, bool allowBelowCost=false, String overrideReason='',
  DocumentReference<Map<String,dynamic>>? pendingRef}) async {
  final due=total-payment;
  return db.runTransaction<Map<String,dynamic>>((tx) async {

                final actor = FirebaseAuth.instance.currentUser!.uid;
                final actorProfile = (await tx.get(db.collection('users').doc(actor))).data();
                if (actorProfile?['active'] != true || actorProfile?['role'] != (owner ? 'owner' : 'employee')) {
                  throw Exception('الحساب غير مفعل');
                }
                final pending = pendingRef == null ? null : (await tx.get(pendingRef)).data();
                final actualBranch = pending == null ? (owner ? branchId : '${actorProfile?['branchId'] ?? ''}') : '${pending['branchId']}';
                final seller = pending == null ? actor : '${pending['employeeId']}';
                final sellerProfile = pending == null ? actorProfile : (await tx.get(db.collection('users').doc(seller))).data();
                if (actualBranch.isEmpty || (!owner && entries.length > 4)) {
                  throw Exception('فاتورة الموظف تقبل حتى 4 أصناف مختلفة');
                }
                final requestKey = jsonEncode({'customerId': customerId, 'credit': credit, 'paid': payment,
                  if(owner) 'note':invoiceNote,
                  'items': entries.map((e) => {'id': e.id, 'qty': e.qty, 'price': e.price}).toList()});
                final priorSale = (await tx.get(saleRef)).data();
                if (priorSale != null) {
                  if (priorSale['employeeId'] != seller || priorSale['requestKey'] != requestKey || (pendingRef != null && priorSale['sourceRequestId'] != pendingRef.id)) {
                    throw Exception('الفاتورة محفوظة بالفعل ببيانات مختلفة');
                  }
                  return priorSale;
                }
                if (pendingRef != null && (pending == null || pending['status'] != 'pending' ||
                    sellerProfile?['active'] != true || sellerProfile?['role'] != 'employee' || sellerProfile?['branchId'] != actualBranch)) {
                  throw Exception('الطلب لم يعد معلقًا أو حساب الموظف غير مفعل');
                }
                if(pending != null) {
                  final proposal=PendingSaleData.parse(pending);
                  if(proposal.customerId!=customerId || proposal.credit!=credit || proposal.paid!=payment || proposal.lines.length!=entries.length ||
                    List.generate(entries.length,(i)=>proposal.lines[i].id!=entries[i].id || proposal.lines[i].quantity!=entries[i].qty ||
                      proposal.lines[i].price!=entries[i].price || proposal.lines[i].basePrice!=entries[i].basePrice || proposal.lines[i].discount!=entries[i].discount).any((x)=>x)) {
                    throw Exception('بيانات الطلب اتغيرت؛ افتحه من جديد');
                  }
                }
                final liveProducts = <String, Map<String, dynamic>>{};
                for (final e in entries) {
                  final product = (await tx.get(db.collection('products').doc(e.id))).data();
                  if (product == null || product['active'] != true) throw Exception('الصنف غير متاح');
                  if ((!owner || pending != null) && sellerProfile?['canEditSalePrice']!=true && ((product['price'] as num?)?.toDouble() != e.basePrice || (e.price-e.basePrice*(1-e.discount/100)).abs()>0.000001)) {
                    throw Exception('سعر الصنف اتغير؛ افتح الفاتورة من جديد');
                  }
                  final cost = (product['purchasePrice'] as num?)?.toDouble();
                  if (cost != null && e.price < cost && !(owner && allowBelowCost)) {
                    throw Exception('سعر البيع أقل من التكلفة');
                  }
                  liveProducts[e.id] = product;
                }
                final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
                for (final e in entries) {
                  stockSnaps[e.id] = await tx.get(db.collection('stock').doc('main_${e.id}'));
                }

                DocumentSnapshot<Map<String, dynamic>>? customerSnap;
                if (customerId.isNotEmpty) customerSnap = await tx.get(db.collection('customers').doc(customerId));

                DocumentSnapshot<Map<String, dynamic>>? cashSnap;
                if (payment > 0) cashSnap = await tx.get(db.collection('settings').doc('cash'));

                final invoiceSerial=owner ? await readInvoiceSerial(tx,'sales',saleRef.id) : null;
                if(invoiceSerial!=null)writeInvoiceSerial(tx,invoiceSerial);
                final items = <Map<String, dynamic>>[];
                for (final e in entries) {
                  final current = (stockSnaps[e.id]?.data()?['quantity'] as num?)?.toInt() ?? 0;
                  if (current < e.qty && !(owner && allowShortage)) {
                    throw Exception('الكمية غير متاحة للصنف ${liveProducts[e.id]!["name"]}');
                  }
                  final after = current - e.qty;
                  final lineTotal = e.qty * e.price;

                  items.add({
                    'productId': e.id,
                    'productName': '${liveProducts[e.id]!['name']}',
                    'quantity': e.qty,
                    'unitPrice':e.price,
                    'basePrice':e.basePrice,'discountPercent':e.discount,
                    'lineTotal': lineTotal,
                    'purchasePriceAtSale': (liveProducts[e.id]!['purchasePrice'] as num?)?.toDouble() ?? 0,
                  });

                  tx.set(db.collection('stock').doc('main_${e.id}'), {
                    'branchId': 'main',
                    'productId': e.id,
                    'quantity': after,
                    'lastSaleId': saleRef.id,
                  }, SetOptions(merge: true));

                  tx.set(db.collection('stockMovements').doc('${saleRef.id}_${e.id}'), {
                    'productId': e.id,
                    'productName': '${liveProducts[e.id]!['name']}',
                    'branchId': 'main',
                    'kind': 'sale',
                    'quantity': -e.qty,
                    'balanceAfter': after,
                    'referenceId': saleRef.id,
                    'actorId': actor,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }

                double previousCustomerBalance = 0;
                double customerBalanceAfter = 0;
                String customerName = '';
                String customerPhone = '';

                if (customerId.isNotEmpty) {
                  if (customerSnap == null || !customerSnap.exists || customerSnap.data()?['active'] == false) throw Exception('العميل غير موجود أو غير نشط');
                  previousCustomerBalance = (customerSnap.data()?['balance'] as num?)?.toDouble() ?? 0;
                  customerBalanceAfter = previousCustomerBalance + due;
                  customerName = '${customerSnap.data()?['name'] ?? ''}';
                  customerPhone = '${customerSnap.data()?['phone'] ?? ''}';
                  if (due > 0) {
                    tx.update(db.collection('customers').doc(customerId), {
                      'balance': customerBalanceAfter,
                      'lastSaleId': saleRef.id,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    tx.set(db.collection('accountMovements').doc('${saleRef.id}_customer'), {
                      'accountType': 'customers',
                      'accountId': customerId,
                      'accountName': customerName,
                      'kind': 'sale',
                      'amount': due,
                      'balanceBefore': previousCustomerBalance,
                      'balanceAfter': customerBalanceAfter,
                      'referenceId': saleRef.id,
                      'createdAt': FieldValue.serverTimestamp(),
                      'actorId': actor,
                    });
                  }
                }

                if (payment > 0) {
                  final beforeCash = (cashSnap?.data()?['balance'] as num?)?.toDouble() ?? 0;
                  final afterCash = beforeCash + payment;
                  tx.set(db.collection('settings').doc('cash'), {
                    'balance': afterCash,
                    'lastSaleId': saleRef.id,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                  tx.set(db.collection('accountMovements').doc('${saleRef.id}_cash'), {
                    'accountType': 'cash',
                    'kind': 'sale',
                    'accountId': customerId,
                    'accountName': customerName,
                    'amount': payment,
                    'delta': payment,
                    'balanceBefore': beforeCash,
                    'balanceAfter': afterCash,
                    'referenceId': saleRef.id,
                    'reason': 'تحصيل فاتورة مبيعات',
                    'actorId': actor,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }

                final invoiceData = <String, dynamic>{
                  'id': saleRef.id,
                  if(invoiceSerial!=null)'internalNumber':invoiceSerial.data['internalNumber'],
                  if(invoiceSerial!=null)'invoiceBarcode':invoiceSerial.data['invoiceBarcode'],
                  'branchId': actualBranch,
                  'stockBranchId': 'main',
                  'requestKey': requestKey,
                  'stockIndex': {for (var i = 0; i < items.length; i++) items[i]['productId'] as String: i},
                  'cashBefore': (cashSnap?.data()?['balance'] as num?)?.toDouble() ?? 0,
                  'cashAfter': ((cashSnap?.data()?['balance'] as num?)?.toDouble() ?? 0) + payment,
                  'employeeId': seller,
                  if(pending != null) 'employeeName': pending['employeeName'],
                  if(pending != null) 'approvedBy': actor,
                  if(pending != null) 'sourceRequestId': pendingRef!.id,
                  'customerId': customerId,
                  'customerName': customerName,
                  'customerPhone': customerPhone,
                  if(owner && invoiceNote.isNotEmpty) 'note':invoiceNote,
                  'customerPreviousBalance': previousCustomerBalance,
                  'customerBalanceAfter': customerBalanceAfter,
                  'items': items,
                  'itemCount': items.length,
                  'total': total,
                  'paid': payment,
                  'due': due,
                  'paymentStatus': due > 0 ? 'credit' : 'cash',
                  'status': 'completed',
                  'createdAt': FieldValue.serverTimestamp(),
                  if (items.length == 1) 'productId': items.first['productId'],
                  if (items.length == 1) 'productName': items.first['productName'],
                  if (items.length == 1) 'quantity': items.first['quantity'],
                  if (items.length == 1) 'unitPrice': items.first['unitPrice'],
                  if (owner && (allowShortage || allowBelowCost)) 'managerOverride': {
                    'reason': overrideReason,
                    'allowShortage': allowShortage,
                    'allowBelowCost': allowBelowCost,
                    'actorId': actor,
                  },
                };
                tx.set(saleRef, invoiceData);
                if(pendingRef != null) tx.update(pendingRef, {'status':'approved','saleId':saleRef.id,'reviewedBy':actor,'reviewedAt':FieldValue.serverTimestamp()});
                return {...invoiceData, 'createdAt': Timestamp.now()};

  });
}

Future<void> submitPendingSale(String id,List<SaleEntry> entries,String customerId,bool credit,double paid,double total) async {
  final uid=FirebaseAuth.instance.currentUser!.uid;
  final ref=db.collection('pendingSales').doc(id);
  final items=entries.map((e)=><String,dynamic>{'productId':e.id,'productName':e.name,'quantity':e.qty,
    'unitPrice':e.price,'basePrice':e.basePrice,'discountPercent':e.discount}).toList();
  final payload=<String,dynamic>{'customerId':customerId,'credit':credit,'paid':paid,'items':items};
  final parsed=PendingSaleData.parse(payload);
  final requestKey=jsonEncode(payload);
  await db.runTransaction((tx) async {
    final prior=(await tx.get(ref)).data();
    if(prior!=null) {
      if(prior['employeeId']!=uid || prior['requestKey']!=requestKey) throw Exception('الطلب موجود ببيانات مختلفة');
      return;
    }
    final profile=(await tx.get(db.collection('users').doc(uid))).data();
    final customer=(await tx.get(db.collection('customers').doc(customerId))).data();
    if(profile?['active']!=true || profile?['role']!='employee' || '${profile?['branchId'] ?? ''}'.isEmpty) throw Exception('حساب الموظف غير مفعل');
    if(customer==null || customer['active']==false) throw Exception('العميل غير موجود أو غير نشط');
    tx.set(ref,{...payload,'id':id,'employeeId':uid,'employeeName':'${profile?['name'] ?? ''}',
      'branchId':profile!['branchId'],'customerName':'${customer['name'] ?? ''}',
      'total':parsed.total,'status':'pending','createdAt':FieldValue.serverTimestamp(),'requestKey':requestKey});
  });
}

Query<Map<String,dynamic>> pendingSalesQuery(bool owner) => owner ? db.collection('pendingSales') :
  db.collection('pendingSales').where('employeeId',isEqualTo:FirebaseAuth.instance.currentUser!.uid);

class PendingSalesShortcut extends StatelessWidget {
  final bool owner;
  const PendingSalesShortcut({super.key,required this.owner});
  @override Widget build(BuildContext context)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:pendingSalesQuery(owner).snapshots(),builder:(context,snapshot) {
      final count=snapshot.data?.docs.where((d)=>d.data()['status']=='pending').length;
      return SizedBox(width:double.infinity,child:OutlinedButton.icon(icon:const Icon(Icons.pending_actions),
        label:Text('${owner ? 'اعتماد فواتير الموظفين' : 'فواتير الموظف — متابعة الاعتماد'}${count==null ? '' : ' ($count معلقة)'}'),
        onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Directionality(textDirection:TextDirection.rtl,
          child:Scaffold(appBar:AppBar(title:Text(owner?'اعتماد فواتير الموظفين':'فواتير الموظف')),body:PendingSalesPage(owner:owner)))))));
    });
}

class PendingSalesPage extends StatelessWidget {
  final bool owner;
  const PendingSalesPage({super.key,required this.owner});
  @override Widget build(BuildContext context)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:pendingSalesQuery(owner).snapshots(),builder:(context,snapshot) {
      if(snapshot.hasError) return const Center(child:Text('تعذر تحميل الطلبات. تأكد من الاتصال وتحديث قواعد الحماية.'));
      if(!snapshot.hasData) return const Center(child:CircularProgressIndicator());
      final rows=snapshot.data!.docs.where((d)=>visibleAfterReset(d.data())).toList()
        ..sort((a,b) {
          final pendingA=a.data()['status']=='pending',pendingB=b.data()['status']=='pending';
          if(pendingA!=pendingB)return pendingA?-1:1;
          return ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0);
        });
      return Column(children:[
        const Padding(padding:EdgeInsets.all(12),child:Text('فواتير الموظف فوق ٤ بنود تنتظر اعتماد المدير. الفواتير حتى ٤ بنود تُحفظ فورًا.',textAlign:TextAlign.center)),
        if(snapshot.data!.metadata.isFromCache)const Text('بيانات محفوظة على الجهاز؛ الحالة تتأكد عند الاتصال'),
        Expanded(child:rows.isEmpty?const Center(child:Text('لا توجد طلبات')):ListView(children:[for(final row in rows)
          Card(child:ListTile(leading:Icon(row.data()['status']=='approved'?Icons.check_circle:row.data()['status']=='rejected'?Icons.cancel:Icons.hourglass_top,color:gold),
            title:Text('${row.data()['customerName'] ?? ''} • ${row.data()['total'] ?? 0} ج.م'),
            subtitle:Text('${owner ? '${row.data()['employeeName'] ?? ''} • ' : ''}${pendingSaleStatus(row.data()['status'])} • ${formatDate(row.data()['createdAt'])}'),
            onTap:()=>reviewPendingSale(context,row.reference,owner))))])),
      ]);
    });
}

String pendingSaleStatus(Object? status)=>status=='approved'?'تم اعتماد الفاتورة':status=='rejected'?'مرفوضة — لم تسجل':'في انتظار الاعتماد';

Future<void> reviewPendingSale(BuildContext context,DocumentReference<Map<String,dynamic>> ref,bool owner) async {
  bool busy=false;
  await showDialog<void>(context:context,barrierDismissible:false,builder:(outer)=>StatefulBuilder(builder:(c,update)=>
    StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:ref.snapshots(),builder:(c,snapshot) {
      final data=snapshot.data?.data();
      if(data==null)return AlertDialog(title:const Text('طلب فاتورة موظف'),content:Text(snapshot.hasError?'تعذر تحميل الطلب':'جارٍ التحميل'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق'))]);
      final raw=data['items'] is List ? data['items'] as List : const [];
      final pending=data['status']=='pending';
      return AlertDialog(title:Text(pendingSaleStatus(data['status'])),content:SizedBox(width:600,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,mainAxisSize:MainAxisSize.min,children:[
        Text('العميل: ${data['customerName'] ?? ''}'),Text('الموظف: ${data['employeeName'] ?? ''}'),
        for(var i=0;i<raw.length;i++) if(raw[i] is Map) Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Text('${i+1}. ${raw[i]['productName']} — ${raw[i]['quantity']} × ${raw[i]['unitPrice']}')),
        Text('الإجمالي: ${data['total']} ج.م • المدفوع: ${data['paid']} ج.م'),
        if(pending)const Text('المخزون والحسابات لم تتغير بعد. الكمية والأسعار تُراجع وقت الاعتماد.'),
        if(data['status']=='rejected')Text('سبب الرفض: ${data['rejectionReason'] ?? ''}'),
      ]))),actions:[
        TextButton(onPressed:busy?null:()=>Navigator.pop(c),child:const Text('إغلاق')),
        if(owner && pending)TextButton(onPressed:busy?null:()async {
          final reason=TextEditingController();
          final result=await showDialog<String>(context:c,builder:(dialog)=>AlertDialog(title:const Text('رفض الطلب'),content:TextField(controller:reason,maxLength:500,decoration:const InputDecoration(labelText:'سبب الرفض')),
            actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('إلغاء')),FilledButton(onPressed:(){if(reason.text.trim().isNotEmpty)Navigator.pop(dialog,reason.text.trim());},child:const Text('رفض'))]));
          reason.dispose();if(result==null || !c.mounted)return;update(()=>busy=true);
          try {await db.runTransaction((tx) async {
            final current=(await tx.get(ref)).data();
            if(current?['status']!='pending')throw Exception('تمت مراجعة الطلب بالفعل');
            tx.update(ref,{'status':'rejected','rejectionReason':result,'reviewedBy':FirebaseAuth.instance.currentUser!.uid,'reviewedAt':FieldValue.serverTimestamp()});
          });if(c.mounted)Navigator.pop(c);}catch(e){if(c.mounted){update(()=>busy=false);await showInvoiceSaveProblem(c,invoiceSaveFailureMessage(e));}}
        },child:const Text('رفض مع السبب')),
        if(owner && pending)FilledButton(onPressed:busy?null:()async {
          update(()=>busy=true);
          try {
            final latest=(await ref.get(const GetOptions(source:Source.server))).data();
            if(latest==null)throw Exception('الطلب غير موجود');
            final parsed=PendingSaleData.parse(latest);
            final entries=parsed.lines.map((x)=>(id:x.id,name:'',qty:x.quantity,price:x.price,cost:null as double?,discount:x.discount,basePrice:x.basePrice)).toList();
            final saved=await commitGroupedSale(owner:true,branchId:'${latest['branchId']}',entries:entries,total:parsed.total,payment:parsed.paid,
              credit:parsed.credit,customerId:parsed.customerId,saleRef:db.collection('sales').doc(ref.id),pendingRef:ref);
            if(c.mounted)Navigator.pop(c);
            if(context.mounted)await showInvoiceSavedActions(context,'sales',ref.id,saved);
          }catch(e){if(c.mounted){update(()=>busy=false);await showInvoiceSaveProblem(c,invoiceSaveFailureMessage(e));}}
        },child:Text(busy?'جارٍ الاعتماد…':'اعتماد وحفظ')),
        if(data['status']=='approved')FilledButton(onPressed:busy?null:()async {
          update(()=>busy=true);
          try {final sale=(await db.collection('sales').doc(ref.id).get(const GetOptions(source:Source.server))).data();
            if(sale==null)throw Exception('تعذر العثور على الفاتورة المعتمدة');
            if(c.mounted)Navigator.pop(c);
            if(context.mounted)await invoiceActions(context,'sales',ref.id,sale,canReturn:owner);
          }catch(e){if(c.mounted){update(()=>busy=false);await showInvoiceSaveProblem(c,invoiceSaveFailureMessage(e));}}
        },child:const Text('عرض الفاتورة المعتمدة')),
      ]);
    })));
}
