part of 'main.dart';

Future<bool> _confirmVoucherCancellation(BuildContext context,String title,String message) async =>
    await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(title),content:Text(message),actions:[
      TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('رجوع')),
      FilledButton(onPressed:()=>Navigator.pop(c,true),style:FilledButton.styleFrom(backgroundColor:Colors.red),child:const Text('إلغاء السند')),
    ]))==true;

Future<void> _queueOfflineVoucherCancellation(String type,String id) async {
  final uid=FirebaseAuth.instance.currentUser!.uid;
  final request=db.collection('managerOfflineVoucherCancellations').doc('${type}_$id');
  final future=request.set({'type':type,'originalId':id,'actorId':uid,'status':'pending','createdAt':FieldValue.serverTimestamp()});
  unawaited(future.then<void>((_) {},onError:(Object error,StackTrace _) {
    debugPrint('VIB offline voucher cancellation sync failed for $type/$id: $error');
  }));
}

Future<bool> applyReceiptVoucherCancellation(String id) async {
  final actor=FirebaseAuth.instance.currentUser!.uid;
  final receiptRef=db.collection('receipts').doc(id),cancelRef=db.collection('voucherCancellations').doc('receipt_$id');
  final customerMovement=db.collection('accountMovements').doc(),cashMovement=db.collection('accountMovements').doc();
  return db.runTransaction<bool>((tx)async{
    final prior=await tx.get(cancelRef),receipt=await tx.get(receiptRef);
    if(prior.exists)return false;
    if(!receipt.exists)throw StateError('سند القبض غير موجود');
    final data=receipt.data()!;
    final customerId='${data['customerId']??''}';
    final amount=(data['amount'] as num?)?.toDouble();
    if(customerId.isEmpty||amount==null||!amount.isFinite||amount<=0)throw StateError('بيانات سند القبض غير صحيحة');
    final customerRef=db.collection('customers').doc(customerId),cashRef=db.collection('settings').doc('cash');
    final customer=await tx.get(customerRef),cash=await tx.get(cashRef);
    if(!customer.exists)throw StateError('حساب العميل غير موجود');
    final customerBefore=((customer.data()?['balance'] as num?)??0).toDouble();
    final cashBefore=((cash.data()?['balance'] as num?)??0).toDouble();
    final customerAfter=(customerBefore*100+(amount*100).round())/100;
    final cashAfter=(cashBefore*100-(amount*100).round())/100;
    final now=FieldValue.serverTimestamp();
    tx.update(customerRef,{'balance':customerAfter,'updatedAt':now});
    tx.set(cashRef,{'balance':cashAfter,'updatedAt':now},SetOptions(merge:true));
    tx.set(customerMovement,{'accountType':'customers','accountId':customerId,'accountName':data['customerName']??customer.data()?['name']??'',
      'kind':'collectionCancellation','amount':amount,'balanceBefore':customerBefore,'balanceAfter':customerAfter,
      'referenceId':id,'reason':'إلغاء سند قبض ${data['receiptNumber']??id}','actorId':actor,'createdAt':now});
    tx.set(cashMovement,{'accountType':'cash','accountId':customerId,'accountName':data['customerName']??'',
      'kind':'customerCollectionCancellation','amount':amount,'delta':-amount,'balanceBefore':cashBefore,'balanceAfter':cashAfter,
      'referenceId':id,'reason':'عكس سند قبض ${data['receiptNumber']??id}','actorId':actor,'createdAt':now});
    tx.set(cancelRef,{'type':'receipt','originalId':id,'amount':amount,'customerId':customerId,
      'actorId':actor,'createdAt':now,'customerMovementId':customerMovement.id,'cashMovementId':cashMovement.id});
    return true;
  });
}

Future<bool> applySupplierPaymentCancellation(String id) async {
  final actor=FirebaseAuth.instance.currentUser!.uid;
  final voucherRef=db.collection('accountMovements').doc(id),cancelRef=db.collection('voucherCancellations').doc('payment_$id');
  final supplierMovement=db.collection('accountMovements').doc(),cashMovement=db.collection('accountMovements').doc();
  return db.runTransaction<bool>((tx)async{
    final prior=await tx.get(cancelRef),voucher=await tx.get(voucherRef);
    if(prior.exists)return false;
    if(!voucher.exists||voucher.data()?['kind']!='payment')throw StateError('سند الصرف غير موجود');
    final data=voucher.data()!;
    final supplierId='${data['accountId']??''}';
    final amount=(data['amount'] as num?)?.toDouble();
    if(supplierId.isEmpty||amount==null||!amount.isFinite||amount<=0)throw StateError('بيانات سند الصرف غير صحيحة');
    final supplierRef=db.collection('suppliers').doc(supplierId),cashRef=db.collection('settings').doc('cash');
    final supplier=await tx.get(supplierRef),cash=await tx.get(cashRef);
    if(!supplier.exists)throw StateError('حساب المورد غير موجود');
    final supplierBefore=((supplier.data()?['balance'] as num?)??0).toDouble();
    final cashBefore=((cash.data()?['balance'] as num?)??0).toDouble();
    final supplierAfter=(supplierBefore*100+(amount*100).round())/100;
    final cashAfter=(cashBefore*100+(amount*100).round())/100;
    final now=FieldValue.serverTimestamp();
    tx.update(supplierRef,{'balance':supplierAfter,'updatedAt':now});
    tx.set(cashRef,{'balance':cashAfter,'updatedAt':now},SetOptions(merge:true));
    tx.set(supplierMovement,{'accountType':'suppliers','accountId':supplierId,'accountName':data['accountName']??supplier.data()?['name']??'',
      'kind':'paymentCancellation','amount':amount,'balanceBefore':supplierBefore,'balanceAfter':supplierAfter,
      'referenceId':id,'reason':'إلغاء سند صرف $id','actorId':actor,'createdAt':now});
    tx.set(cashMovement,{'accountType':'cash','accountId':supplierId,'accountName':data['accountName']??'',
      'kind':'supplierPaymentCancellation','amount':amount,'delta':amount,'balanceBefore':cashBefore,'balanceAfter':cashAfter,
      'referenceId':id,'reason':'عكس سند صرف $id','actorId':actor,'createdAt':now});
    tx.set(cancelRef,{'type':'supplierPayment','originalId':id,'amount':amount,'supplierId':supplierId,
      'actorId':actor,'createdAt':now,'supplierMovementId':supplierMovement.id,'cashMovementId':cashMovement.id});
    return true;
  });
}

