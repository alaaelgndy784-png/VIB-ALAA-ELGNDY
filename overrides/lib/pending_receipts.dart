part of 'main.dart';

Query<Map<String,dynamic>> pendingReceiptQuery(bool owner)=>owner
  ?db.collection('pendingReceipts')
  :db.collection('pendingReceipts').where('employeeId',isEqualTo:FirebaseAuth.instance.currentUser!.uid);

class PendingReceiptShortcut extends StatelessWidget {
  final bool owner;
  const PendingReceiptShortcut({super.key,required this.owner});
  @override Widget build(BuildContext context)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:pendingReceiptQuery(owner).snapshots(),builder:(context,snapshot){
      final count=snapshot.data?.docs.where((d)=>d.data()['status']=='pending').length;
      return SizedBox(width:double.infinity,child:OutlinedButton.icon(
        icon:Icon(Icons.pending_actions,color:owner?vibBlue:vibNeon),
        label:Text('${owner?'اعتماد سندات قبض الموظفين':'سنداتي — متابعة الاعتماد'}${count==null?'':' (${count} معلّق)'}',
          maxLines:1,overflow:TextOverflow.ellipsis),
        onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>Directionality(
          textDirection:TextDirection.rtl,child:Scaffold(
            appBar:AppBar(title:Text(owner?'اعتماد سندات قبض الموظفين':'سندات القبض المرسلة')),
            body:PendingReceiptPage(owner:owner))))));
    });

class PendingReceiptPage extends StatelessWidget {
  final bool owner;
  const PendingReceiptPage({super.key,required this.owner});
  @override Widget build(BuildContext context)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:pendingReceiptQuery(owner).snapshots(includeMetadataChanges:true),
    builder:(context,snapshot){
      if(snapshot.hasError)return const Center(child:Text('تعذر تحميل طلبات سندات القبض؛ راجع الاتصال والصلاحيات'));
      if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
      final rows=snapshot.data!.docs.toList()..sort((a,b){
        final pa=a.data()['status']=='pending',pb=b.data()['status']=='pending';
        if(pa!=pb)return pa?-1:1;
        return ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch??0)
          .compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch??0);
      });
      return Column(children:[
        Padding(padding:const EdgeInsets.all(12),child:Text(owner
          ?'راجع السند ثم اعتمده. رصيد العميل والصندوق لا يتغيران قبل الاعتماد.'
          :'السند لا يغيّر رصيد العميل أو الصندوق إلا بعد اعتماد المدير.',textAlign:TextAlign.center)),
        if(snapshot.data!.metadata.isFromCache)const Text('بيانات محفوظة على الجهاز؛ تأكد من الحالة عند الاتصال'),
        Expanded(child:rows.isEmpty?const Center(child:Text('لا توجد طلبات سند قبض'))
          :ListView(children:[for(final row in rows)Card(child:Padding(
            padding:const EdgeInsets.all(8),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:8),
                leading:Icon(row.data()['status']=='approved'?Icons.check_circle:
                  row.data()['status']=='rejected'?Icons.cancel:Icons.hourglass_top,color:gold),
                title:Text('${row.data()['customerName']??'عميل'} • ${row.data()['amount']??0} ج.م',
                  style:const TextStyle(color:gold,fontWeight:FontWeight.bold)),
                subtitle:Text('${owner?'${row.data()['actorName']??''} • ':''}${pendingReceiptStatus(row.data())}\\n'
                  '${formatDate(row.data()['receiptDate']??row.data()['createdAt'])}\\n${row.data()['note']??''}')),
              if(owner&&row.data()['status']=='pending')Wrap(alignment:WrapAlignment.end,children:[
                TextButton.icon(icon:const Icon(Icons.close,color:Colors.redAccent),label:const Text('رفض'),
                  onPressed:()=>rejectPendingReceiptVoucher(context,row.reference)),
                FilledButton.icon(icon:const Icon(Icons.check),label:const Text('اعتماد السند'),
                  onPressed:()=>approvePendingReceiptVoucher(context,row.reference)),
              ]),
            ])))])),
      ]);
    });

String pendingReceiptStatus(Map<String,dynamic> data)=>data['status']=='approved'?'تم الاعتماد':
  data['status']=='rejected'?'مرفوض — ${data['rejectionReason']??''}':'في انتظار اعتماد المدير';

