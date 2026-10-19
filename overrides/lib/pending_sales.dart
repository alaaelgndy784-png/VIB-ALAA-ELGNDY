part of 'main.dart';

typedef SaleEntry = ({String id, String name, int qty, double price, double? cost, double discount, double basePrice});

// A second local copy is essential: Firestore's offline write can be rejected
// later if the backend returns RESOURCE_EXHAUSTED. Never acknowledge a draft as
// a posted sale until it has a server-confirmed sales document.
class ManagerOfflineDraftStore {
  ManagerOfflineDraftStore._();
  static final instance=ManagerOfflineDraftStore._();
  final ValueNotifier<int> pendingCount=ValueNotifier<int>(0);
  Future<void> _lastMutation=Future<void>.value();
  bool _syncing=false;
  String _key(String uid)=>'vib_manager_offline_drafts_v1_$uid';

  Future<T> _locked<T>(Future<T> Function() task) {
    final previous=_lastMutation;
    final completed=Completer<void>();
    _lastMutation=completed.future;
    return () async {
      await previous;
      try {return await task();}
      finally {completed.complete();}
    }();
  }

  Future<List<Map<String,dynamic>>> _read(String uid) async {
    final prefs=await SharedPreferences.getInstance();
    final raw=prefs.getString(_key(uid));
    if(raw==null||raw.isEmpty)return <Map<String,dynamic>>[];
    final decoded=jsonDecode(raw);
    if(decoded is! List)throw const FormatException('ملف الفواتير المعلقة على الجهاز غير صحيح');
    return decoded.map((item) {
      if(item is! Map)throw const FormatException('فاتورة معلقة محلية غير صحيحة');
      return Map<String,dynamic>.from(item);
    }).toList();
  }

  Future<void> _write(String uid,List<Map<String,dynamic>> docs) async {
    final prefs=await SharedPreferences.getInstance();
    if(!await prefs.setString(_key(uid),jsonEncode(docs))) {
      throw StateError('تعذر تأمين نسخة من الفاتورة على الجهاز');
    }
    pendingCount.value=docs.length;
  }

