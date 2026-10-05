part of 'main.dart';

class InvoiceEditorFrame extends StatelessWidget {
  final String title;
  final bool checkout;
  final double total;
  final bool tableMode;
  final int itemCount, quantityCount;
  final String invoiceNumber;
  final Widget body;
  final Widget? toolbar;
  final Widget? headerAction;
  final List<Widget> actions;
  const InvoiceEditorFrame({super.key,required this.title,required this.checkout,required this.total,
    required this.body,required this.actions,this.toolbar,this.headerAction,this.tableMode=false,
    this.itemCount=0,this.quantityCount=0,this.invoiceNumber='يُخصص عند الحفظ'});
  @override Widget build(BuildContext context) => tableMode ? _tableFrame(context) : Dialog(
    backgroundColor:const Color(0xFF080808),insetPadding:const EdgeInsets.symmetric(horizontal:6,vertical:10),
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:const BorderSide(color:gold)),
    child:SizedBox(width:650,height:double.infinity,child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[
      Padding(padding:const EdgeInsets.only(bottom:10),child:Row(children:[
        if(headerAction != null) headerAction!,
        Expanded(child:Text(title,textAlign:TextAlign.center,style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold))),
        if(headerAction != null) const SizedBox(width:48),
      ])),
      if(!checkout && toolbar != null) Padding(padding:const EdgeInsets.only(bottom:10),child:toolbar!),
      Expanded(child:body),
      if(!checkout) Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Row(children:[
        const Expanded(child:Text('الإجمالي',style:TextStyle(fontSize:15))),
        Flexible(child:FittedBox(fit:BoxFit.scaleDown,child:Text('${total.toStringAsFixed(2)} ج.م',
          style:const TextStyle(color:gold,fontSize:22,fontWeight:FontWeight.bold)))),
      ])),
      const SizedBox(height:4),
      Wrap(alignment:WrapAlignment.end,spacing:8,runSpacing:4,children:actions),
    ]))),
  );
  Widget _tableFrame(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFF080808),
    insetPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
    child: SizedBox(width: 650,
      height: checkout ? (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom - 48).clamp(180.0, 640.0).toDouble() : double.infinity,
      child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
        Row(children: [if(headerAction != null) headerAction!,
          Expanded(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: gold))),
        ]),
        if(!checkout) ...[
          if(MediaQuery.viewInsetsOf(context).bottom==0) Container(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8), color: const Color(0xFF282215),
            child: Row(children: [Expanded(child: Text('رقم الفاتورة: $invoiceNumber', style: const TextStyle(fontSize: 11, color: gold))),
              Text(DateFormat('yyyy-MM-dd').format(DateTime.now()), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12)),
            ])),
          if(toolbar != null) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: toolbar!),
          const InvoiceCompactTableHeader(),
        ],
        Expanded(child: checkout ? body : Container(color: Colors.white,
          child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.black), child: body))),
        if(!checkout) Container(color: const Color(0xFF282215), padding: const EdgeInsets.all(8),
          child: Row(children: [Text('الأصناف: $itemCount • العدد: $quantityCount', style: const TextStyle(fontSize: 11, color: Colors.white)),
            const SizedBox(width: 8), Expanded(child: Align(alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown,
              child:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:6),decoration:BoxDecoration(color:staffApp ? const Color(0xFF1565C0) : null,borderRadius:BorderRadius.circular(6)),child:Text('الإجمالي: ${total.toStringAsFixed(2)} ج.م',style:TextStyle(color:staffApp ? Colors.white : Colors.greenAccent,fontSize:18,fontWeight:FontWeight.bold)))))),
          ])),
        const SizedBox(height: 6),
        Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 4, children: actions),
      ])),
    ),
  );

}

class InvoiceProductsBar extends StatefulWidget {
  final List<({String id,String name})> products;
  final bool enabled;
  final bool inlineSearch,saleScreen;
  final Map<String,num?> unitCosts;
  final Stream<int?> Function(String)? stockStreamFor;
  final VoidCallback onSearch;
  final ValueChanged<String> onSelect;
  const InvoiceProductsBar({super.key,required this.products,required this.enabled,required this.onSearch,required this.onSelect,this.unitCosts=const {},this.stockStreamFor,this.inlineSearch=false,this.saleScreen=false});
  @override State<InvoiceProductsBar> createState() => _InvoiceProductsBarState();
}