Future<void> createPendingReceiptVoucher(BuildContext context,String branchId,{String? initialCustomerId}) async {
  final amount=TextEditingController(),note=TextEditingController();
  DateTime receiptDate=tz.TZDateTime.now(tz.getLocation('Africa/Cairo'));
  String? customerId=initialCustomerId,error;
  String method='نقدي'; bool saving=false;
  final request=db.collection('pendingReceipts').doc();
  await showDialog<void>(context:context,barrierDismissible:false,builder:(dialog)=>StatefulBuilder(
    builder:(dialog,update)=>AlertDialog(
      title:const Text('إرسال سند قبض لاعتماد المدير'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        OutlinedButton.icon(icon:const Icon(Icons.person_search),label:const Text('اختيار عميل مسجل / تغيير العميل'),
          onPressed:saving?null:() async {
            final selected=await selectRegisteredCustomer(dialog);
            if(selected!=null&&dialog.mounted)update(()=>customerId=selected);
          }),
        if(customerId!=null)StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
          stream:db.collection('customers').doc(customerId).snapshots(),
          builder:(context,snap)=>Text(snap.hasError?'تعذر تحميل رصيد العميل':!snap.hasData?'جارٍ تحميل الرصيد':
            '${snap.data?.data()?['name']??''} — الرصيد الحالي: ${snap.data?.data()?['balance']??0} ج.م')),
        TextField(controller:amount,enabled:!saving,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:const InputDecoration(labelText:'المبلغ المقبوض')),
        OutlinedButton.icon(icon:const Icon(Icons.calendar_month),
          label:Text('تاريخ ووقت السداد: ${DateFormat('dd/MM/yyyy HH:mm').format(receiptDate)}'),
          onPressed:saving?null:() async {
            final day=await showDatePicker(context:dialog,initialDate:receiptDate,firstDate:DateTime(2000),lastDate:DateTime(2100));
            if(day==null||!dialog.mounted)return;
            final time=await showTimePicker(context:dialog,initialTime:TimeOfDay.fromDateTime(receiptDate));
            if(time!=null&&dialog.mounted)update(()=>receiptDate=tz.TZDateTime(tz.getLocation('Africa/Cairo'),
              day.year,day.month,day.day,time.hour,time.minute));
          }),
        DropdownButtonFormField<String>(value:method,decoration:const InputDecoration(labelText:'طريقة الدفع / البيان'),
          items:const ['نقدي','تحويل إنستا باي','تحويل فودافون كاش','تحويل محفظة X','تحويل عن طريق الحساب البنكي']
            .map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
          onChanged:saving?null:(v)=>update(()=>method=v??'نقدي')),
        TextField(controller:note,enabled:!saving,decoration:const InputDecoration(labelText:'البيان / ملاحظات')),
        const SizedBox(height:8),const Text('لن يتغير رصيد العميل أو الصندوق حتى يعتمد المدير السند.'),
        if(error!=null)Text(error!,style:const TextStyle(color:Colors.redAccent)),
      ])),
      actions:[
        TextButton(onPressed:saving?null:()=>Navigator.pop(dialog),child:const Text('إلغاء')),
        FilledButton(onPressed:saving?null:() async {
          final paid=parseReceiptAmount(amount.text),id=customerId;
          if(id==null||paid==null||paid<=0){update(()=>error='اختر العميل واكتب مبلغًا صحيحًا أكبر من صفر.');return;}
          update(()=>{saving=true;error=null;});
          try {
            final uid=FirebaseAuth.instance.currentUser!.uid,date=Timestamp.fromDate(receiptDate);
            await db.runTransaction((tx) async {
              final profile=(await tx.get(db.collection('users').doc(uid))).data();
              final customer=(await tx.get(db.collection('customers').doc(id))).data();
              if(profile?['active']!=true||profile?['role']!='employee'||'${profile?['branchId']??''}'!=branchId)
                throw StateError('حساب الموظف غير مفعل أو الفرع غير صحيح');
              if(customer==null||customer['active']==false)throw StateError('العميل غير موجود أو غير نشط');
              final balance=(customer['balance'] as num?)?.toDouble()??0;
              if(paid>balance)throw StateError('المبلغ أكبر من مديونية العميل الحالية');
              tx.set(request,{
                'id':request.id,'employeeId':uid,'actorName':'${profile?['name']??''}','branchId':branchId,
                'customerId':id,'customerName':'${customer['name']??''}','customerPhone':'${customer['phone']??''}',
                'amount':paid,'receiptDate':date,
                'receiptNumber':'VIB-RC-${DateFormat('yyyyMMdd').format(receiptDate)}-${request.id.substring(0,6).toUpperCase()}',
                'paymentMethod':method,'note':note.text.trim(),'status':'pending','createdAt':FieldValue.serverTimestamp(),
                'requestKey':jsonEncode({'customerId':id,'amount':paid,'date':date.millisecondsSinceEpoch,'method':method,'note':note.text.trim()}),
              });
            });
            if(dialog.mounted)Navigator.pop(dialog);
            if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content:Text('تم إرسال سند القبض للمدير للاعتماد؛ لم يتغير رصيد العميل أو الصندوق.')));
          }catch(e){if(dialog.mounted)update(()=>{saving=false;error='تعذر إرسال السند: $e';});}
        },child:Text(saving?'جارٍ الإرسال…':'إرسال للمدير')),
      ],
    )));
  amount.dispose();note.dispose();
}

