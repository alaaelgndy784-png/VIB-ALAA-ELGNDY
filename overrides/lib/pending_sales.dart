part of 'main.dart';

typedef SaleEntry = ({String id, String name, int qty, double price, double? cost, double discount, double basePrice});

Future<void> submitManagerOfflineSale({required String id,required String branchId,required List<SaleEntry> entries,
  required String customerId,required bool credit,required double paid,required double total,required String note,
  required bool allowShortage,required bool allowBelowCost,required String overrideReason}) async {
  final uid=FirebaseAuth.instance.currentUser!.uid;
  final profile=(await db.collection('users').doc(uid).get(const GetOptions(source:Source.cache))).data();
  final customer=customerId.isEmpty?null:(await db.collection('customers').doc(customerId).get(const GetOptions(source:Source.cache))).data();
  if(profile?['active']!=true||profile?['role']!='owner'||(customerId.isNotEmpty&&(customer==null||customer['active']==false))||
    (customerId.isEmpty&&(credit||((paid-total).abs()>0.000001)))) {
    throw StateError('يلزم توفر بيانات المدير والعميل المحفوظة على الجهاز قبل تسجيل فاتورة دون اتصال');
  }
  final items=entries.map((e)=><String,dynamic>{'productId':e.id,'productName':e.name,'quantity':e.qty,
    'unitPrice':e.price,'basePrice':e.basePrice,'discountPercent':e.discount}).toList();
  final payload=<String,dynamic>{'id':id,'employeeId':uid,'employeeName':'${profile?['name']??''}',
    'branchId':branchId,'customerId':customerId,'customerName':'${customer?['name']??''}',
    'credit':credit,'paid':paid,'items':items,'total':total,'status':'pending',
    'managerOffline':true,'note':note,'allowShortage':allowShortage,'allowBelowCost':allowBelowCost,
    'overrideReason':overrideReason,'createdAt':FieldValue.serverTimestamp(),
    'requestKey':jsonEncode({'customerId':customerId,'credit':credit,'paid':paid,'items':items})};
  final write=db.collection('pendingSales').doc(id).set(payload);
  // Firestore persists this local write immediately; its future may remain
  // pending until the server acknowledges it after reconnection.
  unawaited(write.then<void>((_) {},onError:(Object error,StackTrace _) {
    debugPrint('VIB offline sale sync failed for $id: $error');
  }));
}

