part of 'main.dart';

// MicroPOS-style movement ledger: compact columns and all source details,
// without changing stock or invoice records.
String _vibMovementDay(dynamic raw) {
  if (raw is Timestamp) {
    return DateFormat('yyyy/MM/dd').format(
      tz.TZDateTime.from(raw.toDate(), tz.getLocation('Africa/Cairo')));
  }
  if (raw is DateTime) return DateFormat('yyyy/MM/dd').format(raw);
  return '-';
}

String _vibQty(dynamic value) {
  if (value is! num) return '0';
  return value == value.roundToDouble() ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

String _vibMovementDetails(Map<String,dynamic> row, String party) {
  final kind = (row['kind'] ?? '').toString();
  final details = <String>[movementName(kind)];
  if (party.trim().isNotEmpty) details.add(party.trim());
  if (kind == 'adjustment' && (row['reason'] ?? '').toString().trim().isNotEmpty &&
      !party.contains((row['reason'] ?? '').toString())) {
    details.add('السبب: ${row['reason']}');
  }
  final actor = (row['actorName'] ?? '').toString();
  if (actor.isNotEmpty && !party.contains('المستخدم:')) {
    details.add('المستخدم: $actor');
  }
  final ref = (row['referenceId'] ?? '').toString();
  if (ref.isNotEmpty && !party.contains('فاتورة:') && !party.contains('المرجع:')) {
    details.add('المرجع: $ref');
  }
  return details.join(' • ').replaceAll('\n', ' • ');
}

class VibCompactProductLedger extends StatelessWidget {
  final List<Map<String,dynamic>> rows;
  final Map<String,String> parties;
  final num opening;
  final Map<String,num> rowBalances;
  const VibCompactProductLedger({
    super.key, required this.rows, required this.parties, required this.opening,
    required this.rowBalances,
  });

  @override
  Widget build(BuildContext context) {
    const head = Color(0xFF344650), green = Color(0xFFD6F3DD),
      orange = Color(0xFFFFE0CF), balance = Color(0xFFE4EDF2);
    Widget textCell(String text, double width, {Color? fill, Color? color,
        bool bold = false, double size = 12}) => Container(
      width: width, alignment: Alignment.center, padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minHeight: 38),
      decoration: BoxDecoration(color: fill, border: Border.all(color: Colors.white24, width:.4)),
      child: Text(text, textAlign:TextAlign.center, maxLines: 2,
        overflow:TextOverflow.ellipsis, style:TextStyle(color:color ?? Colors.black87,
          fontSize:size,fontWeight:bold?FontWeight.bold:FontWeight.normal)),
    );
    Widget dataRow(String n,String date,String incoming,String outgoing,
        String qty,String description, {bool heading=false, Color? background}) {
      final fg=heading?Colors.white:Colors.black87;
      return Container(color:background ?? (heading?head:Colors.white),
        child: Row(textDirection:TextDirection.rtl,children:[
          textCell(n,34,fill:heading?head:null,color:fg,bold:heading),
          textCell(date,94,fill:heading?head:null,color:fg,bold:heading),
          textCell(incoming,64,fill:heading?head:green,color:heading?fg:Colors.black87,bold:heading),
          textCell(outgoing,64,fill:heading?head:orange,color:heading?fg:Colors.black87,bold:heading),
          textCell(qty,70,fill:heading?head:balance,color:heading?fg:Colors.black87,bold:true),
          Expanded(child:Container(
            alignment:Alignment.centerRight,
            constraints:const BoxConstraints(minHeight:38),
            padding:const EdgeInsets.symmetric(horizontal:6,vertical:4),
            child:Text(description,textAlign:TextAlign.right,maxLines:2,
              overflow:TextOverflow.ellipsis,style:TextStyle(
                fontWeight:heading?FontWeight.bold:FontWeight.normal,
                color:heading?Colors.white:Colors.black87,fontSize:heading?12:11)),
          )),
        ]));
    }
    final ledger = <num>[];
    num running=opening;
    for(final row in rows){
      running+=(row['quantity'] as num?)??0;
      ledger.add(rowBalances[(row['id'] ?? '').toString()] ?? running);
    }
    final totalIn=rows.fold<num>(0,(s,r){final q=(r['quantity'] as num?)??0;return s+(q>0?q:0);});
    final totalOut=rows.fold<num>(0,(s,r){final q=(r['quantity'] as num?)??0;return s+(q<0?-q:0);});
    return LayoutBuilder(builder:(context, constraints) =>
      SingleChildScrollView(
        scrollDirection:Axis.horizontal,
        child:SizedBox(width:constraints.maxWidth>790?constraints.maxWidth:790,
          child:Column(children:[
            dataRow('#','التاريخ','وارد','صادر','الرصيد','البيان',heading:true),
            dataRow('',rows.isEmpty?'':_vibMovementDay(rows.first['createdAt']),
              '','',_vibQty(opening),'رصيد أول المدة',background:const Color(0xFFE8F4FB)),
            Expanded(child:rows.isEmpty
              ? const Center(child:Text('لا توجد حركات في الفترة المختارة'))
              : ListView.builder(itemCount:rows.length,itemBuilder:(context,i){
                final row=rows[i], qty=(row['quantity'] as num?)??0;
                final details=_vibMovementDetails(row,parties['${row['id']}'] ?? '');
                return InkWell(
                  onTap:()=>showDialog<void>(context:context,builder:(c)=>AlertDialog(
                    title:Text('تفاصيل الحركة رقم ${i+1}'),
                    content:SingleChildScrollView(child:SelectableText(
                      'التاريخ: ${_vibMovementDay(row['createdAt'])}\n'
                      'وارد: ${qty>0?_vibQty(qty):'0'}\n'
                      'صادر: ${qty<0?_vibQty(-qty):'0'}\n'
                      'الرصيد: ${_vibQty(ledger[i])}\n'
                      '${details.replaceAll(' • ', '\n')}')),
                    actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق'))])),
                  child:dataRow('${i+1}',_vibMovementDay(row['createdAt']),
                    qty>0?_vibQty(qty):'',qty<0?_vibQty(-qty):'',
                    _vibQty(ledger[i]), details,
                    background:i.isEven?Colors.white:const Color(0xFFF5F8FB)),
                );
              })),
            dataRow('',rows.isEmpty?'':_vibMovementDay(rows.last['createdAt']),
              _vibQty(totalIn),_vibQty(totalOut),_vibQty(ledger.isEmpty?opening:ledger.last),
              'الإجمالي / رصيد آخر المدة',background:const Color(0xFFE8F4FB)),
          ])),
        ),
      ));
  }
}

Future<Uint8List> createVibClassicProductMovementPdf(
    String productName, String productCode, List<Map<String,dynamic>> movements,
    Map<String,String> parties, ProductPeriodTotals totals, pw.Font font,
    {DateTimeRange? range, required int currentQty}) async {
  final doc=pw.Document();
  final navy=PdfColor.fromInt(0xFF344650),green=PdfColor.fromInt(0xFFDDF4DC),
    orange=PdfColor.fromInt(0xFFFFE3D5),pale=PdfColor.fromInt(0xFFE7F1F7);
  final logo=pw.MemoryImage(
    (await rootBundle.load('assets/vip-logo.png')).buffer.asUint8List());
  pw.Widget cell(String value,{bool heading=false,PdfColor? fill,bool strong=false,
      pw.TextAlign align=pw.TextAlign.center,double size=8}) =>
    pw.Container(color:fill ?? (heading?navy:PdfColors.white),
      alignment:pw.Alignment.center,
      padding:const pw.EdgeInsets.symmetric(horizontal:3,vertical:5),
      child:pw.Directionality(textDirection:pw.TextDirection.rtl,child:pw.Text(value,
        textAlign:align,style:pw.TextStyle(font:font,fontSize:size,
          color:heading?PdfColors.white:PdfColors.black,
          fontWeight:heading||strong?pw.FontWeight.bold:pw.FontWeight.normal))));
  pw.TableRow tableRow(String number,String day,String incoming,String outgoing,
      String running,String description, {bool heading=false,bool summary=false})=>
      pw.TableRow(children:[
        cell(description,heading:heading,fill:heading?navy:summary?pale:null,
          align:pw.TextAlign.right,strong:summary),
        cell(running,heading:heading,fill:heading?navy:pale,strong:summary),
        cell(outgoing,heading:heading,fill:heading?navy:orange,strong:summary),
        cell(incoming,heading:heading,fill:heading?navy:green,strong:summary),
        cell(day,heading:heading,fill:summary?pale:null,strong:summary),
        cell(number,heading:heading,fill:summary?pale:null,strong:summary),
      ]);
  final entries=<pw.TableRow>[
    tableRow('#','التاريخ','وارد','صادر','الرصيد','البيان',heading:true),
    tableRow('',range==null?'':DateFormat('yyyy/MM/dd').format(range.start),
      '','',_vibQty(totals.opening),'رصيد أول المدة',summary:true),
  ];
  num running=totals.opening;
  for(var i=0;i<movements.length;i++){
    final row=movements[i];
    final qty=(row['quantity'] as num?)??0;
    running+=qty;
    entries.add(tableRow('${i+1}',_vibMovementDay(row['createdAt']),
      qty>0?_vibQty(qty):'',qty<0?_vibQty(-qty):'',
      _vibQty(running),_vibMovementDetails(row,parties['${row['id']}']??'')));
  }
  if(movements.isEmpty)entries.add(pw.TableRow(children:[
    cell('لا توجد حركات في الفترة المختارة'),cell(''),cell(''),cell(''),cell(''),cell(''),
  ]));
  entries.add(tableRow('',range==null?'':DateFormat('yyyy/MM/dd').format(range.end),
    _vibQty(totals.incoming),_vibQty(totals.outgoing),_vibQty(totals.closing),
    'الإجمالي / رصيد آخر المدة',summary:true));
  final from=range==null?'بداية التسجيل':DateFormat('yyyy/MM/dd').format(range.start);
  final to=range==null?'حتى اليوم':DateFormat('yyyy/MM/dd').format(range.end);
  doc.addPage(pw.MultiPage(
    pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.fromLTRB(22,24,22,30),
    footer:(ctx)=>pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[
      pw.Text('VIB ALAA ELGNDY',style:pw.TextStyle(font:font,fontSize:8)),
      pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',style:pw.TextStyle(font:font,fontSize:8)),
    ]),
    build:(ctx)=>[
      pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
          pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
            pw.Text(DateFormat('yyyy/MM/dd').format(DateTime.now()),
              style:pw.TextStyle(font:font,fontSize:9)),
            pw.Text(DateFormat('HH:mm').format(DateTime.now()),
              style:pw.TextStyle(font:font,fontSize:9)),
          ]),
          pw.Image(logo,width:45,height:45),
          pw.Directionality(textDirection:pw.TextDirection.rtl,
            child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.end,children:[
              pw.Text('VIB ALAA ELGNDY',style:pw.TextStyle(font:font,fontSize:11)),
              pw.Text('للأدوات الصحية والتجارة والتوزيع',style:pw.TextStyle(font:font,fontSize:9)),
              pw.Text('01211500003 • 01013631323',style:pw.TextStyle(font:font,fontSize:9)),
            ])),
        ]),
      pw.SizedBox(height:12),
      pw.Directionality(textDirection:pw.TextDirection.rtl,child:pw.Column(
        crossAxisAlignment:pw.CrossAxisAlignment.center,children:[
          pw.Text('تقرير حركة منتج',style:pw.TextStyle(font:font,fontSize:16,fontWeight:pw.FontWeight.bold)),
          pw.SizedBox(height:6),
          pw.Text('للفترة من $from إلى $to',style:pw.TextStyle(font:font,fontSize:10)),
          pw.SizedBox(height:5),
          pw.Text('المنتج: $productName     رقم المنتج: $productCode',
            style:pw.TextStyle(font:font,fontSize:10),textAlign:pw.TextAlign.center),
        ])),
      pw.SizedBox(height:10),
      pw.Table(
        border:pw.TableBorder.all(color:PdfColors.grey700,width:0.5),
        columnWidths:{
          0:const pw.FlexColumnWidth(4.2),
          1:const pw.FixedColumnWidth(53),
          2:const pw.FixedColumnWidth(48),
          3:const pw.FixedColumnWidth(48),
          4:const pw.FixedColumnWidth(76),
          5:const pw.FixedColumnWidth(22),
        },
        children:entries,
      ),
      pw.SizedBox(height:13),
      pw.Align(alignment:pw.Alignment.centerRight,child:pw.SizedBox(width:310,
        child:pw.Table(border:pw.TableBorder.all(color:PdfColors.grey600,width:0.5),
          columnWidths:{0:const pw.FlexColumnWidth(2),1:const pw.FlexColumnWidth(1)},
          children:[
            for(final v in <(String,String)>[
              ('رصيد أول المدة',_vibQty(totals.opening)),
              ('إجمالي الوارد',_vibQty(totals.incoming)),
              ('إجمالي الصادر',_vibQty(totals.outgoing)),
              ('رصيد آخر المدة',_vibQty(totals.closing)),
              ('عدد الحركات','${movements.length}'),
              ('الكمية الحالية في المخزن','${currentQty}'),
            ])pw.TableRow(children:[
              cell(v.$1,align:pw.TextAlign.right,fill:PdfColors.grey200,size:8),
              cell(v.$2,strong:true,size:9),
            ]),
          ]))),
      if(totals.gap!=0)pw.Directionality(textDirection:pw.TextDirection.rtl,
        child:pw.Text('تنبيه: فرق الجرد عن حركة المخزون المسجلة: ${_vibQty(totals.gap)}',
          style:pw.TextStyle(font:font,color:PdfColors.red,fontSize:9))),
    ],
  ));
  return doc.save();
}