class _InvoiceProductsBarState extends State<InvoiceProductsBar> {
  final search = TextEditingController();
  @override void dispose() { search.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final products=widget.products, enabled=widget.enabled, onSearch=widget.onSearch;
    final onSelect=widget.onSelect, unitCosts=widget.unitCosts, stockStreamFor=widget.stockStreamFor;
    if(widget.inlineSearch) {
      final query=search.text.trim().toLowerCase();
      final rows=products.where((p)=>p.name.toLowerCase().contains(query)).toList()
        ..sort((a,b)=>a.name.compareTo(b.name));
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        TextField(key:const ValueKey('invoice-inline-search'),controller:search,enabled:enabled,
          decoration:_vibInvoiceInput('بحث عن صنف',icon:Icons.search).copyWith(suffixIcon:IconButton(
            tooltip:'عرض كل الأصناف',onPressed:enabled ? onSearch : null,icon:const Icon(Icons.list_alt,color:gold))),
          onChanged:(_)=>setState(() {})),
        if(query.isNotEmpty) SizedBox(height:(MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom - 330).clamp(60.0,160.0).toDouble(),
          child: rows.isEmpty ? const Center(child:Text('لا توجد أصناف مطابقة')) : ListView.separated(
            itemCount:rows.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,index) {
              final product=rows[index];
              return InkWell(key:ValueKey('inline-product-${product.id}'),onTap:enabled ? () {
                FocusScope.of(context).unfocus(); search.clear();setState(() {});onSelect(product.id);
              } : null,child:Padding(padding:const EdgeInsets.symmetric(vertical:8,horizontal:4),
                child:InvoiceProductOptionRow(saleScreen:widget.saleScreen,name:product.name,unitCost:unitCosts[product.id],quantityStream:stockStreamFor?.call(product.id))));
            })),
      ]);
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    OutlinedButton.icon(onPressed:enabled ? onSearch : null,icon:const Icon(Icons.search,color:gold),label:const Text('بحث')),
    const SizedBox(height:6),
    DropdownButtonFormField<String>(
      key:ValueKey(products.map((p)=>p.id).join('|')),isExpanded:true,itemHeight:null,
      menuMaxHeight:MediaQuery.sizeOf(context).height*.7,dropdownColor:const Color(0xFF111015),
      decoration:_vibInvoiceInput('اختيار الصنف'),hint:const Text('اختيار الصنف'),
      selectedItemBuilder:(context)=>products.map((p)=>Align(alignment:AlignmentDirectional.centerStart,
        child:Text(p.name,maxLines:1,overflow:TextOverflow.ellipsis))).toList(),
      items:products.map((p)=>DropdownMenuItem(value:p.id,child:Padding(padding:const EdgeInsets.symmetric(vertical:8),
        child:InvoiceProductOptionRow(saleScreen:widget.saleScreen,name:p.name,unitCost:unitCosts[p.id],quantityStream:stockStreamFor?.call(p.id))))).toList(),
      onChanged:enabled ? (id) {if(id != null) onSelect(id);} : null,
    ),
  ]);
  }
}


Stream<int?> invoiceMainStock(String productId) => db.collection('stock').doc('main_$productId').snapshots()
    .map((snapshot) => snapshot.exists ? (snapshot.data()?['quantity'] as num?)?.toInt() : 0);