Future<void> approvePendingReceiptVoucher(BuildContext context,DocumentReference<Map<String,dynamic>> ref) async {
  try {
    await db.runTransaction((tx) async {
      final pending=(await tx.get(ref)).data(),uid=FirebaseAuth.instance.currentUser!.uid;
      final manager=(await tx.get(db.collection('users').doc(uid))).data();
      if(manager?['active']!=true||manager?['role']!='owner')throw StateError('صلاحية المدير مطلوبة');
      if(pending==null)throw StateError('طلب السند غير موجود');
      if(pending['status']=='approved')return;
      if(pending['status']!='pending')throw StateError('السند لم يعد معلّقًا');
      final employeeId='${pending['employeeId']??''}',customerId='${pending['customerId']??''}';
      final employee=(await tx.get(db.collection('users').doc(employeeId))).data();
      final customerRef=db.collection('customers').doc(customerId),customer=(await tx.get(customerRef)).data();
      final cashRef=db.collection('settings').doc('cash'),cash=(await tx.get(cashRef)).data();
      final receiptRef=db.collection('receipts').doc(ref.id),existing=(await tx.get(receiptRef)).data();
      if(existing!=null)throw StateError('السند موجود بالفعل؛ راجع السجل قبل إعادة الاعتماد');
      if(employee?['active']!=true||employee?['role']!='employee'||employee?['branchId']!=pending['branchId'])
        throw StateError('حساب الموظف غير مفعل أو الفرع تغيّر');
      if(customer==null||customer['active']==false)throw StateError('العميل غير موجود أو غير نشط');
      final amount=(pending['amount'] as num?)?.toDouble()??0,balance=(customer['balance'] as num?)?.toDouble()??0;
      if(!amount.isFinite||amount<=0||amount>balance)throw StateError('المبلغ أكبر من مديونية العميل الحالية');
      final cashBefore=(cash?['balance'] as num?)?.toDouble()??0,cashAfter=cashBefore+amount;
      final name='${employee?['name']??pending['actorName']??''}',customerName='${customer['name']??''}';
      final phone='${customer['phone']??''}',cm=db.collection('accountMovements').doc('${ref.id}_customer');
      final km=db.collection('accountMovements').doc('${ref.id}_cash'),now=FieldValue.serverTimestamp();
      tx.update(customerRef,{'balance':balance-amount,'lastReceiptId':ref.id,'updatedAt':now});
      tx.set(cashRef,{'balance':cashAfter,'lastReceiptId':ref.id,'updatedAt':now},SetOptions(merge:true));
      tx.set(receiptRef,{'customerId':customerId,'customerName':customerName,'customerPhone':phone,
        'receiptDate':pending['receiptDate'],'createdAt':now,'amount':amount,'balanceBefore':balance,'balanceAfter':balance-amount,
        'cashBefore':cashBefore,'cashAfter':cashAfter,'actorId':employeeId,'actorName':name,
        'branchId':pending['branchId'],'note':pending['note']??'','paymentMethod':pending['paymentMethod']??'نقدي',
        'receiptNumber':pending['receiptNumber']??ref.id,'customerMovementId':cm.id,'cashMovementId':km.id});
      tx.set(cm,{'accountType':'customers','accountId':customerId,'accountName':customerName,'kind':'collection',
        'amount':amount,'balanceBefore':balance,'balanceAfter':balance-amount,'referenceId':ref.id,
        'actorId':employeeId,'branchId':pending['branchId'],'createdAt':now,'receiptDate':pending['receiptDate']});
      tx.set(km,{'accountType':'cash','accountId':customerId,'accountName':customerName,'kind':'customerCollection',
        'amount':amount,'delta':amount,'balanceBefore':cashBefore,'balanceAfter':cashAfter,'referenceId':ref.id,
        'reason':'سند قبض من عميل','actorId':employeeId,'branchId':pending['branchId'],
        'createdAt':now,'receiptDate':pending['receiptDate']});
      tx.update(ref,{'status':'approved','reviewedBy':uid,'reviewedAt':now,'approvedByName':'${manager?['name']??''}'});
    });
    if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم اعتماد سند القبض وتحديث رصيد العميل والصندوق.')));
  }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر اعتماد سند القبض: $e')));}
}

Future<void> rejectPendingReceiptVoucher(BuildContext context,DocumentReference<Map<String,dynamic>> ref) async {
  final reason=TextEditingController();
  final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('رفض سند القبض'),
    content:TextField(controller:reason,maxLines:3,decoration:const InputDecoration(labelText:'سبب الرفض')),
    actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('رجوع')),
      FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('تأكيد الرفض'))]));
  if(ok!=true||!context.mounted){reason.dispose();return;}
  try {
    final text=reason.text.trim();if(text.isEmpty)throw StateError('اكتب سبب الرفض');
    final uid=FirebaseAuth.instance.currentUser!.uid;
    await db.runTransaction((tx)async{
      final current=(await tx.get(ref)).data(),manager=(await tx.get(db.collection('users').doc(uid))).data();
      if(manager?['active']!=true||manager?['role']!='owner')throw StateError('صلاحية المدير مطلوبة');
      if(current==null||current['status']!='pending')throw StateError('الطلب لم يعد معلّقًا');
      tx.update(ref,{'status':'rejected','rejectionReason':text,'reviewedBy':uid,'reviewedAt':FieldValue.serverTimestamp()});
    });
    if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم رفض السند.')));
  }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر رفض السند: $e')));}
  finally{reason.dispose();}
}