Future<void> cancelReceiptVoucher(BuildContext context,String id,Map<String,dynamic> displayed) async {
  if(!await _confirmVoucherCancellation(context,'إلغاء سند القبض',
    'سيُعكس مبلغ ${displayed['amount']} ج.م على رصيد العميل والصندوق، مع الاحتفاظ بالسند الأصلي وسجل الإلغاء.')) return;
  try {
    final changed=await applyReceiptVoucherCancellation(id);
    if(context.mounted)await showInvoiceSaveProblem(context,changed?'تم إلغاء سند القبض وعكس أثره على حساب العميل والصندوق. السند الأصلي محفوظ.':'السند ملغي بالفعل.',title:'تم الإلغاء',button:'تمام',success:true);
  } catch(e) {
    if(isTemporaryFirestoreOffline(e)) {
      await _queueOfflineVoucherCancellation('receipt',id);
      if(context.mounted)await showInvoiceSaveProblem(context,'حُفظ طلب الإلغاء محليًا. سيُعكس أثر السند على العميل والصندوق بعد رجوع الإنترنت ومراجعة العملية.',title:'الإلغاء ينتظر المزامنة',button:'تمام',success:true);
      return;
    }
    if(context.mounted)await showInvoiceSaveProblem(context,'تعذر إلغاء سند القبض: $e',title:'إلغاء سند القبض',button:'رجوع');
  }
}

Future<void> cancelSupplierPaymentVoucher(BuildContext context,String id,Map<String,dynamic> displayed) async {
  if(!await _confirmVoucherCancellation(context,'إلغاء سند الصرف',
    'سيُعاد المبلغ ${displayed['amount']} ج.م إلى رصيد الصندوق وتُعاد مديونية المورد، مع الاحتفاظ بالسند الأصلي وسجل الإلغاء.')) return;
  try {
    final changed=await applySupplierPaymentCancellation(id);
    if(context.mounted)await showInvoiceSaveProblem(context,changed?'تم إلغاء سند الصرف وإعادة أثره إلى حساب المورد والصندوق. السند الأصلي محفوظ.':'السند ملغي بالفعل.',title:'تم الإلغاء',button:'تمام',success:true);
  } catch(e) {
    if(isTemporaryFirestoreOffline(e)) {
      await _queueOfflineVoucherCancellation('payment',id);
      if(context.mounted)await showInvoiceSaveProblem(context,'حُفظ طلب الإلغاء محليًا. سيُعكس أثر السند على المورد والصندوق بعد رجوع الإنترنت ومراجعة العملية.',title:'الإلغاء ينتظر المزامنة',button:'تمام',success:true);
      return;
    }
    if(context.mounted)await showInvoiceSaveProblem(context,'تعذر إلغاء سند الصرف: $e',title:'إلغاء سند الصرف',button:'رجوع');
  }
}

class ManagerOfflineVoucherSync {
  ManagerOfflineVoucherSync._();
  static final instance=ManagerOfflineVoucherSync._();
  StreamSubscription<QuerySnapshot<Map<String,dynamic>>>? _subscription;
  final Set<String> _inFlight={},_failedThisSession={};
  void start() {
    if(_subscription!=null)return;
    _subscription=db.collection('managerOfflineVoucherCancellations').snapshots(includeMetadataChanges:true).listen((snapshot){
      if(snapshot.metadata.isFromCache||snapshot.metadata.hasPendingWrites)return;
      for(final doc in snapshot.docs) {
        if(doc.data()['status']!='pending'||doc.metadata.hasPendingWrites||_inFlight.contains(doc.id)||_failedThisSession.contains(doc.id))continue;
        _inFlight.add(doc.id);unawaited(_process(doc));
      }
    },onError:(Object _){});
  }
  Future<void> _process(QueryDocumentSnapshot<Map<String,dynamic>> doc) async {
    try {
      final data=doc.data();
      final type='${data['type']}',id='${data['originalId']}';
      if(type=='receipt')await applyReceiptVoucherCancellation(id);
      else if(type=='payment')await applySupplierPaymentCancellation(id);
      else throw StateError('نوع طلب الإلغاء غير معروف');
      await doc.reference.update({'status':'completed','completedAt':FieldValue.serverTimestamp()});
    } catch(error) {
      if(!isTemporaryFirestoreOffline(error))_failedThisSession.add(doc.id);
    } finally {_inFlight.remove(doc.id);}
  }
  void stop(){_subscription?.cancel();_subscription=null;_inFlight.clear();_failedThisSession.clear();}
}