class ManagerOfflineSaleSync {
  ManagerOfflineSaleSync._();
  static final instance=ManagerOfflineSaleSync._();
  StreamSubscription<QuerySnapshot<Map<String,dynamic>>>? _subscription;
  final Set<String> _inFlight={},_failedThisSession={};
  void start() {
    if(_subscription!=null)return;
    _subscription=pendingSalesQuery(true).snapshots(includeMetadataChanges:true).listen((snapshot){
      if(snapshot.metadata.isFromCache||snapshot.metadata.hasPendingWrites)return;
      for(final doc in snapshot.docs) {
        if(doc.data()['managerOffline']!=true||doc.data()['status']!='pending'||doc.metadata.hasPendingWrites||
          _inFlight.contains(doc.id)||_failedThisSession.contains(doc.id))continue;
        _inFlight.add(doc.id);
        unawaited(_process(doc));
      }
    },onError:(Object _){});
  }
  Future<void> _process(QueryDocumentSnapshot<Map<String,dynamic>> doc) async {
    try {await _syncOne(doc);_failedThisSession.remove(doc.id);}
    catch (error) {
      // Keep the draft intact for manager review; never discard an offline invoice.
      if(!isTemporaryFirestoreOffline(error))_failedThisSession.add(doc.id);
    } finally {_inFlight.remove(doc.id);}
  }
  Future<void> _syncOne(QueryDocumentSnapshot<Map<String,dynamic>> doc) async {
    final data=doc.data();
    final proposal=PendingSaleData.parse(data);
    final rawItems=(data['items'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
    final entries=<SaleEntry>[];
    for(final line in proposal.lines) {
      final item=rawItems.firstWhere((x)=>x['productId']==line.id);
      entries.add((id:line.id,name:'${item['productName']??''}',
        qty:line.quantity,price:line.price,cost:null,discount:line.discount,basePrice:line.basePrice));
    }
    await commitGroupedSale(owner:true,branchId:'${data['branchId']}',entries:entries,total:proposal.total,
      payment:proposal.paid,credit:proposal.credit,customerId:proposal.customerId,
      saleRef:db.collection('sales').doc(doc.id),invoiceNote:'${data['note']??''}',
      allowShortage:data['allowShortage']==true,allowBelowCost:data['allowBelowCost']==true,
      overrideReason:'${data['overrideReason']??''}',pendingRef:doc.reference);
  }
  void stop(){_subscription?.cancel();_subscription=null;_inFlight.clear();_failedThisSession.clear();}
}

// The owner commits stock, accounts, invoice number and approval in one transaction.
Future<Map<String,dynamic>> commitGroupedSale({required bool owner, required String branchId,
  required List<SaleEntry> entries, required double total, required double payment,
  required bool credit, required String customerId,
  required DocumentReference<Map<String,dynamic>> saleRef,
  String invoiceNote='', bool allowShortage=false, bool allowBelowCost=false, String overrideReason='',
  DocumentReference<Map<String,dynamic>>? pendingRef, Map<String,double> managerPriceEdits=const {}}) async {
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
                final managerOffline=pending?['managerOffline']==true && owner && pending?['employeeId']==actor;
                if (pendingRef != null && (pending == null || pending['status'] != 'pending' ||
                    sellerProfile?['active'] != true || (managerOffline ? (sellerProfile?['role']!='owner') : (sellerProfile?['role']!='employee')) ||
                    (!managerOffline && sellerProfile?['branchId'] != actualBranch))) {
                  throw Exception('الطلب لم يعد معلقًا أو حساب الموظف غير مفعل');
                }
                if(managerPriceEdits.isNotEmpty && (!owner || pending==null || pending['managerOffline']==true ||
                  managerPriceEdits.keys.any((id)=>!entries.any((e)=>e.id==id && managerPriceEdits[id]==e.price)))) {
                  throw Exception('تعديل السعر مسموح للمدير أثناء مراجعة فاتورة الموظف فقط');
                }
                PendingSaleData? pendingProposal;
                if(pending != null) {
                  final proposal=PendingSaleData.parse(pending);
                  pendingProposal=proposal;
                  final cashManagerEdit=owner && managerPriceEdits.isNotEmpty && !proposal.credit && payment==total;
                  if(proposal.customerId!=customerId || proposal.credit!=credit || (proposal.paid!=payment && !cashManagerEdit) || proposal.lines.length!=entries.length ||
                    List.generate(entries.length,(i)=>proposal.lines[i].id!=entries[i].id || proposal.lines[i].quantity!=entries[i].qty ||
                      (proposal.lines[i].price!=entries[i].price && managerPriceEdits[entries[i].id]!=entries[i].price) ||
                      proposal.lines[i].basePrice!=entries[i].basePrice || proposal.lines[i].discount!=entries[i].discount).any((x)=>x)) {
                    throw Exception('بيانات الطلب اتغيرت؛ افتحه من جديد');
                  }
                }
                final liveProducts = <String, Map<String, dynamic>>{};
                for (final e in entries) {
                  final product = (await tx.get(db.collection('products').doc(e.id))).data();
                  if (product == null || product['active'] != true) throw Exception('الصنف غير متاح');
                  if ((!owner || (pending != null && pending['managerOffline']!=true)) && sellerProfile?['canEditSalePrice']!=true && ((product['price'] as num?)?.toDouble() != e.basePrice || (e.price-e.basePrice*(1-e.discount/100)).abs()>0.000001)) {
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
                  if(managerPriceEdits.isNotEmpty) 'managerPriceEdits': {
                    'actorId':actor,
                    'items':entries.where((e)=>managerPriceEdits.containsKey(e.id)).map((e)=>{
                      'productId':e.id,
                      'from':pendingProposal!.lines.firstWhere((line)=>line.id==e.id).price,
                      'to':e.price,
                    }).toList(),
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
      final count=snapshot.data?.docs.where((d)=>pendingSaleIsVisible(d.data()) && d.data()['status']=='pending').length;
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
      final rows=snapshot.data!.docs.where((d)=>visibleAfterReset(d.data()) && pendingSaleIsVisible(d.data())).toList()
        ..sort((a,b) {
          final pendingA=a.data()['status']=='pending',pendingB=b.data()['status']=='pending';
          if(pendingA!=pendingB)return pendingA?-1:1;
          return ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0);
        });
      return Column(children:[
        const Padding(padding:EdgeInsets.all(12),child:Text('فواتير الموظف الكبيرة تنتظر اعتماد المدير. فواتير المدير التي سُجلت دون اتصال تُراجع وتُزامن تلقائيًا عند رجوع الإنترنت.',textAlign:TextAlign.center)),
        if(snapshot.data!.metadata.isFromCache)const Text('بيانات محفوظة على الجهاز؛ الحالة تتأكد عند الاتصال'),
        Expanded(child:rows.isEmpty?const Center(child:Text('لا توجد طلبات')):ListView(children:[for(final row in rows)
          Card(child:ListTile(leading:Icon(row.data()['status']=='approved'?Icons.check_circle:row.data()['status']=='rejected'?Icons.cancel:Icons.hourglass_top,color:gold),
            title:Text('${row.data()['customerName'] ?? ''} • ${row.data()['total'] ?? 0} ج.م'),
            subtitle:Text('${owner ? '${row.data()['employeeName'] ?? ''} • ' : ''}${row.data()['managerOffline']==true?'فاتورة مدير تنتظر المزامنة':'${pendingSaleStatus(row.data()['status'])}'} • ${formatDate(row.data()['createdAt'])}'),
            trailing:owner && row.data()['status']=='rejected' ? IconButton(tooltip:'مسح الطلب من التطبيقين',icon:const Icon(Icons.delete_outline,color:Colors.redAccent),onPressed:()=>removeRejectedPendingSale(context,row.reference)) : null,
            onTap:()=>reviewPendingSale(context,row.reference,owner)))])),
      ]);
    });
}

String pendingSaleStatus(Object? status)=>status=='approved'?'تم اعتماد الفاتورة':status=='rejected'?'مرفوضة — لم تسجل':'في انتظار الاعتماد';

bool pendingSaleIsVisible(Map<String,dynamic> data)=>data['removed']!=true;

String pendingApprovalAlertText(String employeeName,String requestId,Map<String,dynamic> data) {
  final parsed=PendingSaleData.parse(data);
  final customer='${data['customerName'] ?? 'عميل'}';
  final shortId=requestId.substring(0,requestId.length < 8 ? requestId.length : 8);
  return '🔔 طلب اعتماد فاتورة من $employeeName • العميل $customer • ${parsed.total.toStringAsFixed(2)} ج.م • طلب $shortId';
}

Future<bool> requestPendingSaleApproval(DocumentReference<Map<String,dynamic>> ref) async {
  final uid=FirebaseAuth.instance.currentUser?.uid;
  if(uid==null)throw StateError('سجّل الدخول مرة أخرى');
  final thread=db.collection('staffChats').doc(uid),messageRef=thread.collection('messages').doc();
  await db.runTransaction((tx) async {
    final current=(await tx.get(ref)).data();
    final employee=(await tx.get(db.collection('users').doc(uid))).data();
    if(current==null || current['status']!='pending' || current['employeeId']!=uid)
      throw StateError('الفاتورة لم تعد في انتظار اعتمادك');
    if(employee?['role']!='employee' || employee?['active']!=true)
      throw StateError('طلب الاعتماد متاح للموظف المفعل فقط');
    final text=pendingApprovalAlertText('${employee?['name'] ?? ''}',ref.id,current);
    final now=FieldValue.serverTimestamp();
    tx.set(messageRef,{'senderId':uid,'senderName':'${employee?['name'] ?? ''}',
      'senderRole':'employee','text':text,'createdAt':now});
    tx.set(thread,{'employeeId':uid,'employeeName':'${employee?['name'] ?? ''}',
      'branchId':'${employee?['branchId'] ?? ''}','lastMessageId':messageRef.id,
      'lastText':text,'lastSenderId':uid,'lastSenderRole':'employee','lastMessageAt':now},SetOptions(merge:true));
  });
  return true;
}

// Keep the rejected payload and audit trail; hide it in both applications.
Future<bool> removeRejectedPendingSale(BuildContext context,DocumentReference<Map<String,dynamic>> ref) async {
  final confirmed=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
    title:const Text('مسح الطلب المرفوض'),
    content:const Text('سيختفي الطلب من عندك ومن عند الموظف. الموظف يبدأ فاتورة جديدة من شاشة المبيعات.'),
    actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),
      FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('مسح من التطبيقين'))]));
  if(confirmed!=true || !context.mounted)return false;
  try {
    await db.runTransaction((tx)async {
      final current=(await tx.get(ref)).data();
      if(current==null || current['status']!='rejected')throw Exception('المسح متاح للطلبات المرفوضة فقط');
      if(current['removed']==true)return;
      tx.update(ref,{'removed':true,'removedBy':FirebaseAuth.instance.currentUser!.uid,'removedAt':FieldValue.serverTimestamp()});
    });
    return true;
  }catch(e){if(context.mounted)await showInvoiceSaveProblem(context,invoiceSaveFailureMessage(e));return false;}
}

