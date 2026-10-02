part of 'main.dart';

class InvoiceEditorFrame extends StatelessWidget {
  final String title;
  final bool checkout;
  final double total;
  final Widget body;
  final Widget? toolbar;
  final List<Widget> actions;
  const InvoiceEditorFrame({super.key,required this.title,required this.checkout,required this.total,
    required this.body,required this.actions,this.toolbar});
  @override Widget build(BuildContext context) => Dialog(
    backgroundColor:const Color(0xFF080808),insetPadding:const EdgeInsets.symmetric(horizontal:6,vertical:10),
    shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16),side:const BorderSide(color:gold)),
    child:SizedBox(width:650,height:double.infinity,child:Padding(padding:const EdgeInsets.all(10),child:Column(children:[
      Padding(padding:const EdgeInsets.only(bottom:10),child:Text(title,style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold))),
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
  final VoidCallback onSearch;
  final ValueChanged<String> onSelect;
  const InvoiceProductsBar({super.key,required this.products,required this.enabled,required this.onSearch,required this.onSelect});
  @override Widget build(BuildContext context) => Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    OutlinedButton.icon(onPressed:enabled ? onSearch : null,icon:const Icon(Icons.search,color:gold),label:const Text('بحث')),
    const SizedBox(height:6),
    DropdownButtonFormField<String>(
      key:ValueKey(products.map((p)=>p.id).join('|')),isExpanded:true,
      decoration:_vibInvoiceInput('اختيار الصنف'),hint:const Text('اختيار الصنف'),
      items:products.map((p)=>DropdownMenuItem(value:p.id,child:Text(p.name,maxLines:2,overflow:TextOverflow.ellipsis))).toList(),
      onChanged:enabled ? (id) {if(id != null) onSelect(id);} : null,
    ),
  ]);
}