  Future<void> preserve(String id,Map<String,dynamic> payload) async {
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null)throw StateError('لا يوجد حساب مدير مسجل');
    final safe=Map<String,dynamic>.from(payload)
      ..remove('createdAt')..remove('reviewedAt')..remove('reviewedBy');
    safe['id']=id;
    safe['draftStoredAtMs'] ??=DateTime.now().millisecondsSinceEpoch;
    if(safe['managerOffline']!=true||safe['employeeId']!=uid||
        safe['status']!='pending')throw StateError('هذه ليست فاتورة مدير معلقة');
    PendingSaleData.parse(safe);
    await _locked(() async {
      final docs=await _read(uid);
      final index=docs.indexWhere((doc)=>doc['id']==id);
      if(index>=0) {
        if(docs[index]['employeeId']!=uid ||
            docs[index]['requestKey']!=safe['requestKey']) {
          throw StateError('الفاتورة محفوظة محليًا ببيانات مختلفة؛ لا تنشئ نسخة أخرى');
        }
        safe['draftStoredAtMs']=docs[index]['draftStoredAtMs'];
        docs[index]=safe;
      } else {
        if(docs.length>=250)throw StateError('الذاكرة بها 250 فاتورة معلقة؛ يلزم إتمام المزامنة');
        docs.add(safe);
      }
      await _write(uid,docs);
    });
  }

  Future<void> loadPendingCount() async {
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null)return;
    try {
      final docs=await _locked(() => _read(uid));
      pendingCount.value=docs.length;
    } catch(error) {
      debugPrint('VIB manager local draft count unavailable: $error');
    }
  }

  Future<void> discard(String id) async {
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null)return;
    await _locked(() async {
      final docs=await _read(uid);
      docs.removeWhere((doc)=>doc['id']==id);
      await _write(uid,docs);
    });
  }

  // Explicit retry / app resume only, not a continuous quota-consuming loop.
  Future<void> syncPending() async {
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null||_syncing)return;
    _syncing=true;
    try {
      final docs=await _locked(() => _read(uid));
      pendingCount.value=docs.length;
      for(final row in docs) {
        final id='${row['id']??''}';
        if(id.isEmpty)continue;
        try {
          final posted=await db.collection('sales').doc(id)
            .get(const GetOptions(source:Source.server))
            .timeout(const Duration(seconds:6));
          if(posted.exists) {
            if(posted.data()?['employeeId']!=uid) {
              debugPrint('VIB manager draft ID collision: $id');
              continue;
            }
            await discard(id);
            continue;
          }
          final ref=db.collection('pendingSales').doc(id);
          final pending=await ref.get(const GetOptions(source:Source.server))
            .timeout(const Duration(seconds:6));
          if(pending.exists) {
            if(pending.data()?['managerOffline']!=true ||
                pending.data()?['employeeId']!=uid ||
                pending.data()?['requestKey']!=row['requestKey']) {
              debugPrint('VIB manager pending draft differs from server: $id');
              continue;
            }
            // The server has a durable pending document; its normal approval
            // pipeline will post the sale with the same unique ID.
            await discard(id);
            continue;
          }
          final upload=Map<String,dynamic>.from(row)
            ..remove('draftStoredAtMs');
          upload['createdAt']=Timestamp.fromMillisecondsSinceEpoch(
              (row['draftStoredAtMs'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch);
          await ref.set(upload).timeout(const Duration(seconds:10));
          await discard(id);
        } catch(error) {
          debugPrint('VIB manager draft $id awaits server recovery: $error');
          if(isTemporaryFirestoreOffline(error)||isFirestoreQuotaExhausted(error))break;
          // Keep the original on device for investigation, never delete it.
        }
      }
    } catch(error) {
      debugPrint('VIB manager pending draft storage error: $error');
    } finally {_syncing=false;}
  }
}

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
  // A server quota rejection can roll back the Firestore cache. Preserve the
  // invoice on local device storage before asking Firestore to upload it.
  await ManagerOfflineDraftStore.instance.preserve(id,payload);
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
    unawaited(ManagerOfflineDraftStore.instance.loadPendingCount());
    _subscription=pendingSalesQuery(true)
      .where('status',isEqualTo:'pending')
      .snapshots(includeMetadataChanges:true).listen((snapshot){
      if(snapshot.metadata.isFromCache||snapshot.metadata.hasPendingWrites) {
        // Recover pending drafts created by versions before local backup existed.
        for(final doc in snapshot.docs) {
          if(doc.data()['managerOffline']==true && doc.data()['status']=='pending') {
            unawaited(ManagerOfflineDraftStore.instance.preserve(doc.id,doc.data())
              .catchError((Object e) {debugPrint('VIB local pending invoice backup: $e');}));
          }
        }
        return;
      }
      for(final doc in snapshot.docs) {
        if(doc.data()['managerOffline']!=true||doc.data()['status']!='pending'||doc.metadata.hasPendingWrites||
          _inFlight.contains(doc.id)||_failedThisSession.contains(doc.id))continue;
        _inFlight.add(doc.id);
        unawaited(_process(doc));
      }
    },onError:(Object _){});
  }
  Future<void> _process(QueryDocumentSnapshot<Map<String,dynamic>> doc) async {
    try {
      await _syncOne(doc);
      await ManagerOfflineDraftStore.instance.discard(doc.id);
      _failedThisSession.remove(doc.id);
    }
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
      payment:proposal.paid,paymentBreakdown:proposal.paymentBreakdown,credit:proposal.credit,customerId:proposal.customerId,
      saleRef:db.collection('sales').doc(doc.id),invoiceNote:'${data['note']??''}',
      allowShortage:data['allowShortage']==true,allowBelowCost:data['allowBelowCost']==true,
      overrideReason:'${data['overrideReason']??''}',pendingRef:doc.reference);
  }
  Future<void> retryAfterServerRecovery() async {
    // Quota errors are not retried in a tight loop. A deliberate refresh or
    // app foreground event allows one new attempt against confirmed documents.
    _failedThisSession.clear();
    await _subscription?.cancel();
    _subscription=null;
    start();
  }
  void stop(){_subscription?.cancel();_subscription=null;_inFlight.clear();_failedThisSession.clear();}
}

