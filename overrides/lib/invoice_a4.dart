part of 'main.dart';

// Shared VIP black/gold invoice layout for A4 and thermal PDF exports.
Future<Uint8List> createStyledA4InvoicePdf({
  required pw.Font font, required pw.ImageProvider logo,
  required bool isSale, required String number, required String barcode,
  required Map<String, dynamic> data, required List<Map<String, dynamic>> items,
  required String company, required String address, required String taxNumber,
  required String commercialRegister, required List<String> phones,
  required String footer, required num? supplierBalance,
  required bool liveSupplierBalance,String paper='a4',
}) async {
  final thermal=paper!='a4';
  final narrow=paper=='58';
  const navy = PdfColor.fromInt(0xFF080808);
  const gold = PdfColor.fromInt(0xFFD4AF37);
  const pale = PdfColor.fromInt(0xFFFFFBF0);
  const line = PdfColor.fromInt(0xFFD8C59A);
  final pdf = pw.Document();
  String money(dynamic value) => ((value as num?)?.toDouble() ?? 0).toStringAsFixed(2);
  pw.Widget txt(String value, {double size = 9, bool bold = false,
    PdfColor color = PdfColors.black, pw.TextAlign align = pw.TextAlign.right}) =>
    pw.Text(value, textAlign: align, style: pw.TextStyle(fontSize:thermal ? (narrow ? size*.65 : size*.78) : size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color));
  pw.Widget ltr(String value, {double size = 9, bool bold = false, PdfColor color = PdfColors.black}) =>
    pw.Directionality(textDirection: pw.TextDirection.ltr,
      child: txt(value, size: size, bold: bold, color: color, align: pw.TextAlign.left));
  pw.Widget info(String label, String value, {bool numeric = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Row(children: [
      pw.Expanded(child: txt(label, color: navy)), pw.SizedBox(width: 8),
      pw.Flexible(flex: 2, child: numeric ? ltr(value) : txt(value, bold: true)),
    ]));
  pw.Widget card(String title, List<pw.Widget> children) => pw.Container(
    padding: pw.EdgeInsets.all(thermal ? 5 : 10), decoration: pw.BoxDecoration(
      border: pw.Border.all(color: gold, width: .6), borderRadius: pw.BorderRadius.circular(5)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      txt(title, size: 11, bold: true, color: navy), pw.Divider(color: line, thickness: .5), ...children,
    ]));
  final title = isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات';
  final partyName = '${data[isSale ? 'customerName' : 'supplierName'] ?? ''}'.trim();
  final partyPhone = '${data[isSale ? 'customerPhone' : 'supplierPhone'] ?? ''}'.trim();
  final reference = '${data['invoiceNumber'] ?? ''}'.trim();
  final total = (data['total'] as num?)?.toDouble() ?? 0;
  final paid = (data['paid'] as num?)?.toDouble() ?? (isSale ? total : 0);
  final due = (data['due'] as num?)?.toDouble() ?? total - paid;
  final receiptPaid = (data['receiptPaid'] as num?)?.toDouble() ?? 0;
  final previousKey = isSale ? 'customerPreviousBalance' : 'supplierPreviousBalance';
  final summary = <pw.Widget>[];
  void amount(String label, dynamic value, {bool highlight = false}) {
    summary.add(pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: pw.BoxDecoration(color: highlight ? gold : pale,
        border: pw.Border(bottom: pw.BorderSide(color: line, width: .4))),
      child: pw.Row(children: [pw.Expanded(child: txt(label, bold: highlight, color: navy)),
        pw.SizedBox(width: 6), ltr(money(value), size: highlight ? 11 : 9, bold: highlight, color: navy),
        pw.SizedBox(width: 4), txt('ج.م', size: 8, color: navy)])));
  }
  if (data.containsKey(previousKey)) amount('الرصيد السابق', data[previousKey]);
  amount('إجمالي الفاتورة', total);
  if (data.containsKey(previousKey)) amount('الإجمالي المستحق', (data[previousKey] as num).toDouble() + total);
  amount('المدفوع نقدًا', paid);
  if (receiptPaid > 0) amount(data['onlinePaymentEver'] == true ? 'محصّل بعد الفاتورة' : 'محصّل بسندات قبض', receiptPaid);
  amount('باقي هذه الفاتورة', due - receiptPaid);
  if (isSale && data.containsKey('customerBalanceAfter')) {
    amount('رصيد العميل بعد الفاتورة', data['customerBalanceAfter'], highlight: true);
  } else if (!isSale && supplierBalance != null) {
    amount(liveSupplierBalance ? 'رصيد المورد الحالي' : 'رصيد المورد بعد الفاتورة', supplierBalance, highlight: true);
  } else if (!isSale) {
    summary.add(pw.Padding(padding: const pw.EdgeInsets.all(8), child: txt('رصيد المورد غير متاح', bold: true)));
  }
  final table = pw.Table(columnWidths: {0: const pw.FlexColumnWidth(1.5),
    1: const pw.FlexColumnWidth(1.2), 2: const pw.FlexColumnWidth(.8),
    3: const pw.FlexColumnWidth(4.5), 4:pw.FlexColumnWidth(thermal ? .8 : .45)},
    border: pw.TableBorder.all(color: line, width: .5), children: [
      pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: navy),
        children: ['الإجمالي', 'السعر', 'العدد', 'الصنف', 'م'].map((value) =>
          pw.Padding(padding: pw.EdgeInsets.symmetric(horizontal:thermal ? 2 : 5,vertical:thermal ? 5 : 9),
            child: txt(value, bold: true, color: gold, align: pw.TextAlign.center))).toList()),
      for (var i = 0; i < items.length; i++) pw.TableRow(
        decoration: pw.BoxDecoration(color: i.isEven ? pale : PdfColors.white), children: [
          money(items[i]['lineTotal'] ?? ((items[i]['quantity'] as num?) ?? 0) * ((items[i][isSale ? 'unitPrice' : 'unitCost'] as num?) ?? 0)),
          money(items[i][isSale ? 'unitPrice' : 'unitCost']), '${items[i]['quantity'] ?? 0}',
          '${items[i]['productName'] ?? ''}${((items[i]['discountPercent'] as num?) ?? 0)>0 ? '\nخصم ${items[i]['discountPercent']}%' : ''}', '${i + 1}',
        ].asMap().entries.map((entry) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(horizontal:thermal ? 2 : 5,vertical:thermal ? 5 : 8),
          child: txt(entry.value, align: entry.key == 3 ? pw.TextAlign.right : pw.TextAlign.center))).toList()),
    ]);
  pw.Widget masthead() => pw.Container(padding: pw.EdgeInsets.all(thermal ? 7 : 12),
    decoration: const pw.BoxDecoration(color: navy,
      border:pw.Border(top:pw.BorderSide(color:PdfColor.fromInt(0xFFFFE8A0),width:2),bottom:pw.BorderSide(color:gold,width:3))),
    child:thermal ? pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
      pw.Center(child:pw.Image(logo,width:52,height:52)),pw.SizedBox(height:5),
      txt(company,size:16,bold:true,color:gold,align:pw.TextAlign.center),
      pw.Center(child:ltr('ALAAELGNDY',size:11,color:gold)),
      if(address.isNotEmpty)txt(address,size:8,color:PdfColors.white,align:pw.TextAlign.center),
      for(final phone in phones)pw.Center(child:ltr(phone,size:8,color:PdfColors.white)),
      if(taxNumber.isNotEmpty)pw.Row(children:[pw.Expanded(child:txt('البطاقة الضريبية:',size:7,color:PdfColors.white)),pw.Flexible(child:ltr(taxNumber,size:7,color:PdfColors.white))]),
      if(commercialRegister.isNotEmpty)pw.Row(children:[pw.Expanded(child:txt('السجل التجاري:',size:7,color:PdfColors.white)),pw.Flexible(child:ltr(commercialRegister,size:7,color:PdfColors.white))]),
    ]) : pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      pw.Expanded(flex: 3, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        txt(company, size: 16, bold: true, color: gold), pw.SizedBox(height: 4),
        ltr('ALAAELGNDY', size: 9, color: gold),
        if (address.isNotEmpty) ...[pw.SizedBox(height: 4), txt(address, size: 8, color: PdfColors.white)],
      ])), pw.SizedBox(width: 10),
      pw.Expanded(flex: 2, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        for (final phone in phones) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child: ltr(phone, size: 8, color: PdfColors.white)),
        if (taxNumber.isNotEmpty) pw.Row(children: [txt('البطاقة الضريبية: ', size: 7, color: PdfColors.white),
          pw.Flexible(child: ltr(taxNumber, size: 7, color: PdfColors.white))]),
        if (commercialRegister.isNotEmpty) pw.Row(children: [txt('السجل التجاري: ', size: 7, color: PdfColors.white),
          pw.Flexible(child: ltr(commercialRegister, size: 7, color: PdfColors.white))]),
      ])), pw.SizedBox(width: 10),
      pw.Container(width: 42, height: 42, color: navy, padding: const pw.EdgeInsets.all(2),
        child: pw.Image(logo, fit: pw.BoxFit.contain)),
    ]));
  pw.Widget signature(String label) => pw.Expanded(child: pw.Container(
    padding: pw.EdgeInsets.all(thermal ? 5 : 10), decoration: pw.BoxDecoration(color: pale,
      border: pw.Border.all(color: line, width: .5), borderRadius: pw.BorderRadius.circular(4)),
    child: pw.Column(children: [txt(label, bold: true, color: navy, align: pw.TextAlign.center),
      pw.SizedBox(height: 16), txt('................................', color: PdfColors.grey600, align: pw.TextAlign.center)])));
  final content=<pw.Widget>[masthead(), pw.SizedBox(height: 12),
      pw.Center(child: pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 26, vertical: 7),
        decoration: pw.BoxDecoration(color:navy,border: pw.Border.all(color: gold, width: .8), borderRadius: pw.BorderRadius.circular(5)),
        child: txt(title, size: 18, bold: true, color: gold, align: pw.TextAlign.center))),
      pw.SizedBox(height: 12),
      (thermal ? (List<pw.Widget> children)=>pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:children) : (List<pw.Widget> children)=>pw.Row(crossAxisAlignment:pw.CrossAxisAlignment.start,children:children))([
        (thermal ? (pw.Widget child)=>child : (pw.Widget child)=>pw.Expanded(child:child))(card(isSale ? 'بيانات العميل' : 'بيانات المورد', [
          info(isSale ? 'اسم العميل' : 'اسم المورد', partyName.isEmpty && isSale ? 'بيع نقدي' : partyName),
          if (partyPhone.isNotEmpty) info('رقم الهاتف', partyPhone, numeric: true),
          if (!isSale && reference.isNotEmpty) info('رقم فاتورة المورد', reference, numeric: true),
        ])), pw.SizedBox(width:thermal ? 0 : 12,height:thermal ? 6 : 0),
        (thermal ? (pw.Widget child)=>child : (pw.Widget child)=>pw.Expanded(child:child))(card('بيانات الفاتورة', [
          info('رقم الفاتورة', number, numeric: true), info('التاريخ', formatDate(data['createdAt'])),
          if (barcode.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: barcode,
              width:thermal ? 130 : 180,height:thermal ? 32 : 40, drawText: true, textStyle: const pw.TextStyle(fontSize: 8)))),
        ])),
      ]), pw.SizedBox(height: 12), table, pw.SizedBox(height: 12),
      (thermal ? (List<pw.Widget> children)=>pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:children) : (List<pw.Widget> children)=>pw.Row(crossAxisAlignment:pw.CrossAxisAlignment.start,children:children))([
        (thermal ? (pw.Widget child)=>child : (pw.Widget child)=>pw.Expanded(flex:2,child:child))(card('ملاحظات', [
          if ('${data['note'] ?? ''}'.trim().isNotEmpty) txt('${data['note']}'),
          if (data['status'] == 'returned') txt('فاتورة مرتجعة', bold: true, color: PdfColors.red),
          pw.SizedBox(height:thermal ? 8 : 40), txt('........................................................', color: PdfColors.grey500),
        ])), pw.SizedBox(width:thermal ? 0 : 12,height:thermal ? 6 : 0),
        (thermal ? (pw.Widget child)=>child : (pw.Widget child)=>pw.Expanded(flex:3,child:child))(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: summary)),
      ]), pw.SizedBox(height: 12),
      pw.Row(children: [signature(isSale ? 'توقيع العميل / المستلم' : 'توقيع المورد'),
        pw.SizedBox(width:thermal ? 0 : 12,height:thermal ? 6 : 0), signature(isSale ? 'توقيع الموظف' : 'توقيع المستلم')]),
  ];
  if(thermal) {
    pdf.addPage(pw.Page(pageFormat:PdfPageFormat(narrow ? 58*PdfPageFormat.mm : 80*PdfPageFormat.mm,double.infinity),
      margin:const pw.EdgeInsets.all(4*PdfPageFormat.mm),theme:pw.ThemeData.withFont(base:font,bold:font),textDirection:pw.TextDirection.rtl,
      build:(_)=>pw.Column(mainAxisSize:pw.MainAxisSize.min,crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[...content,pw.SizedBox(height:8),pw.Divider(color:gold),txt(footer,size:8,align:pw.TextAlign.center)])));
  } else {
  pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(12 * PdfPageFormat.mm), maxPages: 100,
    theme: pw.ThemeData.withFont(base: font, bold: font), textDirection: pw.TextDirection.rtl,
    header: (context) => context.pageNumber == 1 ? pw.SizedBox() : pw.Column(children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [txt(company, bold: true, color: navy), txt('$title — $number', color: navy)]),
      pw.Divider(color: gold),
    ]),
    footer: (context) => pw.Column(children: [
      pw.Container(height: 2, color: gold), pw.SizedBox(height: 5),
      txt(footer, size: 8, color: navy, align: pw.TextAlign.center), pw.SizedBox(height: 3),
      txt('صفحة ${context.pageNumber} / ${context.pagesCount}', size: 7, color: navy, align: pw.TextAlign.center),
    ]),
    build:(_)=>content));
  }
  return pdf.save();
}
