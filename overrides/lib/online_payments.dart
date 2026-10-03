part of 'main.dart';

Future<Map<String,dynamic>> geideaCall(String name, [Map<String,dynamic> data = const {}]) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('سجل دخولك أولًا');
  final token = await user.getIdToken();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.postUrl(Uri.https('us-central1-$_vibProjectId.cloudfunctions.net', '/$name')).timeout(const Duration(seconds: 25));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'data':data}));
    final response = await request.close().timeout(const Duration(seconds: 125));
    final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 25));
    if (response.statusCode == 404) throw StateError('ربط جيديا لم يُنشر بعد؛ يلزم تفعيل حساب التاجر وإعداد الخدمة');
    final result = jsonDecode(body) as Map;
    if (result['error'] is Map) throw StateError('${(result['error'] as Map)['message'] ?? 'تعذر الاتصال بجيديا'}');
    if (response.statusCode != 200 || result['result'] is! Map) throw StateError('لم يصل تأكيد العملية؛ حدّث السجل قبل إعادة المحاولة');
    return Map<String,dynamic>.from(result['result'] as Map);
  } on SocketException {
    throw StateError('تعذر الاتصال؛ حدّث سجل الدفع قبل إعادة المحاولة');
  } on FormatException {
    throw StateError('خدمة جيديا لم تُجهز بعد أو لم ترسل ردًا صحيحًا');
  } finally { client.close(force:true); }
}

Future<void> openGeideaPayments(BuildContext context, {String? invoiceId}) => Navigator.push<void>(context,
  MaterialPageRoute(builder:(_) => Directionality(textDirection:TextDirection.rtl, child:Theme(data:managerTheme(context),
    child:Scaffold(appBar:AppBar(title:const Text('جيديا — روابط الدفع')),body:GeideaPayments(invoiceId:invoiceId))))));

String geideaState(dynamic value) => const <String,String>{
  'pending':'بانتظار الدفع','creating':'جاري إنشاء الرابط','creation_unknown':'إنشاء غير مؤكد — راجع جيديا',
  'creation_failed':'لم يتم إنشاء الرابط','expired':'انتهت صلاحية الرابط','paid':'تم السداد',
  'partially_refunded':'رد جزئي للكارت','refunded':'تم رد المبلغ للكارت','review':'يحتاج مراجعة الفاتورة',
  'test_paid':'سداد تجريبي — لا يؤثر على الأرصدة','test_refunded':'رد تجريبي',
}[value] ?? 'قيد المراجعة';