class PendingSaleInvoiceDialog extends StatelessWidget {
  final Map<String,dynamic> data;
  final List<Widget> actions;
  const PendingSaleInvoiceDialog({super.key,required this.data,required this.actions});
  @override Widget build(BuildContext context) {
    final items=(data['items'] as List? ?? const []).whereType<Map>().toList();
    final total=items.fold<double>(0,(sum,x)=>sum+((x['unitPrice'] as num?)?.toDouble() ?? 0)*((x['quantity'] as num?)?.toInt() ?? 0));
    final paid=(data['paid'] as num?)?.toDouble() ?? 0;
    final quantity=items.fold<int>(0,(sum,x)=>sum+((x['quantity'] as num?)?.toInt() ?? 0));
    Widget money(String label,double value)=>Text('$label: ${value.toStringAsFixed(2)} ج.م',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold));
    return Directionality(textDirection:TextDirection.rtl,child:Dialog(
      backgroundColor:const Color(0xFF080808),insetPadding:const EdgeInsets.symmetric(horizontal:6,vertical:12),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:const BorderSide(color:gold)),
      child:SizedBox(width:650,height:double.infinity,child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[
        const Padding(padding:EdgeInsets.only(bottom:8),child:Text('فاتورة مبيعات الموظف',textAlign:TextAlign.center,style:TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:gold))),
        Expanded(child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Container(color:const Color(0xFF282215),padding:const EdgeInsets.all(8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(pendingSaleStatus(data['status']),style:const TextStyle(color:gold,fontWeight:FontWeight.bold)),
            Text('العميل: ${data['customerName'] ?? ''}'),Text('الموظف: ${data['employeeName'] ?? ''}'),
            Text('التاريخ: ${formatDate(data['createdAt'])}'),
            if(data['status']!='approved')const Text('رقم الفاتورة: يُخصص عند الاعتماد'),
            Text(data['credit']==true?'طريقة الدفع: آجل':'طريقة الدفع: نقدي'),
            if(data['managerPriceEditPreview']==true)const Text('الأسعار المعروضة معدلة من المدير قبل الاعتماد.',style:TextStyle(color:Colors.lightBlueAccent)),
          ])),
          const SizedBox(height:8),const InvoiceCompactTableHeader(),
          for(var i=0;i<items.length;i++)InvoiceCompactReadOnlyLine(number:i+1,name:'${items[i]['productName'] ?? ''}',
            price:(items[i]['unitPrice'] as num?)?.toDouble() ?? 0,quantity:(items[i]['quantity'] as num?)?.toInt() ?? 0),
          const SizedBox(height:8),
          if(data['status']=='pending')const Text('الكمية والأسعار تُراجع وقت الاعتماد. المخزون والحسابات لم تتغير بعد.'),
          if(data['status']=='rejected')Text('سبب الرفض: ${data['rejectionReason'] ?? ''}'),
        ]))),
        Container(width:double.infinity,color:const Color(0xFF282215),padding:const EdgeInsets.all(8),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text('الأصناف: ${items.length} • العدد: $quantity',style:const TextStyle(color:Colors.white,fontSize:12)),
          Text('الإجمالي: ${total.toStringAsFixed(2)} ج.م',style:const TextStyle(color:gold,fontSize:20,fontWeight:FontWeight.bold)),
          Wrap(spacing:16,runSpacing:4,children:[money('المدفوع',paid),money('المتبقي',total-paid)]),
        ])),
        const SizedBox(height:6),Wrap(alignment:WrapAlignment.end,spacing:6,runSpacing:4,children:actions),
      ]))),
    ));
  }
}