// The owner commits stock, accounts, invoice number and approval in one transaction.
Future<Map<String,dynamic>> commitGroupedSale({required bool owner, required String branchId,
  required List<SaleEntry> entries, required double total, required double payment,
  Map<String,double>? paymentBreakdown,
  required bool credit, required String customerId,
  required DocumentReference<Map<String,dynamic>> saleRef,
  String invoiceNote='', bool allowShortage=false, bool allowBelowCost=false, String overrideReason='',
  DocumentReference<Map<String,dynamic>>? pendingRef}) async {
  final tender=normalizeSalePaymentBreakdown(paymentBreakdown,payment);
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
                final requestKey = jsonEncode({'customerId': customerId, 'credit': credit, 'paid': payment,'paymentBreakdown':tender,
                  if(owner) 'note':invoiceNote,
                  'items': entries.map((e) => {'id': e.id, 'qty': e.qty, 'price': e.price}).toList()});
                final managerOffline=pending?['managerOffline']==true && owner && pending?['employeeId']==actor;
                final priorSale = (await tx.get(saleRef)).data();
                if (priorSale != null) {
                  // A transaction that timed out on the phone may have completed when
                  // the network returned. The same sale ID must never debit stock twice.
                  final reconciledOffline = managerOffline && priorSale['sourceRequestId'] == null;
                  if (priorSale['employeeId'] != seller || priorSale['requestKey'] != requestKey ||
                      (pendingRef != null && priorSale['sourceRequestId'] != pendingRef.id && !reconciledOffline)) {
                    throw Exception('الفاتورة محفوظة بالفعل ببيانات مختلفة');
                  }
                  if (reconciledOffline && pendingRef != null) {
                    tx.update(pendingRef, {'status':'approved','saleId':saleRef.id,
                      'reviewedBy':actor,'reviewedAt':FieldValue.serverTimestamp()});
                  }
                  return priorSale;
                }
                if (pendingRef != null && (pending == null || pending['status'] != 'pending' ||
                    sellerProfile?['active'] != true || (managerOffline ? (sellerProfile?['role']!='owner') : (sellerProfile?['role']!='employee')) ||
                    (!managerOffline && sellerProfile?['branchId'] != actualBranch))) {
                  throw Exception('الطلب لم يعد معلقًا أو حساب الموظف غير مفعل');
                }
                if(pending != null) {
                  final proposal=PendingSaleData.parse(pending);
                  if(proposal.customerId!=customerId || proposal.credit!=credit || proposal.paid!=payment ||
                    jsonEncode(proposal.paymentBreakdown)!=jsonEncode(tender) || proposal.lines.length!=entries.length ||
                    List.generate(entries.length,(i)=>proposal.lines[i].id!=entries[i].id || proposal.lines[i].quantity!=entries[i].qty ||
                      proposal.lines[i].price!=entries[i].price || proposal.lines[i].basePrice!=entries[i].basePrice || proposal.lines[i].discount!=entries[i].discount).any((x)=>x)) {
                    throw Exception('بيانات الطلب اتغيرت؛ افتحه من جديد');
                  }
                }
                final liveProducts = <String, Map<String, dynamic>>{};
                for (final e in entries) {
                  final product = (await tx.get(db.collection('products').doc(e.id))).data();
                  if (product == null || product['active'] != true) throw Exception('الصنف غير متاح');
                  final managerReviewedPrice=owner && pending?['managerPriceAdjusted']==true;
                  if ((!owner || (pending != null && pending['managerOffline']!=true)) && !managerReviewedPrice && sellerProfile?['canEditSalePrice']!=true && ((product['price'] as num?)?.toDouble() != e.basePrice || (e.price-e.basePrice*(1-e.discount/100)).abs()>0.000001)) {
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
                  'paymentBreakdown':tender,
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

Future<void> submitPendingSale(String id,List<SaleEntry> entries,String customerId,bool credit,double paid,double total,
    {Map<String,double>? paymentBreakdown}) async {
  final uid=FirebaseAuth.instance.currentUser!.uid;
  final ref=db.collection('pendingSales').doc(id);
  final items=entries.map((e)=><String,dynamic>{'productId':e.id,'productName':e.name,'quantity':e.qty,
    'unitPrice':e.price,'basePrice':e.basePrice,'discountPercent':e.discount}).toList();
  final tender=normalizeSalePaymentBreakdown(paymentBreakdown,paid);
  final payload=<String,dynamic>{'customerId':customerId,'credit':credit,'paid':paid,
    'paymentBreakdown':tender,'items':items};
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
  final bool compact;
  const PendingSalesShortcut({super.key,required this.owner,this.compact=false});
  @override Widget build(BuildContext context)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:pendingSalesQuery(owner).snapshots(),builder:(context,snapshot) {
      final count=snapshot.data?.docs.where((d)=>pendingSaleIsVisible(d.data()) && d.data()['status']=='pending').length;
      return SizedBox(width:double.infinity,child:OutlinedButton.icon(
        style:compact ? OutlinedButton.styleFrom(visualDensity:VisualDensity.compact,minimumSize:const Size.fromHeight(38),padding:const EdgeInsets.symmetric(horizontal:8)) : null,
        icon:Icon(Icons.pending_actions,color:owner?vibBlue:vibNeon,size:compact?18:null),
        label:Text('${owner ? 'اعتماد فواتير الموظفين' : 'فواتير الموظف — متابعة الاعتماد'}${count==null ? '' : ' ($count معلقة)'}',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:owner?vibBlue:vibNeon)),
        onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Directionality(textDirection:TextDirection.rtl,
          child:Scaffold(appBar:AppBar(title:Text(owner?'اعتماد فواتير الموظفين':'فواتير الموظف')),body:PendingSalesPage(owner:owner)))))));
    });
}