class InvoiceProductOptionRow extends StatelessWidget {
  final String name;
  final bool saleScreen;
  final num? unitCost;
  final Stream<int?>? quantityStream;
  const InvoiceProductOptionRow({super.key,required this.name,this.unitCost,this.quantityStream,this.saleScreen=false});
  @override Widget build(BuildContext context) => Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
    Expanded(flex:5,child:Text(name,softWrap:true,style:TextStyle(fontSize:14,color:staffApp ? Colors.lightBlueAccent : null))),
    const SizedBox(width:8),
    Expanded(flex:4,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      StreamBuilder<int?>(stream:quantityStream,builder:(context,snapshot)=>Text(
        'المتاح: ${snapshot.hasError ? 'تعذر التحميل' : snapshot.connectionState == ConnectionState.waiting ? 'جارٍ التحميل' : snapshot.data == null ? 'غير متاح' : snapshot.data}',
        softWrap:true,style:TextStyle(fontSize:12,color:staffApp ? Colors.redAccent : gold))),
      ValueListenableBuilder<bool>(valueListenable:saleCostVisible,builder:(context,visible,_)=>!saleScreen || visible ? Text('تكلفة الوحدة: ${unitCost == null ? 'غير مسجلة' : '${unitCost!.toStringAsFixed(2)} ج.م'}',
        softWrap:true,style:TextStyle(fontSize:12,color:staffApp ? Colors.greenAccent : null)) : const SizedBox.shrink()),
    ])),
  ]);
}


Future<String?> showInvoiceProductChoices(BuildContext context, {
  required List<({String id,String name})> products,
  required Set<String> excluded,
  Map<String,num?> unitCosts = const {},
  bool saleScreen=false,
  Stream<int?> Function(String)? stockStreamFor,
}) => showModalBottomSheet<String>(
  context:context,isScrollControlled:true,useSafeArea:true,
  constraints:const BoxConstraints(maxWidth:650),backgroundColor:const Color(0xFF111015),
  shape:const RoundedRectangleBorder(borderRadius:BorderRadius.vertical(top:Radius.circular(16))),
  builder:(sheet)=>Directionality(textDirection:TextDirection.rtl,child:InvoiceProductSearchList(
    products:products,excluded:excluded,unitCosts:unitCosts,stockStreamFor:stockStreamFor,saleScreen:saleScreen,
    onSelect:(id)=>Navigator.pop(sheet,id),onClose:()=>Navigator.pop(sheet),
  )),
);

class InvoiceProductSearchList extends StatefulWidget {
  final List<({String id,String name})> products;
  final Set<String> excluded;
  final bool saleScreen;
  final Map<String,num?> unitCosts;
  final Stream<int?> Function(String)? stockStreamFor;
  final ValueChanged<String> onSelect;
  final VoidCallback onClose;
  const InvoiceProductSearchList({super.key,required this.products,required this.excluded,
    required this.onSelect,required this.onClose,this.unitCosts=const {},this.stockStreamFor,this.saleScreen=false});
  @override State<InvoiceProductSearchList> createState()=>_InvoiceProductSearchListState();
}

class _InvoiceProductSearchListState extends State<InvoiceProductSearchList> {
  String _query='';
  @override Widget build(BuildContext context) {
    final rows=widget.products.where((p)=>!widget.excluded.contains(p.id) && p.name.toLowerCase().contains(_query)).toList()
      ..sort((a,b)=>a.name.compareTo(b.name));
    return SizedBox(width:double.infinity,height:MediaQuery.sizeOf(context).height*.90,
      child:Padding(padding:EdgeInsets.fromLTRB(10,8,10,MediaQuery.viewInsetsOf(context).bottom+8),child:Column(children:[
        Row(children:[const Expanded(child:Text('اختيار الصنف',style:TextStyle(fontSize:18,color:gold))),
          IconButton(tooltip:'إغلاق البحث',onPressed:widget.onClose,icon:const Icon(Icons.close,color:gold))]),
        TextField(autofocus:false,decoration:_vibInvoiceInput('بحث باسم الصنف',icon:Icons.search),
          onChanged:(value)=>setState(()=>_query=value.trim().toLowerCase())),
        const SizedBox(height:8),
        Expanded(child:rows.isEmpty ? const Center(child:Text('لا توجد أصناف مطابقة')) : ListView.separated(
          itemCount:rows.length,separatorBuilder:(_,__)=>const Divider(height:1,color:Color(0xFF363239)),
          itemBuilder:(context,index) {
            final product=rows[index];
            return InkWell(key:ValueKey('product-choice-${product.id}'),onTap:()=>widget.onSelect(product.id),
              child:Padding(padding:const EdgeInsets.symmetric(vertical:14,horizontal:4),child:InvoiceProductOptionRow(
                saleScreen:widget.saleScreen,name:product.name,unitCost:widget.unitCosts[product.id],quantityStream:widget.stockStreamFor?.call(product.id),
              )));
          },
        )),
      ])));
  }
}