Future<({Map<String,double> prices,double paid})?> editPendingSalePrices(
    BuildContext context, Map<String,dynamic> data, Map<String,double> currentPrices) async {
  final proposal=PendingSaleData.parse(data);
  final names=<String,String>{for(final raw in (data['items'] as List? ?? const []).whereType<Map>())
    '${raw['productId']}':'${raw['productName']??raw['productId']}'};
  final values=<String,double>{for(final line in proposal.lines)line.id:currentPrices[line.id]??line.price};
  bool valid=true;
  double total=0;
  double paid=proposal.paid;
  void recalculate(){
    total=proposal.lines.fold<double>(0,(sum,line)=>sum+line.quantity*(values[line.id]??line.price));
    paid=proposal.credit?proposal.paid:total;
    valid=proposal.lines.every((line)=>values[line.id]!=null && values[line.id]!.isFinite && values[line.id]!>0) && paid<=total;
  }
  recalculate();
  return showDialog<({Map<String,double> prices,double paid})>(context:context,builder:(dialog)=>StatefulBuilder(builder:(dialog,update){
    recalculate();
    return Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
      title:const Text('تعديل أسعار الفاتورة'),
      content:SizedBox(width:500,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final line in proposal.lines)Padding(padding:const EdgeInsets.only(bottom:10),child:Row(children:[
          Expanded(child:Text('${names[line.id]??line.id} × ${line.quantity}',maxLines:2,overflow:TextOverflow.ellipsis)),
          const SizedBox(width:8),SizedBox(width:120,child:TextFormField(
            key:ValueKey('manager-price-${line.id}'),initialValue:'${values[line.id]}',
            keyboardType:const TextInputType.numberWithOptions(decimal:true),
            decoration:const InputDecoration(labelText:'سعر الوحدة'),
            onChanged:(text){final value=double.tryParse(text.trim());update(()=>values[line.id]=value??double.nan);},
          )),
        ])),
        const Divider(),
        Align(alignment:AlignmentDirectional.centerStart,child:Text('الإجمالي بعد التعديل: ${total.toStringAsFixed(2)} ج.م',style:const TextStyle(fontWeight:FontWeight.bold))),
        Align(alignment:AlignmentDirectional.centerStart,child:Text(proposal.credit
          ? 'المدفوع: ${paid.toStringAsFixed(2)} • المتبقي: ${(total-paid).toStringAsFixed(2)} ج.م'
          : 'المدفوع النقدي بعد التعديل: ${paid.toStringAsFixed(2)} ج.م')),
        if(!valid)const Align(alignment:AlignmentDirectional.centerStart,child:Text('راجع الأسعار؛ لا يمكن أن يتجاوز المدفوع إجمالي الفاتورة.',style:TextStyle(color:Colors.redAccent))),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('إلغاء')),
        FilledButton(onPressed:valid?()=>Navigator.pop(dialog,(prices:Map<String,double>.from(values),paid:paid)):null,child:const Text('تطبيق الأسعار'))],
    ));
  }));
}

