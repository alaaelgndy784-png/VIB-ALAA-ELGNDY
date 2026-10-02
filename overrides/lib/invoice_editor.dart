part of 'main.dart';

class InvoiceEditorFrame extends StatelessWidget {
  final String title;
  final bool checkout;
  final double total;
  final Widget body;
  final Widget? toolbar;
  final Widget? headerAction;
  final List<Widget> actions;
  const InvoiceEditorFrame({super.key,required this.title,required this.checkout,required this.total,
    required this.body,required this.actions,this.toolbar,this.headerAction});
  @override Widget build(BuildContext context) => Dialog(
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
}

class InvoiceProductsBar extends StatelessWidget {
  final List<({String id,String name})> products;
  final bool enabled;
  final Map<String,num?> unitCosts;
  final Stream<int?> Function(String)? stockStreamFor;
  final VoidCallback onSearch;
  final ValueChanged<String> onSelect;
  const InvoiceProductsBar({super.key,required this.products,required this.enabled,required this.onSearch,required this.onSelect,this.unitCosts=const {},this.stockStreamFor});
  @override Widget build(BuildContext context) => Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    OutlinedButton.icon(onPressed:enabled ? onSearch : null,icon:const Icon(Icons.search,color:gold),label:const Text('بحث')),
    const SizedBox(height:6),
    DropdownButtonFormField<String>(
      key:ValueKey(products.map((p)=>p.id).join('|')),isExpanded:true,itemHeight:null,
      menuMaxHeight:MediaQuery.sizeOf(context).height*.7,dropdownColor:const Color(0xFF111015),
      decoration:_vibInvoiceInput('اختيار الصنف'),hint:const Text('اختيار الصنف'),
      selectedItemBuilder:(context)=>products.map((p)=>Align(alignment:AlignmentDirectional.centerStart,
        child:Text(p.name,maxLines:1,overflow:TextOverflow.ellipsis))).toList(),
      items:products.map((p)=>DropdownMenuItem(value:p.id,child:Padding(padding:const EdgeInsets.symmetric(vertical:8),
        child:InvoiceProductOptionRow(name:p.name,unitCost:unitCosts[p.id],quantityStream:stockStreamFor?.call(p.id))))).toList(),
      onChanged:enabled ? (id) {if(id != null) onSelect(id);} : null,
    ),
  ]);
}


Stream<int?> invoiceMainStock(String productId) => db.collection('stock').doc('main_$productId').snapshots()
    .map((snapshot) => snapshot.exists ? (snapshot.data()?['quantity'] as num?)?.toInt() : 0);

class InvoiceProductOptionRow extends StatelessWidget {
  final String name;
  final num? unitCost;
  final Stream<int?>? quantityStream;
  const InvoiceProductOptionRow({super.key,required this.name,this.unitCost,this.quantityStream});
  @override Widget build(BuildContext context) => Row(crossAxisAlignment:CrossAxisAlignment.center,children:[
    Expanded(flex:5,child:Text(name,softWrap:true,style:const TextStyle(fontSize:14))),
    const SizedBox(width:8),
    Expanded(flex:4,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      StreamBuilder<int?>(stream:quantityStream,builder:(context,snapshot)=>Text(
        'المتاح: ${snapshot.hasError ? 'تعذر التحميل' : snapshot.connectionState == ConnectionState.waiting ? 'جارٍ التحميل' : snapshot.data == null ? 'غير متاح' : snapshot.data}',
        softWrap:true,style:const TextStyle(fontSize:12,color:gold))),
      const SizedBox(height:3),
      Text('تكلفة الوحدة: ${unitCost == null ? 'غير مسجلة' : '${unitCost!.toStringAsFixed(2)} ج.م'}',
        softWrap:true,style:const TextStyle(fontSize:12)),
    ])),
  ]);
}
