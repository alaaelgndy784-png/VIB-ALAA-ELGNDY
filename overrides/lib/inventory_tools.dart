part of 'main.dart';

void openInventoryPrices(BuildContext context) => Navigator.push(context, MaterialPageRoute(builder: (_) =>
  const Directionality(textDirection: TextDirection.rtl, child: InventoryPriceAdjustment())));

class InventoryPriceAdjustment extends StatefulWidget {
  const InventoryPriceAdjustment({super.key});
  @override State<InventoryPriceAdjustment> createState() => _InventoryPriceAdjustmentState();
}

class _InventoryPriceAdjustmentState extends State<InventoryPriceAdjustment> {
  final percent = TextEditingController(), search = TextEditingController();
  List<QueryDocumentSnapshot<Map<String, dynamic>>> products = [];
  final selected = <String>{};
  List<Map<String, dynamic>>? preview;
  String field = 'price', category = 'الكل', error = '', operation = '';
  bool increase = true, loading = true, saving = false, attempted = false;
  int completed = 0;
  @override void initState() { super.initState(); load(); }
  @override void dispose() { percent.dispose(); search.dispose(); super.dispose(); }
  Future<void> load() async {
    try {
      final data = await db.collection('products').get(const GetOptions(source: Source.server));
      final pending = (await db.collection('settings').doc('priceChangePending_${FirebaseAuth.instance.currentUser!.uid}').get(const GetOptions(source: Source.server))).data();
      if (!mounted) return;
      setState(() { products = data.docs.where((d) => d.data()['active'] == true).toList()
        ..sort((a,b) => '${a.data()['name']}'.compareTo('${b.data()['name']}')); loading = false;
        if(pending?['status']=='pending') {
          preview=(pending!['rows'] as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList();
          operation=pending['operationId'] as String; field=pending['field'] as String;
          increase=pending['increase'] as bool; percent.text='${pending['percent']}'; attempted=true;
          error='يوجد تعديل أسعار لم يكتمل؛ اضغط استكمال التعديل. الأصناف المكتملة لن تُعدّل مرتين.';
        }
      });
    } catch (e) { if (mounted) setState(() { loading = false; error = 'تعذر تحميل الأصناف: $e'; }); }
  }
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get filtered => products.where((p) =>
    (category == 'الكل' || '${p.data()['category'] ?? 'غير مصنف'}' == category) &&
    '${p.data()['name']}'.toLowerCase().contains(search.text.trim().toLowerCase())).toList();
  String get label => field == 'price' ? 'سعر البيع' : field == 'purchasePrice' ? 'سعر الشراء' : 'الشراء والبيع';
  void prepare() {
    try {
      final text = percent.text.trim().replaceAll('٫', '.').replaceAllMapped(RegExp('[٠-٩]'), (m) => '${'٠١٢٣٤٥٦٧٨٩'.indexOf(m[0]!)}');
      final rate = double.tryParse(text);
      if (rate == null || selected.isEmpty) throw StateError('اختار الأصناف واكتب النسبة');
      final fields = field == 'both' ? ['purchasePrice','price'] : [field];
      final plan = <Map<String, dynamic>>[];
      for (final p in products.where((p) => selected.contains(p.id))) {
        final before = <String, num>{}, after = <String, num>{};
        for (final key in fields) {
          final value = p.data()[key];
          if (value is! num) throw StateError('السعر غير مسجل للصنف: ${p.data()['name']}');
          before[key] = value; after[key] = adjustedInventoryPrice(value, rate, increase: increase);
        }
        if (fields.any((k) => before[k] != after[k])) plan.add({'id':p.id,'name':p.data()['name'],'before':before,'after':after});
      }
      if (plan.isEmpty) throw StateError('النسبة لا تغيّر الأسعار المختارة بعد التقريب');
      if (utf8.encode(jsonEncode(plan)).length > 800000) throw StateError('اختار عددًا أقل من الأصناف في العملية الواحدة');
      setState(() { preview = plan; error = ''; completed = 0; operation = db.collection('settings').doc().id; });
    } catch (e) { setState(() => error = '$e'); }
  }
  Future<void> apply() async {
    if (saving || preview == null) return;
    setState(() {saving = true; attempted = true; error = '';});
    try {
      final actor = FirebaseAuth.instance.currentUser!.uid;
      final pendingRef=db.collection('settings').doc('priceChangePending_$actor');
      await db.runTransaction((tx) async {
        final owner=await tx.get(db.collection('users').doc(actor));
        final pending=await tx.get(pendingRef);
        if(owner.data()?['role']!='owner'||owner.data()?['active']!=true)throw StateError('تعديل الأسعار للمدير فقط');
        if(pending.data()?['status']=='pending'&&pending.data()?['operationId']!=operation)throw StateError('يوجد تعديل آخر؛ أعد فتح الشاشة لاستكماله');
        tx.set(pendingRef,{'kind':'inventoryPriceOperation','status':'pending','operationId':operation,'rows':preview,
          'field':field,'increase':increase,'percent':percent.text,'actorId':actor,'updatedAt':FieldValue.serverTimestamp()});
      });
      for (int start = 0; start < preview!.length; start += 20) {
        final chunk = preview!.skip(start).take(20).toList();
        await db.runTransaction((tx) async {
          final owner = await tx.get(db.collection('users').doc(actor));
          final pending=await tx.get(pendingRef);
          if (owner.data()?['role'] != 'owner' || owner.data()?['active'] != true) throw StateError('تعديل الأسعار للمدير فقط');
          if(pending.data()?['operationId']!=operation||pending.data()?['status']!='pending')throw StateError('عملية التعديل تغيّرت؛ أعد فتح الشاشة');
          final live = <String, DocumentSnapshot<Map<String,dynamic>>>{};
          final markers = <String, DocumentSnapshot<Map<String,dynamic>>>{};
          for (final row in chunk) {
            final id = row['id'] as String;
            markers[id] = await tx.get(db.collection('settings').doc('priceChange_${operation}_$id'));
            live[id] = await tx.get(db.collection('products').doc(id));
          }
          for (final row in chunk) {
            final id = row['id'] as String;
            if (markers[id]!.exists) continue;
            final before = Map<String,num>.from(row['before'] as Map);
            final data = live[id]!.data();
            if (data == null || data['active'] != true || before.keys.any((k) => data[k] != before[k])) {
              throw StateError('سعر الصنف تغيّر؛ راجع الأسعار الجديدة: ${row['name']}');
            }
          }
          for (final row in chunk) {
            final id = row['id'] as String;
            if (markers[id]!.exists) continue;
            tx.update(live[id]!.reference, {...Map<String,num>.from(row['after'] as Map), 'updatedAt':FieldValue.serverTimestamp()});
            tx.set(markers[id]!.reference, {'kind':'inventoryPriceChange','operationId':operation,'productId':id,
              'productName':row['name'],'before':row['before'],'after':row['after'],'actorId':actor,'createdAt':FieldValue.serverTimestamp()});
          }
        });
        if (mounted) setState(() => completed = start + chunk.length);
      }
      await db.runTransaction((tx)async{
        final pending=await tx.get(pendingRef);
        if(pending.data()?['operationId']==operation)tx.update(pendingRef,{'status':'completed','updatedAt':FieldValue.serverTimestamp()});
      });
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (c) => AlertDialog(title: const Text('تم تعديل الأسعار'),
        content: Text('تم تحديث أسعار ${preview!.length} صنفًا بنجاح.'),
        actions:[FilledButton(onPressed:()=>Navigator.pop(c),child:const Text('تمام'))]));
      if (mounted) Navigator.pop(context);
    } catch (e) { if (mounted) setState(() => error = 'تم تنفيذ $completed من ${preview!.length}. $e\nإعادة المحاولة لا تكرر التعديل على الأصناف المكتملة.'); }
    finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> cancelRemaining() async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('إلغاء بقية التعديل'),
      content:const Text('الأسعار التي تم حفظها ستظل كما هي. سيتم إلغاء الأصناف التي لم تُعدّل فقط.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('رجوع')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('إلغاء البقية'))]))??false;
    if(!yes||!mounted)return;
    setState(()=>saving=true);
    try{
      final ref=db.collection('settings').doc('priceChangePending_${FirebaseAuth.instance.currentUser!.uid}');
      await db.runTransaction((tx)async{final snap=await tx.get(ref);if(snap.data()?['operationId']==operation)tx.update(ref,{'status':'cancelled','updatedAt':FieldValue.serverTimestamp()});});
      if(mounted)Navigator.pop(context);
    }catch(e){if(mounted)setState(()=>error='تعذر إلغاء البقية: $e');}
    finally{if(mounted)setState(()=>saving=false);}
  }
  @override Widget build(BuildContext context) => PopScope(canPop: !saving, child: Scaffold(
    appBar: AppBar(title: const Text('زيادة / تخفيض أسعار الأصناف')),
    body: loading ? const Center(child:CircularProgressIndicator()) : Column(children:[
      if (error.isNotEmpty) Padding(padding:const EdgeInsets.all(12),child:Text(error,style:const TextStyle(color:Colors.redAccent))),
      if (preview == null) ...[
        Padding(padding:const EdgeInsets.all(12),child:Column(children:[
          DropdownButtonFormField<String>(value:field,decoration:const InputDecoration(labelText:'الأسعار المطلوب تعديلها'),items:const[
            DropdownMenuItem(value:'price',child:Text('سعر البيع')),DropdownMenuItem(value:'purchasePrice',child:Text('سعر الشراء')),
            DropdownMenuItem(value:'both',child:Text('سعر الشراء والبيع'))],onChanged:(v)=>setState(()=>field=v!)),
          Row(children:[Expanded(child:TextField(controller:percent,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'النسبة ٪'))),
            const SizedBox(width:12),DropdownButton<bool>(value:increase,items:const[DropdownMenuItem(value:true,child:Text('زيادة +')),DropdownMenuItem(value:false,child:Text('نقصان −'))],onChanged:(v)=>setState(()=>increase=v!))]),
          DropdownButtonFormField<String>(value:category,decoration:const InputDecoration(labelText:'تصفية بالفئة'),items:{'الكل',...products.map((p)=>'${p.data()['category'] ?? 'غير مصنف'}')}.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>category=v!)),
          TextField(controller:search,decoration:const InputDecoration(labelText:'بحث عن صنف',prefixIcon:Icon(Icons.search)),onChanged:(_)=>setState((){})),
          Wrap(spacing:12,children:[TextButton(onPressed:()=>setState(()=>selected.addAll(filtered.map((p)=>p.id))),child:const Text('تحديد كل النتائج')),
            TextButton(onPressed:()=>setState(()=>selected.clear()),child:const Text('إلغاء التحديد')),Text('المختار: ${selected.length}')]),
        ])),
        Expanded(child:ListView.builder(itemCount:filtered.length,itemBuilder:(c,i){final p=filtered[i];return CheckboxListTile(value:selected.contains(p.id),title:Text('${p.data()['name']}'),subtitle:Text('شراء: ${p.data()['purchasePrice'] ?? 'غير مسجل'} • بيع: ${p.data()['price'] ?? 'غير مسجل'}'),onChanged:(v)=>setState(()=>v==true?selected.add(p.id):selected.remove(p.id)));})),
        Padding(padding:const EdgeInsets.all(12),child:FilledButton.icon(onPressed:prepare,icon:const Icon(Icons.visibility),label:const Text('معاينة الأسعار الجديدة'))),
      ] else ...[
        Padding(padding:const EdgeInsets.all(12),child:Text('$label • ${increase ? 'زيادة' : 'نقصان'} ${percent.text}٪ • ${preview!.length} صنفًا\nالتعديل يطبق على السعر الحالي. الفواتير المحفوظة تحتفظ بأسعارها.')),
        Expanded(child:ListView(children:preview!.map((r)=>ListTile(title:Text('${r['name']}'),subtitle:Text((r['before'] as Map).keys.map((k)=>'${k=='price'?'بيع':'شراء'}: ${(r['before'][k] as num).toStringAsFixed(2)} ← ${(r['after'][k] as num).toStringAsFixed(2)}').join('\n')))).toList())),
        if(saving) Padding(padding:const EdgeInsets.all(12),child:Text('جارٍ الحفظ: $completed / ${preview!.length}')),
        SafeArea(child:Padding(padding:const EdgeInsets.all(12),child:Wrap(spacing:12,children:[
          if(!attempted) TextButton(onPressed:saving?null:()=>setState(()=>preview=null),child:const Text('رجوع للاختيار')),
          if(attempted) TextButton(onPressed:saving?null:cancelRemaining,child:const Text('إلغاء بقية التعديل')),
          FilledButton(onPressed:saving?null:apply,child:Text(saving?'جارٍ الحفظ…':attempted?'استكمال التعديل':'تأكيد تعديل الأسعار')),
        ]))),
      ],
    ]),
  ));
}