class InvoiceCompactTableHeader extends StatelessWidget {
  const InvoiceCompactTableHeader({super.key});
  @override Widget build(BuildContext context) => Container(color: gold, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: const Row(textDirection: TextDirection.rtl, children: [
      SizedBox(width: 22, child: Text('م', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontSize: 11))),
      Expanded(flex: 5, child: Text('المنتج', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold))),
      Expanded(flex: 3, child: Text('السعر', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold))),
      Expanded(flex: 2, child: Text('العدد', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold))),
      Expanded(flex: 3, child: Text('الإجمالي', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold))),
    ]));
}

class InvoiceCompactTableLine extends StatelessWidget {
  final int number;
  final String name;
  final TextEditingController price, quantity;
  final VoidCallback? onEdit;
  const InvoiceCompactTableLine({super.key,required this.number,required this.name,required this.price,required this.quantity,this.onEdit});
  @override Widget build(BuildContext context) {
    final p=double.tryParse(price.text.trim().replaceAll(',', '.')) ?? 0;
    final q=int.tryParse(quantity.text.trim()) ?? 0;
    Widget value(String text,{Color? background})=>Container(margin:const EdgeInsets.all(2),padding:const EdgeInsets.symmetric(vertical:7,horizontal:2),
      decoration:BoxDecoration(color:background,border:Border.all(color:const Color(0xFFD4D4D4))),
      child:FittedBox(fit:BoxFit.scaleDown,child:Text(text,style:const TextStyle(color:Colors.black,fontSize:12,fontWeight:FontWeight.w600))));
    return Material(color:number.isOdd ? Colors.white : const Color(0xFFF5F4F0),child:InkWell(onTap:onEdit,
      child:Container(padding:const EdgeInsets.symmetric(vertical:8,horizontal:4),
        decoration:const BoxDecoration(border:Border(bottom:BorderSide(color:Color(0xFFDDDDDD)))),
        child:Row(textDirection:TextDirection.rtl,children:[
          SizedBox(width:22,child:Text('$number',textAlign:TextAlign.center,style:const TextStyle(color:Colors.black54,fontSize:11))),
          Expanded(flex:5,child:Text(name,textDirection:TextDirection.rtl,style:TextStyle(color:staffApp ? const Color(0xFF0056B3) : Colors.black,fontSize:12))),
          Expanded(flex:3,child:value(p.toStringAsFixed(2),background:staffApp ? const Color(0xFFB9F6CA) : null)),
          Expanded(flex:2,child:value('$q',background:staffApp ? const Color(0xFFFFF59D) : null)),
          Expanded(flex:3,child:value((p*q).toStringAsFixed(2),background:staffApp ? const Color(0xFF90CAF9) : null)),
        ]))));
  }
}

enum InvoiceLineEditAction { apply, delete }
class _InvoiceLineEditorResult {
  final InvoiceLineEditAction action;
  final String price,quantity;
  final double? baseCost;
  final double percent;
  _InvoiceLineEditorResult(this.action,this.price,this.quantity,this.baseCost,this.percent);
}

Future<InvoiceLineEditAction?> showInvoiceLineEditor(BuildContext context, {
  required String name,required TextEditingController price,required TextEditingController quantity,
  required PurchaseDiscountDraft discount, bool priceEditable=true,bool allowDelete=false,
  num? unitCost,Stream<int?>? stockStream,bool saleScreen=false,
}) async {
  final result=await showDialog<_InvoiceLineEditorResult>(context:context,barrierDismissible:false,
    builder:(_)=>_InvoiceLineEditorDialog(name:name,initialPrice:price.text,initialQuantity:quantity.text,
      baseCost:discount.baseCost,percent:discount.percent,priceEditable:priceEditable,
      allowDelete:allowDelete,unitCost:unitCost,stockStream:stockStream,saleScreen:saleScreen));
  if(result?.action==InvoiceLineEditAction.apply) {
    quantity.text=result!.quantity;price.text=result.price;
    discount.baseCost=result.baseCost;discount.percent=result.percent;
  }
  return result?.action;
}