class ManagerOfflineDraftBanner extends StatelessWidget {
  const ManagerOfflineDraftBanner({super.key});
  @override Widget build(BuildContext context)=>ValueListenableBuilder<int>(
    valueListenable:ManagerOfflineDraftStore.instance.pendingCount,
    builder:(context,count,_) {
      if(count==0)return const SizedBox.shrink();
      return Card(color:const Color(0xFF3B321C),child:Padding(
        padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),
        child:Column(children:[
          Text('$count فاتورة مدير محفوظة بنسخة أمان على هذا الجهاز. لم تُعتمد ماليًا بعد.',
            style:const TextStyle(color:Colors.white)),
          TextButton.icon(
            onPressed:() {
              unawaited(ManagerOfflineDraftStore.instance.syncPending());
              unawaited(ManagerOfflineSaleSync.instance.retryAfterServerRecovery());
            },
            icon:const Icon(Icons.sync),
            label:const Text('إعادة المزامنة بعد عودة Firebase'),
          ),
        ]),
      ));
    },
  );
}

class PendingSalesPage extends StatelessWidget {
  final bool owner;
  const PendingSalesPage({super.key,required this.owner});
  @override Widget build(BuildContext context)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:pendingSalesQuery(owner).snapshots(),builder:(context,snapshot) {
      if(snapshot.hasError)return Column(children:[
        if(owner)const ManagerOfflineDraftBanner(),
        const Expanded(child:Center(child:Text('تعذر تحميل الطلبات من السيرفر. الفواتير المحفوظة على الجهاز لا تُحذف.'))),
      ]);
      if(!snapshot.hasData)return Column(children:[
        if(owner)const ManagerOfflineDraftBanner(),
        const Expanded(child:Center(child:CircularProgressIndicator())),
      ]);
      final rows=snapshot.data!.docs.where((d)=>visibleAfterReset(d.data()) && pendingSaleIsVisible(d.data())).toList()
        ..sort((a,b) {
          final pendingA=a.data()['status']=='pending',pendingB=b.data()['status']=='pending';
          if(pendingA!=pendingB)return pendingA?-1:1;
          return ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0);
        });
      return Column(children:[
        const Padding(padding:EdgeInsets.all(12),child:Text('فواتير الموظف تنتظر الاعتماد، وفواتير المدير دون إنترنت تنتظر تأكيد Firebase. لا يُخصم المخزون أو يُسجل الدين قبل نجاح الحفظ على السيرفر.',textAlign:TextAlign.center)),
        if(owner)const ManagerOfflineDraftBanner(),
        if(snapshot.data!.metadata.isFromCache)const Text('بيانات محفوظة على الجهاز؛ الحالة تتأكد عند الاتصال'),
        Expanded(child:rows.isEmpty?const Center(child:Text('لا توجد طلبات')):ListView(children:[for(final row in rows)
          Card(child:ListTile(leading:Icon(row.data()['status']=='approved'?Icons.check_circle:row.data()['status']=='rejected'?Icons.cancel:Icons.hourglass_top,color:gold),
            title:Text('${row.data()['customerName'] ?? ''} • ${row.data()['total'] ?? 0} ج.م',style:const TextStyle(color:vibNeon,fontWeight:FontWeight.bold)),
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

class PendingSaleInvoiceDialog extends StatefulWidget {
  final Map<String,dynamic> data;
  final List<Widget> actions;
  final bool showCosts;
  const PendingSaleInvoiceDialog({super.key,required this.data,required this.actions,this.showCosts=false});
  @override State<PendingSaleInvoiceDialog> createState()=>_PendingSaleInvoiceDialogState();
}

class _PendingSaleInvoiceDialogState extends State<PendingSaleInvoiceDialog> {
  final Map<String,Future<double?>> _costReads={};
  Future<double?> _readPurchasePrice(String productId) async {
    final product=(await db.collection('products').doc(productId).get(const GetOptions(source:Source.server))).data();
    return (product?['purchasePrice'] as num?)?.toDouble();
  }
  @override Widget build(BuildContext context) {
    final data=widget.data,actions=widget.actions;
    final items=(data['items'] as List? ?? const []).whereType<Map>().toList();
    final total=items.fold<double>(0,(sum,x)=>sum+((x['unitPrice'] as num?)?.toDouble() ?? 0)*((x['quantity'] as num?)?.toInt() ?? 0));
    final paid=(data['paid'] as num?)?.toDouble() ?? 0;
    final quantity=items.fold<int>(0,(sum,x)=>sum+((x['quantity'] as num?)?.toInt() ?? 0));
    Widget money(String label,double value)=>Text('$label: ${value.toStringAsFixed(2)} ج.م',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold));
    return Directionality(textDirection:TextDirection.rtl,child:Dialog(
      backgroundColor:const Color(0xFF080808),insetPadding:const EdgeInsets.symmetric(horizontal:6,vertical:12),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:const BorderSide(color:gold)),
      child:SizedBox(width:650,height:double.infinity,child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[
        Padding(padding:const EdgeInsets.only(bottom:8),child:Text(
          data['managerOffline']==true?'فاتورة المدير المعلقة':'فاتورة مبيعات الموظف',
          textAlign:TextAlign.center,
          style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:gold))),
        Expanded(child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Container(color:const Color(0xFF282215),padding:const EdgeInsets.all(8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(pendingSaleStatus(data['status']),style:const TextStyle(color:gold,fontWeight:FontWeight.bold)),
            Text('العميل: ${data['customerName'] ?? ''}'),
            Text(data['managerOffline']==true?'المسؤول: المدير':'الموظف: ${data['employeeName'] ?? ''}'),
            if(data['managerOffline']==true && data['status']=='pending')
              const Text('محفوظة كطلب فقط؛ الحساب والمخزون والصندوق لم يتغيروا بعد',
                style:TextStyle(color:Colors.orangeAccent)),
            Text('التاريخ: ${formatDate(data['createdAt'])}'),
            if(data['status']!='approved')const Text('رقم الفاتورة: يُخصص عند الاعتماد'),
            Text(data['credit']==true?'طريقة الدفع: آجل':'طريقة الدفع: نقدي'),
          ])),
          const SizedBox(height:8),const InvoiceCompactTableHeader(),
          for(var i=0;i<items.length;i++) ...[
            InvoiceCompactReadOnlyLine(number:i+1,name:'${items[i]['productName'] ?? ''}',
              price:(items[i]['unitPrice'] as num?)?.toDouble() ?? 0,quantity:(items[i]['quantity'] as num?)?.toInt() ?? 0),
            if(widget.showCosts) Builder(builder:(context){
              final productId='${items[i]['productId'] ?? ''}';
              if(productId.isEmpty)return const SizedBox.shrink();
              final future=_costReads.putIfAbsent(productId,()=>_readPurchasePrice(productId));
              return FutureBuilder<double?>(future:future,builder:(context,cost)=>Padding(
                padding:const EdgeInsetsDirectional.only(start:28,bottom:5),
                child:Text(cost.hasError?'تعذر تحميل سعر التكلفة':cost.connectionState!=ConnectionState.done?'جارٍ تحميل سعر التكلفة…':
                  cost.data==null?'سعر التكلفة: غير مسجل':'سعر التكلفة: ${cost.data!.toStringAsFixed(2)} ج.م للوحدة • تكلفة الكمية: ${(cost.data!*((items[i]['quantity'] as num?)?.toDouble() ?? 0)).toStringAsFixed(2)} ج.م',
                  style:const TextStyle(color:gold,fontSize:12,fontWeight:FontWeight.bold)),
              ));
            }),
          ],
          if(data['managerPriceAdjusted']==true) ...[
            Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),child:Text(
              'عدّل المدير الأسعار قبل الاعتماد • ${data['managerAdjustedBy'] ?? ''}',
              style:const TextStyle(color:Colors.lightBlueAccent,fontWeight:FontWeight.bold))),
            for(var i=0;i<items.length;i++)
              if((data['managerOriginalItems'] as List? ?? const []).length>i)
                Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:2),child:Text(
                  'السعر الأصلي للصنف ${i+1}: ${((data['managerOriginalItems'] as List)[i] as Map)['unitPrice'] ?? '—'} ج.م',
                  style:const TextStyle(color:Colors.white70,fontSize:12))),
          ],
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

Future<void> editPendingSalePrices(BuildContext context,DocumentReference<Map<String,dynamic>> ref) async {
  try {
    final current=(await ref.get(const GetOptions(source:Source.server))).data();
    if(current==null || current['status']!='pending')throw StateError('الفاتورة لم تعد في انتظار الاعتماد');
    final items=(current['items'] as List).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
    final controllers=items.map((item)=>TextEditingController(text:'${item['unitPrice']}')).toList();
    final result=await showDialog<List<double>>(context:context,builder:(dialog)=>AlertDialog(
      title:const Text('تعديل أسعار الفاتورة قبل الاعتماد'),
      content:SizedBox(width:520,height:460,child:ListView.builder(itemCount:items.length,itemBuilder:(c,i)=>Padding(
        padding:const EdgeInsets.symmetric(vertical:5),child:TextField(controller:controllers[i],keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:InputDecoration(labelText:'${i+1}. ${items[i]['productName'] ?? 'الصنف'} • السعر الحالي ${items[i]['unitPrice']} ج.م'))))),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('إلغاء')),
        FilledButton(onPressed:(){
          final parsed=<double>[];
          for(var i=0;i<controllers.length;i++){
            final value=double.tryParse(controllers[i].text.trim());
            if(value==null || !value.isFinite || value<0){
              ScaffoldMessenger.of(dialog).showSnackBar(const SnackBar(content:Text('اكتب سعرًا صحيحًا لكل صنف')));
              return;
            }
            parsed.add(value);
          }
          Navigator.pop(dialog,parsed);
        },child:const Text('مراجعة الإجمالي'))],
    ));
    for(final controller in controllers){controller.dispose();}
    if(result==null || !context.mounted)return;
    final edited=repricePendingSale(current,result);
    final answer=await showDialog<String>(context:context,builder:(confirm)=>AlertDialog(
      title:const Text('تأكيد تعديل الفاتورة'),
      content:Text('الإجمالي بعد التعديل: ${(edited['total'] as double).toStringAsFixed(2)} ج.م\nالمدفوع: ${(edited['paid'] as double).toStringAsFixed(2)} ج.م\nالمتبقي: ${((edited['total'] as double)-(edited['paid'] as double)).toStringAsFixed(2)} ج.م\n\nسيظهر التعديل للموظف، وستظل الفاتورة معلقة حتى تعتمدها.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(confirm),child:const Text('رجوع')),
        FilledButton(onPressed:()=>Navigator.pop(confirm,'save'),child:const Text('حفظ الأسعار'))],
    ));
    if(answer!='save' || !context.mounted)return;
    await db.runTransaction((tx)async{
      final latest=(await tx.get(ref)).data();
      if(latest==null || latest['status']!='pending')throw StateError('الفاتورة لم تعد معلقة');
      final safe=repricePendingSale(latest,result);
      tx.update(ref,{...safe,'managerAdjustedBy':FirebaseAuth.instance.currentUser!.uid,
        'managerAdjustedAt':FieldValue.serverTimestamp()});
    });
    if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم تعديل الأسعار وحفظ الفاتورة للمراجعة')));
  }catch(e){if(context.mounted)await showInvoiceSaveProblem(context,invoiceSaveFailureMessage(e),title:'تعديل أسعار الفاتورة');}
}

Future<void> reviewPendingSale(BuildContext context,DocumentReference<Map<String,dynamic>> ref,bool owner) async {
  bool busy=false;
  await showDialog<void>(context:context,barrierDismissible:false,builder:(outer)=>StatefulBuilder(builder:(c,update)=>
    StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream:ref.snapshots(),builder:(c,snapshot) {
      final data=snapshot.data?.data();
      if(data==null)return AlertDialog(title:const Text('طلب فاتورة موظف'),content:Text(snapshot.hasError?'تعذر تحميل الطلب':'جارٍ التحميل'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق'))]);
      if(!pendingSaleIsVisible(data))return AlertDialog(title:const Text('تم مسح الطلب'),content:const Text('ابدأ فاتورة جديدة من شاشة المبيعات.'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق'))]);
      final pending=data['status']=='pending';
      return PendingSaleInvoiceDialog(data:data,showCosts:owner&&pending,actions:[
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
        if(owner && pending)OutlinedButton.icon(
          onPressed:busy?null:()async {await editPendingSalePrices(c,ref);},
          icon:const Icon(Icons.edit,color:gold),label:const Text('تعديل الأسعار')),
        if(owner && pending)FilledButton(onPressed:busy?null:()async {
          update(()=>busy=true);
          try {
            if(data['managerOffline']==true && snapshot.data?.metadata.isFromCache==true) {
              throw StateError('الفاتورة معلقة على الجهاز. اتصل بالإنترنت وانتظر تأكيد Firebase قبل الاعتماد.');
            }
            final latest=(await ref.get(const GetOptions(source:Source.server)))
              .timeout(const Duration(seconds:8)).data();
            if(latest==null)throw Exception('الطلب غير موجود');
            final parsed=PendingSaleData.parse(latest);
            final entries=parsed.lines.map((x)=>(id:x.id,name:'',qty:x.quantity,price:x.price,cost:null as double?,discount:x.discount,basePrice:x.basePrice)).toList();
            final saved=await commitGroupedSale(owner:true,branchId:'${latest['branchId']}',entries:entries,total:parsed.total,payment:parsed.paid,
              paymentBreakdown:parsed.paymentBreakdown,credit:parsed.credit,customerId:parsed.customerId,saleRef:db.collection('sales').doc(ref.id),pendingRef:ref);
            if(c.mounted)Navigator.pop(c);
            if(context.mounted)await showInvoiceSavedActions(context,'sales',ref.id,saved);
          }catch(e){
            if(data['managerOffline']==true && isFirestoreQuotaExhausted(e)) {
              try {await ManagerOfflineDraftStore.instance.preserve(ref.id,data);}
              catch(backupError) {debugPrint('VIB manager backup after quota error: $backupError');}
            }
            if(c.mounted){
              update(()=>busy=false);
              await showInvoiceSaveProblem(c,invoiceSaveFailureMessage(e),
                title:data['managerOffline']==true?'الفاتورة ما زالت معلقة':'تعذر الاعتماد',
                button:'الرجوع للفاتورة المعلقة');
            }
          }
        },child:Text(busy?'جارٍ الاعتماد…':data['managerOffline']==true?'اعتماد الفاتورة المعلقة':'اعتماد وحفظ')),
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
