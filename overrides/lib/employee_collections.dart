part of 'main.dart';

class EmployeeCollections extends StatelessWidget {
  const EmployeeCollections({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
    stream:db.collection('sales').orderBy('createdAt',descending:true).snapshots(),
    builder:(context,salesSnapshot) {
      if(salesSnapshot.hasError)return const Center(child:Text('تعذر تحميل تحصيلات الموظفين'));
      if(!salesSnapshot.hasData)return const Center(child:CircularProgressIndicator());
      return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream:db.collection('users').snapshots(),
        builder:(context,userSnapshot) {
          if(userSnapshot.hasError)return const Center(child:Text('تعذر تحميل أسماء الموظفين'));
          if(!userSnapshot.hasData)return const Center(child:CircularProgressIndicator());
          final employeeIds={for(final user in userSnapshot.data!.docs)
            if(user.data()['role']=='employee'&&user.data()['active']==true)user.id};
          final names={for(final user in userSnapshot.data!.docs)user.id:'${user.data()['name']??''}'};
          final rows=salesSnapshot.data!.docs.where((sale){
            final data=sale.data();
            return visibleAfterReset(data)&&data['status']=='completed'&&employeeIds.contains('${data['employeeId']??''}')&&
              ((data['paid'] as num?)??0)>0;
          }).toList();
          final grouped=<String,List<QueryDocumentSnapshot<Map<String,dynamic>>>>{};
          for(final row in rows){grouped.putIfAbsent('${row.data()['employeeId']}',()=>[]).add(row);}
          final employees=grouped.keys.toList()..sort((a,b)=>(names[a]??'').compareTo(names[b]??''));
          final totals=<String,int>{for(final method in salePaymentMethodLabels.keys)method:0};
          for(final row in rows){
            final data=row.data(),paid=((data['paid'] as num?)??0).toDouble();
            final split=normalizeSalePaymentBreakdown(data['paymentBreakdown'],paid);
            for(final method in totals.keys)totals[method]=totals[method]!+(split[method]!*100).round();
          }
          final totalPaid=totals.values.fold<int>(0,(a,b)=>a+b);
          return Column(children:[
            Card(margin:const EdgeInsets.all(10),child:Padding(padding:const EdgeInsets.all(12),child:Column(
              crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                const Text('المبالغ المحصّلة حسب الموظف وطريقة الدفع',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
                const SizedBox(height:6),
                Text('إجمالي المحصّل: ${(totalPaid/100).toStringAsFixed(2)} ج.م • عدد الفواتير: ${rows.length}',
                  style:const TextStyle(fontWeight:FontWeight.bold)),
                for(final method in salePaymentMethodLabels.keys)
                  Text('${salePaymentMethodLabels[method]}: ${(totals[method]!/100).toStringAsFixed(2)} ج.م'),
              ]))),
            Expanded(child:employees.isEmpty?const Center(child:Text('لا توجد تحصيلات موظفين')):
              ListView.builder(itemCount:employees.length,itemBuilder:(context,index){
                final employeeId=employees[index],invoices=grouped[employeeId]!;
                final employeeTotals=<String,int>{for(final method in salePaymentMethodLabels.keys)method:0};
                for(final invoice in invoices){
                  final data=invoice.data(),split=normalizeSalePaymentBreakdown(data['paymentBreakdown'],((data['paid'] as num?)??0).toDouble());
                  for(final method in employeeTotals.keys)employeeTotals[method]=employeeTotals[method]!+(split[method]!*100).round();
                }
                final sum=employeeTotals.values.fold<int>(0,(a,b)=>a+b);
                return Card(child:ExpansionTile(
                  leading:const Icon(Icons.account_balance_wallet_outlined,color:gold),
                  title:Text(names[employeeId]?.isNotEmpty==true?names[employeeId]!: '${invoices.first.data()['employeeName']??'موظف'}',
                    style:const TextStyle(color:Colors.greenAccent,fontWeight:FontWeight.bold)),
                  subtitle:Text('${(sum/100).toStringAsFixed(2)} ج.م • ${invoices.length} فاتورة'),
                  children:[
                    Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:4),child:Wrap(spacing:12,runSpacing:4,children:[
                      for(final method in salePaymentMethodLabels.keys)
                        Text('${salePaymentMethodLabels[method]} ${(employeeTotals[method]!/100).toStringAsFixed(2)} ج.م'),
                    ])),
                    for(final invoice in invoices)
                      _EmployeeCollectionInvoiceRow(id:invoice.id,data:invoice.data()),
                  ],
                ));
              })),
          ]);
        },
      );
    },
  );
}

class _EmployeeCollectionInvoiceRow extends StatelessWidget {
  final String id;
  final Map<String,dynamic> data;
  const _EmployeeCollectionInvoiceRow({required this.id,required this.data});
  @override
  Widget build(BuildContext context){
    final split=normalizeSalePaymentBreakdown(data['paymentBreakdown'],((data['paid'] as num?)??0).toDouble());
    final methods=salePaymentMethodLabels.keys.where((key)=>(split[key]??0)>0)
      .map((key)=>'${salePaymentMethodLabels[key]} ${(split[key]!).toStringAsFixed(2)}').join(' • ');
    return ListTile(dense:true,title:Text('${data['customerName']??'بدون عميل'}',maxLines:1,overflow:TextOverflow.ellipsis),
      subtitle:Text('فاتورة ${invoiceDisplayNumber('sales',id,data)} • ${formatDate(data['createdAt'])}\n$methods'),
      isThreeLine:true,trailing:Text('${data['paid']??0} ج.م',style:const TextStyle(color:gold,fontWeight:FontWeight.bold)),
      onTap:()=>invoiceActions(context,'sales',id,data,canReturn:false));
  }
}