class _InvoiceLineEditorDialog extends StatefulWidget {
  final String name,initialPrice,initialQuantity;
  final double? baseCost;
  final double percent;
  final bool priceEditable,allowDelete,saleScreen;
  final num? unitCost;
  final Stream<int?>? stockStream;
  const _InvoiceLineEditorDialog({required this.name,required this.initialPrice,required this.initialQuantity,
    required this.baseCost,required this.percent,required this.priceEditable,required this.allowDelete,this.unitCost,this.stockStream,this.saleScreen=false});
  @override State<_InvoiceLineEditorDialog> createState()=>_InvoiceLineEditorDialogState();
}

class _InvoiceLineEditorDialogState extends State<_InvoiceLineEditorDialog> {
  late final TextEditingController draftPrice,draftQuantity;
  late final PurchaseDiscountDraft draftDiscount;
  @override void initState() {
    super.initState();draftPrice=TextEditingController(text:widget.initialPrice);draftQuantity=TextEditingController(text:widget.initialQuantity);
    draftDiscount=PurchaseDiscountDraft()..baseCost=widget.baseCost..percent=widget.percent;
  }
  @override void dispose() {draftPrice.dispose();draftQuantity.dispose();super.dispose();}
  void finish(InvoiceLineEditAction action)=>Navigator.pop(context,_InvoiceLineEditorResult(
    action,draftPrice.text,draftQuantity.text,draftDiscount.baseCost,draftDiscount.percent));
  @override Widget build(BuildContext context)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
    insetPadding:const EdgeInsets.symmetric(horizontal:12,vertical:16),contentPadding:const EdgeInsets.all(10),
    title:const Text('بيانات الصنف'),
    content:SizedBox(width:450,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      PurchaseInvoiceLine(number:1,name:widget.name,cost:draftPrice,quantity:draftQuantity,enabled:true,
        priceEditable:widget.priceEditable,totalEditable:widget.priceEditable,discountEditable:widget.saleScreen,discountDraft:draftDiscount,showProductActions:false,
        onChoose:() {},onDelete:() {},onChanged:()=>setState(() {})),
      if(widget.stockStream!=null) StreamBuilder<int?>(stream:widget.stockStream,builder:(context,snapshot)=>Text(
        'الكمية المتوفرة: ${snapshot.hasError ? 'تعذر التحميل' : snapshot.data ?? 'جارٍ التحميل'}',style:TextStyle(color:staffApp ? Colors.redAccent : gold))),
      if(widget.unitCost!=null) ValueListenableBuilder<bool>(valueListenable:saleCostVisible,builder:(context,visible,_)=>!widget.saleScreen || visible ? Text('سعر التكلفة: ${widget.unitCost!.toStringAsFixed(2)} ج.م',style:TextStyle(color:staffApp ? Colors.greenAccent : gold)) : const SizedBox.shrink()),
    ]))),
    actions:[
      if(widget.allowDelete) TextButton.icon(icon:const Icon(Icons.delete_outline,color:Colors.redAccent),label:const Text('حذف الصنف'),
        onPressed:()=>finish(InvoiceLineEditAction.delete)),
      TextButton(onPressed:()=>Navigator.pop(context),child:const Text('تراجع')),
      FilledButton(onPressed:() async {
        final q=int.tryParse(draftQuantity.text.trim()),p=double.tryParse(draftPrice.text.trim().replaceAll(',', '.'));
        if(q==null || q<=0 || p==null || !p.isFinite || p<0) {
          await showInvoiceSaveProblem(context,'أدخل عددًا أكبر من صفر وسعرًا صحيحًا',title:'بيانات الصنف',button:'رجوع للصنف');return;
        }
        finish(InvoiceLineEditAction.apply);
      },child:const Text('متابعة')),
    ],
  ));
}

Future<String> invoiceDraftNumberPreview(String type) async {
  try {
    final data=(await db.collection('settings').doc('invoiceCounter_$type').get()).data();
    return '${((data?['lastNumber'] as num?)?.toInt() ?? 0)+1}'.padLeft(6,'0')+' (مبدئي)';
  } catch(_) { return 'يُخصص عند الحفظ'; }
}

