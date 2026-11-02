part of 'main.dart';

// A4 and thermal payment reports must use exactly the ReceiptDayReport
// already filtered and re-confirmed by the screen's print action.
Future<Uint8List> createVibCustomerPaymentDetailPdf(
  DateTime from, ReceiptDayReport report, pw.Font font,
  {required bool owner, required bool thermal, DateTime? to,
   required bool suppliers}) async {
  initializeChequeTimeZones();
  final pdf = pw.Document();
  final logoData = await rootBundle.load('assets/vip-logo.png');
  final logo = pw.MemoryImage(logoData.buffer.asUint8List(
      logoData.offsetInBytes, logoData.lengthInBytes));
  final parties = suppliers ? 'الموردين' : 'العملاء';
  final single = report.customers.length == 1 ? report.customers.single : null;
  final title = suppliers ? 'تقرير حركة سداد المورد' : 'تقرير حركة سداد العميل';
  final reportTitle = single == null ? 'تقرير حركة سداد ' + parties : title;
  final period = 'من ' + DateFormat('dd/MM/yyyy').format(from) +
      ' إلى ' + DateFormat('dd/MM/yyyy').format(to ?? from);
  final entries = <Map<String, dynamic>>[
    for (final customer in report.customers)
      for (final receipt in customer.receipts) receipt,
  ];
  entries.sort((a, b) {
    final left = receiptEffectiveTimestamp(a)?.millisecondsSinceEpoch ?? 0;
    final right = receiptEffectiveTimestamp(b)?.millisecondsSinceEpoch ?? 0;
    return left.compareTo(right);
  });
  String amount(Map<String, dynamic> row) =>
      receiptReportMoney(((row['amount'] as num) * 100).round());
  String details(Map<String, dynamic> row) {
    final method = (row['paymentMethod'] ?? '').toString().trim();
    final note = (row['note'] ?? '').toString().trim();
    if (method.isEmpty) return note.isEmpty ? '-' : note;
    if (note.isEmpty || note == method) return method;
    return method + ' - ' + note;
  }
  String issued(Map<String, dynamic> row) =>
      receiptReportStamp(row, to ?? from);
  final displayCount = report.receiptCount.toString() +
      (suppliers ? ' سند صرف' : ' سند قبض');
  final total = receiptReportMoney(report.totalCents);

  if (thermal) {
    // Size thermal roll by actual rows rather than reserving excessive white paper.
    // Reserve measured room for the final total and normal bottom cut margin,
    // without the long blank feed of the previous implementation.
    final estimatedHeight = 75 + entries.fold<double>(0, (sum, row) =>
      sum + (single == null ? 19 : 14) + (details(row).length > 30 ? 6 : 0));
    final rollHeight = estimatedHeight.clamp(95, 4100).toDouble();
    pw.Widget line(String value, {bool strong = false, double size = 9}) =>
      pw.Text(value, textAlign: pw.TextAlign.right,
        style: pw.TextStyle(font: font, fontSize: size,
          fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal));
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat(80 * PdfPageFormat.mm,
        rollHeight * PdfPageFormat.mm, marginAll: 3 * PdfPageFormat.mm),
      theme: pw.ThemeData.withFont(base: font, bold: font),
      textDirection: pw.TextDirection.rtl,
      build: (_) => pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: pw.Image(logo, width: 38, height: 38)),
          pw.SizedBox(height: 4),
          pw.Center(child: line('VIB للتجارة والتوزيع', strong: true, size: 12)),
          pw.Center(child: line(reportTitle, strong: true, size: 11)),
          if (single != null) line((suppliers ? 'المورد: ' : 'العميل: ') + single.name,
              strong: true, size: 10),
          line(period),
          line(displayCount), pw.Divider(),
          for (var i = 0; i < entries.length; i++) ...[
            line((i + 1).toString() + ' - ' + issued(entries[i]) +
              '     ' + amount(entries[i]), strong: true),
            line('رقم السند: ' + receiptDisplayNumber(entries[i])),
            if (single == null) line((suppliers ? 'المورد: ' : 'العميل: ') +
                (entries[i]['customerName'] ?? 'غير مسجل').toString()),
            line('البيان: ' + details(entries[i])),
            pw.Divider(height: 7),
          ],
          line('الإجمالي: ' + total, strong: true, size: 12),
        ],
      ),
    ));
    return pdf.save();
  }

  const navy = PdfColor.fromInt(0xFF17283D);
  const pale = PdfColor.fromInt(0xFFF3F5F8);
  const grid = PdfColor.fromInt(0xFFADB7C4);
  pw.Widget cell(String value, {bool head = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: pw.Text(value, textAlign: pw.TextAlign.center,
      style: pw.TextStyle(font: font, fontSize: head ? 9.3 : 9.2,
        fontWeight: head ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: head ? PdfColors.white : PdfColors.black)),
  );
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    maxPages: 1000,
    margin: const pw.EdgeInsets.fromLTRB(22, 24, 22, 26),
    theme: pw.ThemeData.withFont(base: font, bold: font),
    textDirection: pw.TextDirection.rtl,
    footer: (ctx) => pw.Center(child: pw.Text(
      'صفحة ' + ctx.pageNumber.toString() + ' من ' +
        ctx.pagesCount.toString(), style: pw.TextStyle(font: font, fontSize: 9))),
    build: (_) => [
      pw.Center(child: pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            pw.Text('تاريخ الطباعة: ' +
              DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
              style: pw.TextStyle(font: font, fontSize: 9)),
            pw.Image(logo, width: 48, height: 48),
            pw.Text('VIB للتجارة والتوزيع', style: pw.TextStyle(font: font,
              fontSize: 14, color: navy, fontWeight: pw.FontWeight.bold)),
          ]),
        pw.SizedBox(height: 9),
        pw.SizedBox(height: 5),
        pw.Text(reportTitle, style: pw.TextStyle(font: font,
          fontSize: 16, fontWeight: pw.FontWeight.bold)),
        if (single != null) ...[
          pw.SizedBox(height: 5),
          pw.Text((suppliers ? 'المورد: ' : 'العميل: ') + single.name,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: font, fontSize: 14,
              fontWeight: pw.FontWeight.bold)),
        ],
        pw.SizedBox(height: 5),
        pw.Text(period, style: pw.TextStyle(font: font, fontSize: 11)),
      ])),
      pw.SizedBox(height: 12),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: pw.BoxDecoration(color: pale, border: pw.Border.all(color: grid)),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(displayCount, style: pw.TextStyle(font: font, fontSize: 12)),
            pw.Text('إجمالي السداد: ' + total,
              style: pw.TextStyle(font: font, fontSize: 12,
                fontWeight: pw.FontWeight.bold)),
          ]),
      ),
      pw.SizedBox(height: 13),
      pw.Table(
        border: pw.TableBorder.all(color: grid, width: .5),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.12),
          1: const pw.FlexColumnWidth(2.4),
          2: const pw.FlexColumnWidth(1.45),
          3: const pw.FlexColumnWidth(1.65),
          4: const pw.FlexColumnWidth(1.58),
          5: const pw.FlexColumnWidth(.4),
        },
        children: [
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: navy),
            children: [
              cell('المبلغ', head: true),
              cell('بيان الدفعة', head: true),
              cell(suppliers ? 'المورد' : 'العميل', head: true),
              cell('رقم السند', head: true),
              cell('التاريخ والوقت', head: true),
              cell('م', head: true),
            ],
          ),
          for (var i = 0; i < entries.length; i++)
            pw.TableRow(
              decoration: i.isOdd ? const pw.BoxDecoration(color: pale) : null,
              children: [
                cell(amount(entries[i])),
                cell(details(entries[i])),
                cell((entries[i]['customerName'] ?? 'غير مسجل').toString()),
                cell(receiptDisplayNumber(entries[i])),
                cell(issued(entries[i])),
                cell((i + 1).toString()),
              ],
            ),
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Container(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text('الإجمالي النهائي: ' + total, style: pw.TextStyle(
          font: font, fontSize: 15, color: PdfColors.red700,
          fontWeight: pw.FontWeight.bold)),
      ),
    ],
  ));
  return pdf.save();
}