class GeideaPayments extends StatefulWidget {
  final String? invoiceId;
  const GeideaPayments({super.key,this.invoiceId});
  @override State<GeideaPayments> createState()=>_GeideaPaymentsState();
}
class _GeideaPaymentsState extends State<GeideaPayments> {
  final invoice=TextEditingController(),phone=TextEditingController(),email=TextEditingController();
  bool loading=true,busy=false,enabled=false;
  String error='',mode='test',requestId='';
  Map<String,dynamic> ledger={};
  @override void initState(){super.initState();invoice.text=widget.invoiceId??'';load();}
  @override void dispose(){invoice.dispose();phone.dispose();email.dispose();super.dispose();}
  Future<void> load() async {
    if(mounted)setState(()=>loading=true);
    try {
      final status=await geideaCall('geideaStatus');
      final next=await geideaCall('listGeideaPayments');
      if(widget.invoiceId!=null && phone.text.isEmpty){
        final sale=(await db.collection('sales').doc(widget.invoiceId).get()).data();
        final cid='${sale?['customerId']??''}';
        if(cid.isNotEmpty){final customer=(await db.collection('customers').doc(cid).get()).data();phone.text='${customer?['phone']??''}';}
      }
      if(mounted)setState((){enabled=status['enabled']==true;mode='${status['mode']??'test'}';ledger=next;error='';});
    }catch(e){if(mounted)setState(()=>error='$e');}
    finally {if(mounted)setState(()=>loading=false);}
  }
  Future<void> act(Future<void> Function() action) async {
    if(busy)return;setState(()=>busy=true);
    try {await action();await load();}
    catch(e){if(mounted)await showInvoiceSaveProblem(context,'$e',title:'راجع حالة الدفع',button:'تمام');}
    finally {if(mounted)setState(()=>busy=false);}
  }
  Future<void> create() async {
    final id=invoice.text.trim();
    if(id.isEmpty || id.contains('/'))throw StateError('اكتب رقم فاتورة مبيعات صحيحًا');
    final data=(await db.collection('sales').doc(id).get(const GetOptions(source:Source.server))).data();
    if(data==null || data['status']!='completed')throw StateError('الفاتورة غير متاحة للدفع');
    final remaining=((data['due'] as num?)?.toDouble()??0)-((data['receiptPaid'] as num?)?.toDouble()??0);
    if(remaining<=0)throw StateError('الفاتورة مسددة بالفعل');
    if(!mounted)return;
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('إنشاء رابط دفع'),
      content:Text('العميل: ${data['customerName']??''}\nالمبلغ المتبقي: ${remaining.toStringAsFixed(2)} ج.م\n${mode=='test'?'وضع تجريبي: لن تُحدّث الأرصدة.':'سيُسجّل السداد بعد تأكيد جيديا فقط.'}'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('إنشاء الرابط'))]))??false;
    if(!yes)return;
    if(requestId.isEmpty)requestId=db.collection('paymentRequests').doc().id;
    await geideaCall('createGeideaLink',{'invoiceId':id,'requestId':requestId,'phone':phone.text.trim(),'email':email.text.trim()});
  }
  Future<void> refund(Map row) async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('رد المبلغ للكارت'),
      content:Text('رد ${((row['net'] as num?)??0).toStringAsFixed(2)} ج.م إلى وسيلة الدفع الأصلية.\nلن يُخصم من الصندوق. بعد تأكيد الرد يمكنك إرجاع الفاتورة والمخزون.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('تأكيد رد الكارت'))]))??false;
    if(yes)await geideaCall('refundGeideaPayment',{'transactionId':row['transactionId']});
  }
  @override Widget build(BuildContext context){
    final requests=(ledger['requests'] as List?)??[],transactions=(ledger['transactions'] as List?)??[];
    return ListView(padding:const EdgeInsets.all(14),children:[
      const Text('جيديا',style:TextStyle(color:gold,fontSize:22,fontWeight:FontWeight.bold)),
      const Text('رابط دفع بالكارت للمتبقي على الفاتورة. السداد يظهر بعد تأكيد الشركة. تحويل البنك حسب عقد حساب التاجر.'),
      const SizedBox(height:10),
      if(loading)const LinearProgressIndicator(),
      if(error.isNotEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(error,style:const TextStyle(color:Colors.orangeAccent))),
      if(!enabled)const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('الخدمة غير مفعّلة بعد. يلزم حساب تاجر جيديا وربط حساب بنك مصر، ثم إعداد مفاتيح الربط على السيرفر.',style:TextStyle(color:Colors.orangeAccent))),
      if(enabled && mode=='test')const Text('وضع الاختبار — لا يغيّر أرصدة العملاء',style:TextStyle(color:Colors.orangeAccent)),
      OutlinedButton.icon(onPressed:()=>launchUrl(Uri.parse('https://www.geidea.net/egy/en/'),mode:LaunchMode.externalApplication),icon:const Icon(Icons.open_in_new),label:const Text('موقع جيديا وتفعيل حساب التاجر')),
      TextField(controller:invoice,readOnly:widget.invoiceId!=null,onChanged:(_)=>requestId='',decoration:const InputDecoration(labelText:'رقم فاتورة المبيعات')),
      TextField(controller:phone,keyboardType:TextInputType.phone,onChanged:(_)=>requestId='',decoration:const InputDecoration(labelText:'موبايل العميل')),
      TextField(controller:email,keyboardType:TextInputType.emailAddress,onChanged:(_)=>requestId='',decoration:const InputDecoration(labelText:'بريد العميل — اختياري')),
      const SizedBox(height:10),
      FilledButton.icon(onPressed:enabled&&!busy&&!loading?()=>act(create):null,icon:const Icon(Icons.link),label:const Text('إنشاء رابط دفع للفاتورة')),
      OutlinedButton.icon(onPressed:busy?null:load,icon:const Icon(Icons.refresh),label:const Text('تحديث السجل')),
      const Divider(),
      Text('تحصيل إلكتروني بانتظار مطابقة تحويل البنك: ${((ledger['clearingBalance'] as num?)??0).toStringAsFixed(2)} ج.م'),
      const Text('المبلغ منفصل عن الصندوق النقدي. الدفع من ظهر الموبايل يحتاج تفعيل خدمة قبول الكروت من جيديا؛ دعم NFC وحده لا يكفي.'),
      const SizedBox(height:14),const Text('روابط الفواتير — أحدث ٥٠ طلبًا',style:TextStyle(color:gold)),
      for(final raw in requests)Builder(builder:(context){final row=Map<String,dynamic>.from(raw as Map),url='${row['checkoutUrl']??''}';return Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${row['customerName']} • ${((row['amount'] as num?)??0).toStringAsFixed(2)} ج.م'),SelectableText('فاتورة: ${row['invoiceId']}'),Text(geideaState(row['state'])),
        Wrap(spacing:6,children:[if(url.isNotEmpty)TextButton(onPressed:busy?null:()=>launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication),child:const Text('فتح الرابط')),
          if(url.isNotEmpty)TextButton(onPressed:busy?null:()=>Share.share('رابط سداد فاتورة ${row['invoiceId']}\n$url'),child:const Text('مشاركة الرابط')),
          if(enabled)TextButton(onPressed:busy?null:()=>act(()async{await geideaCall('refreshGeideaPayment',{'requestId':row['requestId']});}),child:const Text('تحقق من السداد'))]),
      ])) );}),
      const Text('عمليات الدفع والرد — أحدث ٥٠ عملية',style:TextStyle(color:gold)),
      for(final raw in transactions)Builder(builder:(context){final row=Map<String,dynamic>.from(raw as Map);return Card(child:ListTile(title:Text('${row['customerName']} • ${geideaState(row['state'])}'),
        subtitle:Text('فاتورة ${row['invoiceId']}\nسداد ${row['gross']} • رد ${row['refunded']} • صافي ${row['net']} ج.م${row['refundState']=='unknown'?'\nرد غير مؤكد — تحقق من السداد ولا تكرر الطلب':''}'),
        trailing:enabled && ((row['net'] as num?)??0)>0 && !['unknown','requested'].contains(row['refundState'])?TextButton(onPressed:busy?null:()=>act(()=>refund(row)),child:const Text('رد للكارت')):null));}),
    ]);
  }
}
