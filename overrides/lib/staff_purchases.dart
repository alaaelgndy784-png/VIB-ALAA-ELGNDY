part of 'main.dart';

Future<Map<String,dynamic>> saveEmployeePurchase(String id,String supplierId,
    List<({String id,int qty,double cost})> entries,double payment,String invoiceNumber,String note) async {
  if(entries.isEmpty || entries.length>4 || !payment.isFinite)throw StateError('راجع البنود والمدفوع؛ الحد 4 أصناف للموظف');
  final actor=FirebaseAuth.instance.currentUser!.uid;
  final ref=db.collection('purchases').doc(id);
  final key=jsonEncode({'supplier':supplierId,'items':entries.map((e)=>[e.id,e.qty,e.cost]).toList(),'paid':payment,'number':invoiceNumber,'note':note});
  return db.runTransaction<Map<String,dynamic>>((tx) async {
    final user=(await tx.get(db.collection('users').doc(actor))).data();
    if(user?['role']!='employee' || user?['active']!=true || user?['canPurchase']!=true)throw StateError('المدير لم يسمح لك بعمل فواتير مشتريات أو ألغى الإذن');
    final old=(await tx.get(ref)).data();
    if(old!=null){if(old['requestKey']!=key || old['actorId']!=actor)throw StateError('طلب سابق مختلف؛ افتح فاتورة جديدة');return old;}
    final supplierRef=db.collection('suppliers').doc(supplierId);
    final supplier=(await tx.get(supplierRef)).data();
    if(supplier==null || supplier['active']==false)throw StateError('اختر موردًا مسجلًا ونشطًا');
    final cashRef=db.collection('settings').doc('cash');final cash=(await tx.get(cashRef)).data();
    final products=<String,Map<String,dynamic>>{},stocks=<String,int>{};
    for(final entry in entries){
      final product=(await tx.get(db.collection('products').doc(entry.id))).data();
      final stock=(await tx.get(db.collection('stock').doc('main_${entry.id}'))).data();
      if(product==null || product['active']!=true || entry.qty<=0 || entry.qty>1000000 || !entry.cost.isFinite || entry.cost<0 || entry.cost>1000000000 || products.containsKey(entry.id))throw StateError('راجع الصنف والكمية والتكلفة');
      products[entry.id]=product;stocks[entry.id]=(stock?['quantity'] as num?)?.toInt() ?? 0;
    }
    final items=[for(final e in entries)<String,dynamic>{'productId':e.id,'productName':products[e.id]!['name'],'quantity':e.qty,'unitCost':e.cost,'lineTotal':e.qty*e.cost}];
    final total=items.fold<double>(0,(sum,x)=>sum+(x['lineTotal'] as num).toDouble());
    final paid=ledgerCents(payment)/100,due=total-paid;
    final before=(supplier['balance'] as num?)?.toDouble() ?? 0,cashBefore=(cash?['balance'] as num?)?.toDouble() ?? 0;
    if(total>1000000000000 || paid<0 || due<0 || cashBefore<paid)throw StateError('راجع المدفوع أو رصيد الصندوق');
    final now=FieldValue.serverTimestamp();
    final invoice=<String,dynamic>{'id':id,'actorId':actor,'actorName':user?['name'] ?? '', 'branchId':user?['branchId'] ?? '',
      'supplierId':supplierId,'supplierName':supplier['name'],'invoiceNumber':invoiceNumber,'note':note,
      'items':items,'itemCount':items.length,'stockIndex':{for(var i=0;i<items.length;i++)'${items[i]['productId']}':i},
      'total':total,'paid':paid,'due':due,'cashPosted':true,'cashBefore':cashBefore,'cashAfter':cashBefore-paid,
      'supplierPreviousBalance':before,'supplierBalanceAfter':before+due,'paymentStatus':due>0?'credit':'cash',
      'status':'completed','source':'employee','requestKey':key,'createdAt':now};
    tx.set(ref,invoice);
    tx.update(supplierRef,{'balance':before+due,'lastPurchaseId':id,'updatedAt':now});
    tx.set(db.collection('accountMovements').doc('${id}_supplier'),{'accountType':'suppliers','accountId':supplierId,'accountName':supplier['name'],
      'kind':'purchase','amount':due,'paid':paid,'balanceBefore':before,'balanceAfter':before+due,'referenceId':id,'actorId':actor,'createdAt':now});
    if(paid>0){
      tx.set(cashRef,{'balance':cashBefore-paid,'lastPurchaseId':id,'updatedAt':now},SetOptions(merge:true));
      tx.set(db.collection('accountMovements').doc('${id}_cash'),{'accountType':'cash','accountId':supplierId,'accountName':supplier['name'],
        'kind':'purchasePayment','amount':paid,'delta':-paid,'balanceBefore':cashBefore,'balanceAfter':cashBefore-paid,'referenceId':id,'actorId':actor,'createdAt':now});
    }
    for(final e in entries){
      tx.set(db.collection('stock').doc('main_${e.id}'),{'branchId':'main','productId':e.id,'quantity':stocks[e.id]!+e.qty,'lastPurchaseId':id},SetOptions(merge:true));
      tx.update(db.collection('products').doc(e.id),{'purchasePrice':e.cost,'lastPurchaseId':id,'updatedAt':now});
      tx.set(db.collection('stockMovements').doc('${id}_${e.id}'),{'productId':e.id,'productName':products[e.id]!['name'],
        'branchId':'main','kind':'purchase','quantity':e.qty,'balanceAfter':stocks[e.id]!+e.qty,'referenceId':id,'actorId':actor,'createdAt':now});
    }
    return {...invoice,'createdAt':Timestamp.now()};
  });
}