Future<void> reviewPendingSale(BuildContext context,DocumentReference<Map<String,dynamic>> ref,bool owner) async {
  bool busy=false;
  Map<String,double> adjustedPrices={};
  double? adjustedPaid;
  await showDialog<void>(context:context,barrierDismissible:false,builder:(outer)=>StatefulBuilder(builder:(c,update)=>
    StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:ref.snapshots(),builder:(c,snapshot) {
      final data=snapshot.data?.data();
      if(data==null)return AlertDialog(title:const Text('طلب فاتورة موظف'),content:Text(snapshot.hasError?'تعذر تحميل الطلب':'جارٍ التحميل'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق'))]);
      if(!pendingSaleIsVisible(data))return AlertDialog(title:const Text('تم مسح الطلب'),content:const Text('ابدأ فاتورة جديدة من شاشة المبيعات.'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق'))]);
      final pending=data['status']=='pending';
      final rawItems=(data['items'] as List? ?? const []).whereType<Map>().map((x){
        final item=Map<String,dynamic>.from(x);final id='${item['productId']??''}';
        if(adjustedPrices.containsKey(id))item['unitPrice']=adjustedPrices[id];
        return item;
      }).toList();
      final displayData=<String,dynamic>{...data,'items':rawItems,if(adjustedPaid!=null)'paid':adjustedPaid,
        if(adjustedPrices.isNotEmpty)'managerPriceEditPreview':true};
      return PendingSaleInvoiceDialog(data:displayData,actions:[
        TextButton(onPressed:busy?null:()=>Navigator.pop(c),child:const Text('إغلاق')),
        if(!owner && pending) OutlinedButton.icon(
          onPressed:busy?null:()async {
            update(()=>busy=true);
            try {
              await requestPendingSaleApproval(ref);
              if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('وصل طلب الاعتماد للمدير، ورنّ تنبيه المحادثة.')));
            } catch(e) {
              if(c.mounted)await showInvoiceSaveProblem(c,'تعذر إرسال التنبيه: $e',title:'طلب اعتماد الفاتورة',button:'تمام');
            } finally { if(c.mounted)update(()=>busy=false); }
          },
          icon:const Icon(Icons.notifications_active,color:Colors.greenAccent),
          label:Text(busy?'جارٍ إرسال التنبيه…':'رنّ عند المدير')),
        if(owner && data['status']=='rejected')TextButton.icon(icon:const Icon(Icons.delete_outline,color:Colors.redAccent),label:const Text('مسح الطلب'),
          onPressed:busy?null:()async {update(()=>busy=true);final removed=await removeRejectedPendingSale(c,ref);if(!c.mounted)return;if(removed)Navigator.pop(c);else update(()=>busy=false);}),
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
        if(owner && pending)OutlinedButton.icon(onPressed:busy?null:()async {
          try {
            final edited=await editPendingSalePrices(c,data,adjustedPrices);
            if(edited!=null && c.mounted)update((){adjustedPrices=edited.prices;adjustedPaid=edited.paid;});
          }catch(e){if(c.mounted)await showInvoiceSaveProblem(c,'تعذر تعديل الأسعار: $e',title:'تعديل الفاتورة',button:'تمام');}
        },icon:const Icon(Icons.edit,color:Colors.lightBlueAccent),label:const Text('تعديل الأسعار')),
        if(owner && pending)FilledButton(onPressed:busy?null:()async {
          update(()=>busy=true);
          try {
            final latest=(await ref.get(const GetOptions(source:Source.server))).data();
            if(latest==null)throw Exception('الطلب غير موجود');
            final parsed=PendingSaleData.parse(latest);
            final entries=parsed.lines.map((x)=>(id:x.id,name:x.name,qty:x.quantity,price:adjustedPrices[x.id]??x.price,cost:null as double?,discount:x.discount,basePrice:x.basePrice)).toList();
            final total=entries.fold<double>(0,(sum,e)=>sum+e.qty*e.price);
            final payment=parsed.credit?parsed.paid:total;
            final priceEdits=<String,double>{for(final e in entries)if((parsed.lines.firstWhere((line)=>line.id==e.id).price-e.price).abs()>0.000001)e.id:e.price};
            final saved=await commitGroupedSale(owner:true,branchId:'${latest['branchId']}',entries:entries,total:total,payment:payment,
              credit:parsed.credit,customerId:parsed.customerId,saleRef:db.collection('sales').doc(ref.id),pendingRef:ref,managerPriceEdits:priceEdits);
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