class InvoiceReturnPage extends StatefulWidget {
  final String type;
  const InvoiceReturnPage({super.key,required this.type});
  @override State<InvoiceReturnPage> createState()=>_InvoiceReturnPageState();
}
class _InvoiceReturnPageState extends State<InvoiceReturnPage> {
  final number=TextEditingController();
  List<QueryDocumentSnapshot<Map<String,dynamic>>> invoices=[];
  String error='';bool loading=false;
  bool get sales=>widget.type=='sales';
  @override void dispose(){number.dispose();super.dispose();}
  Future<void> find() async {
    setState((){loading=true;error='';invoices=[];});
    try {
      final key=number.text.trim();
      final query=db.collection(widget.type);
      // Show all matching numbers rather than choosing an ambiguous supplier invoice.
      final result=key.isEmpty?await query.orderBy('createdAt',descending:true).limit(100).get(const GetOptions(source:Source.server)):
        await query.where('invoiceNumber',isEqualTo:key).get(const GetOptions(source:Source.server));
      final rows=result.docs.where((d)=>visibleAfterReset(d.data())).toList();
      if(key.isNotEmpty&&!key.contains('/')){
        final direct=await query.doc(key).get(const GetOptions(source:Source.server));
        if(direct.exists&&visibleAfterReset(direct.data()!)&&!rows.any((r)=>r.id==direct.id)){
          // Resolve document IDs through a bounded query so the row type is consistent.
          final match=await query.where(FieldPath.documentId,isEqualTo:key).get(const GetOptions(source:Source.server));
          rows.addAll(match.docs);
        }
      }
      if(mounted)setState(()=>invoices=rows);
    }catch(e){if(mounted)setState(()=>error='تعذر تحميل الفواتير: $e');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Column(children:[
      Text(sales?'مرتجع المبيعات يضيف الكميات إلى مخزون الفاتورة.':'مرتجع المشتريات يخصم الكميات من المخزون الرئيسي.'),
      TextField(controller:number,decoration:const InputDecoration(labelText:'رقم الفاتورة أو رمزها الكامل'),onSubmitted:(_)=>find()),
      FilledButton.icon(onPressed:loading?null:find,icon:const Icon(Icons.search),label:Text(number.text.trim().isEmpty?'عرض آخر 100 فاتورة':'بحث')),
    ])),
    if(error.isNotEmpty)Text(error,style:const TextStyle(color:Colors.redAccent)),
    if(loading)const CircularProgressIndicator(),
    Expanded(child:ListView(children:invoices.map((d){final data=d.data();return Card(child:ListTile(
      title:Text('فاتورة ${data['invoiceNumber']?.toString().isNotEmpty==true?data['invoiceNumber']:d.id}'),
      subtitle:Text('${data[sales?'customerName':'supplierName'] ?? ''}\n${formatDate(data['createdAt'])} • الإجمالي: ${data['total']}\n${data['status']=='returned'?'تم إرجاعها بالفعل':'اضغط لمراجعة الفاتورة وإرجاعها'}'),
      onTap:()=>invoiceActions(context,widget.type,d.id,data),
    ));}).toList())),
  ]);
}
