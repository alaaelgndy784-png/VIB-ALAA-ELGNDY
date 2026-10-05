part of 'main.dart';

// Shared VIB invoice, with a vector wordmark and angled settlement cards.
Future<Uint8List> createStyledA4InvoicePdf({
  required pw.Font font,
  required pw.ImageProvider logo,
  required bool isSale,
  required String number,
  required String barcode,
  required Map<String, dynamic> data,
  required List<Map<String, dynamic>> items,
  required String company,
  required String address,
  required String taxNumber,
  required String commercialRegister,
  required List<String> phones,
  required String footer,
  required num? supplierBalance,
  required bool liveSupplierBalance,
  String paper = 'a4',
}) async {
  final thermal = paper != 'a4', narrow = paper == '58';
  const black = PdfColor.fromInt(0xFF080808);
  const gold = PdfColor.fromInt(0xFFD4AF37);
  const pale = PdfColor.fromInt(0xFFFFFBF0);
  const line = PdfColor.fromInt(0xFFD8C59A);
  final pdf = pw.Document();
  String money(num value) => value.toStringAsFixed(2);
  double numValue(dynamic value) => (value as num?)?.toDouble() ?? 0;
  pw.Widget txt(
    String value, {
    double size = 9,
    bool bold = false,
    PdfColor color = PdfColors.black,
    pw.TextAlign align = pw.TextAlign.right,
  }) => pw.Text(
    value,
    textAlign: align,
    style: pw.TextStyle(
      fontSize: thermal ? (narrow ? size * .85 : size) : size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    ),
  );
  pw.Widget centered(
    String value, {
    double size = 9,
    bool bold = false,
    PdfColor color = PdfColors.black,
    bool numeric = false,
  }) {
    final child = txt(
      value,
      size: size,
      bold: bold,
      color: color,
      align: pw.TextAlign.center,
    );
    return numeric
        ? pw.Directionality(textDirection: pw.TextDirection.ltr, child: child)
        : child;
  }

  final title = isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات';
  final partyName = '${data[isSale ? 'customerName' : 'supplierName'] ?? ''}'
      .trim();
  final partyPhone = '${data[isSale ? 'customerPhone' : 'supplierPhone'] ?? ''}'
      .trim();
  final reference = '${data['invoiceNumber'] ?? ''}'.trim();
  final total = numValue(data['total']);
  final paid = (data['paid'] as num?)?.toDouble() ?? (isSale ? total : 0);
  final due = (data['due'] as num?)?.toDouble() ?? total - paid;
  final receiptPaid = numValue(data['receiptPaid']);
  final previousKey = isSale
      ? 'customerPreviousBalance'
      : 'supplierPreviousBalance';
  final previous = data[previousKey] as num?;
  // Saved total and balances remain authoritative. Discounts are already applied.
  final discount = items.fold<double>(0, (sum, item) {
    final base = item['basePrice'] as num?;
    if (!isSale || base == null || numValue(item['discountPercent']) <= 0)
      return sum;
    final difference = base.toDouble() - numValue(item['unitPrice']);
    return sum + (difference > 0 ? difference * numValue(item['quantity']) : 0);
  });
  final gross = total + discount;
  final percent = gross > 0 ? discount / gross * 100 : 0.0;
  final finalBalance = isSale
      ? data['customerBalanceAfter'] as num?
      : supplierBalance;
  final finalLabel = finalBalance == null
      ? 'باقي الفاتورة'
      : !isSale && liveSupplierBalance
      ? 'رصيد المورد الحالي'
      : 'الإجمالي المتبقي';
  final totals = <({String label, String value, bool highlight})>[
    (label: 'إجمالي الفاتورة', value: money(gross), highlight: false),
    (
      label: 'نسبة الخصم',
      value: '${percent.toStringAsFixed(2)}%',
      highlight: false,
    ),
    (label: 'قيمة الخصم', value: money(discount), highlight: false),
    (label: 'بعد الخصم', value: money(total), highlight: false),
    (
      label: 'الرصيد السابق',
      value: previous == null ? 'غير مسجل' : money(previous),
      highlight: false,
    ),
    (
      label: 'الإجمالي المستحق',
      value: previous == null ? 'غير مسجل' : money(previous + total),
      highlight: false,
    ),
    (label: 'المدفوع نقدًا', value: money(paid), highlight: false),
    (
      label: finalLabel,
      value: money(finalBalance ?? due - receiptPaid),
      highlight: true,
    ),
  ];
  pw.Widget calculationCard(
    ({String label, String value, bool highlight}) entry,
  ) {
    // The diagonal is 45 degrees: equal horizontal and vertical cut distances.
    const shape = '8,0 100,0 108,8 108,44 100,52 8,52 0,44 0,8';
    return pw.Expanded(
      child: pw.Stack(
        children: [
          pw.Positioned.fill(
            child: pw.SvgImage(
              svg:
                  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 52" preserveAspectRatio="none"><polygon points="$shape" fill="${entry.highlight ? '#080808' : '#fffbf0'}" stroke="#d4af37" stroke-width="1"/></svg>',
              fit: pw.BoxFit.fill,
            ),
          ),
          pw.Container(
            height: thermal ? 45 : 58,
            padding: pw.EdgeInsets.symmetric(
              horizontal: thermal ? 5 : 8,
              vertical: 7,
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                centered(
                  entry.label,
                  size: thermal ? 7 : 9,
                  bold: true,
                  color: entry.highlight ? gold : black,
                ),
                pw.SizedBox(height: 4),
                pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: centered(
                    entry.value,
                    size: thermal ? 11 : 15,
                    bold: true,
                    numeric: entry.value != 'غير مسجل',
                    color: entry.highlight ? gold : black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget summary() {
    final columns = thermal ? 2 : 4;
    return pw.Column(
      children: [
        for (var offset = 0; offset < totals.length; offset += columns)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Directionality(
              textDirection: pw.TextDirection.ltr,
              child: pw.Row(
                children: [
                  // Explicit reversal keeps the final amount at the physical left edge.
                  for (final entry
                      in totals.sublist(offset, offset + columns).reversed)
                    calculationCard(entry),
                ],
              ),
            ),
          ),
        if (receiptPaid > 0)
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: line)),
            child: pw.Column(
              children: [
                centered(
                  '${data['onlinePaymentEver'] == true ? 'محصّل بعد الفاتورة' : 'محصّل بسندات قبض'}: ${money(receiptPaid)} ج.م',
                  size: 8,
                ),
                centered(
                  'باقي هذه الفاتورة الآن: ${money(due - receiptPaid)} ج.م',
                  size: 8,
                ),
              ],
            ),
          ),
      ],
    );
  }

  pw.Widget wordmark() => pw.SizedBox(
    height: thermal ? 45 : 60,
    width: thermal ? 110 : 150,
    child: pw.Stack(
      alignment: pw.Alignment.center,
      children: [
        pw.Positioned.fill(
          child: pw.SvgImage(
            svg:
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 150 60"><path d="M30 14 C-8 18 -8 54 35 56 C6 42 9 29 30 14 M120 14 C158 18 158 54 115 56 C144 42 141 29 120 14" fill="#b58727"/><path d="M57 2 L65 10 L75 0 L85 10 L93 2 L89 16 L61 16 Z" fill="#f8df83"/></svg>',
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, left: 3),
          child: centered(
            'VIB',
            size: thermal ? 34 : 45,
            bold: true,
            color: const PdfColor.fromInt(0xFF815715),
            numeric: true,
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: centered(
            'VIB',
            size: thermal ? 34 : 45,
            bold: true,
            color: gold,
            numeric: true,
          ),
        ),
      ],
    ),
  );
  pw.Widget brand() => pw.Column(
    children: [
      wordmark(),
      centered(company, size: thermal ? 10 : 14, bold: true, color: gold),
      centered(
        'ALAA ELGNDY',
        size: thermal ? 8 : 10,
        bold: true,
        color: gold,
        numeric: true,
      ),
    ],
  );
  pw.Widget legal() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (taxNumber.isNotEmpty) ...[
        centered(
          'البطاقة الضريبية:',
          size: thermal ? 7 : 8,
          color: PdfColors.white,
        ),
        centered(
          taxNumber,
          size: thermal ? 8 : 9,
          color: PdfColors.white,
          numeric: true,
        ),
      ],
      if (commercialRegister.isNotEmpty) ...[
        pw.SizedBox(height: 5),
        centered(
          'السجل التجاري:',
          size: thermal ? 7 : 8,
          color: PdfColors.white,
        ),
        centered(
          commercialRegister,
          size: thermal ? 8 : 9,
          color: PdfColors.white,
          numeric: true,
        ),
      ],
    ],
  );
  pw.Widget contacts() => pw.Column(
    children: [
      for (final phone in phones)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: centered(
            phone,
            size: thermal ? 8 : 9,
            color: PdfColors.white,
            numeric: true,
          ),
        ),
    ],
  );
  pw.Widget masthead() => pw.Container(
    padding: pw.EdgeInsets.all(thermal ? 7 : 12),
    decoration: const pw.BoxDecoration(
      color: black,
      border: pw.Border(bottom: pw.BorderSide(color: gold, width: 3)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (thermal) ...[
          brand(),
          pw.SizedBox(height: 6),
          pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(child: contacts()),
                pw.SizedBox(width: 4),
                pw.Expanded(child: legal()),
              ],
            ),
          ),
        ] else
          pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(flex: 2, child: contacts()),
                pw.Expanded(flex: 4, child: brand()),
                pw.Expanded(flex: 2, child: legal()),
              ],
            ),
          ),
        if (address.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          centered(address, size: thermal ? 8 : 10, color: PdfColors.white),
        ],
      ],
    ),
  );
  pw.Widget detail(String label, String value, {bool numeric = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          color: pale,
          border: pw.Border.all(color: line, width: .5),
        ),
        child: pw.Row(
          children: [
            pw.Expanded(child: txt(label, size: thermal ? 8 : 9, bold: true)),
            pw.SizedBox(width: 5),
            pw.Flexible(
              flex: 2,
              child: numeric
                  ? pw.Directionality(
                      textDirection: pw.TextDirection.ltr,
                      child: txt(value, size: thermal ? 8 : 9),
                    )
                  : txt(value, size: thermal ? 8 : 9),
            ),
          ],
        ),
      );
  final table = pw.Table(
    columnWidths: {
      0: const pw.FlexColumnWidth(1.6),
      1: const pw.FlexColumnWidth(1.35),
      2: const pw.FlexColumnWidth(.8),
      3: const pw.FlexColumnWidth(4.5),
      4: const pw.FlexColumnWidth(.5),
    },
    border: pw.TableBorder.all(color: line, width: .5),
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: black),
        children: ['الإجمالي', 'السعر', 'العدد', 'الصنف', 'م']
            .map(
              (v) => pw.Padding(
                padding: pw.EdgeInsets.symmetric(
                  horizontal: thermal ? 1 : 4,
                  vertical: 7,
                ),
                child: centered(
                  v,
                  size: thermal ? 7 : 10,
                  bold: true,
                  color: gold,
                ),
              ),
            )
            .toList(),
      ),
      for (var i = 0; i < items.length; i++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isEven ? pale : PdfColors.white,
          ),
          children:
              [
                    money(
                      (items[i]['lineTotal'] as num?) ??
                          numValue(items[i]['quantity']) *
                              numValue(
                                items[i][isSale ? 'unitPrice' : 'unitCost'],
                              ),
                    ),
                    money(
                      numValue(items[i][isSale ? 'unitPrice' : 'unitCost']),
                    ),
                    '${items[i]['quantity'] ?? 0}',
                    '${items[i]['productName'] ?? ''}${numValue(items[i]['discountPercent']) > 0 ? '\nخصم ${items[i]['discountPercent']}%' : ''}',
                    '${i + 1}',
                  ]
                  .asMap()
                  .entries
                  .map(
                    (entry) => pw.Padding(
                      padding: pw.EdgeInsets.symmetric(
                        horizontal: thermal ? 2 : 5,
                        vertical: thermal ? 5 : 8,
                      ),
                      child: entry.key == 3
                          ? txt(entry.value, size: thermal ? 8 : 9)
                          : centered(
                              entry.value,
                              size: thermal ? 7 : 9,
                              numeric: true,
                            ),
                    ),
                  )
                  .toList(),
        ),
    ],
  );
  final content = <pw.Widget>[
    masthead(),
    pw.SizedBox(height: 9),
    pw.Center(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 6),
        decoration: pw.BoxDecoration(
          color: black,
          border: pw.Border.all(color: gold),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: centered(
          title,
          size: thermal ? 14 : 19,
          bold: true,
          color: gold,
        ),
      ),
    ),
    pw.SizedBox(height: 9),
    detail('رقم الفاتورة', number, numeric: true),
    detail('التاريخ', formatDate(data['createdAt']), numeric: true),
    detail(
      'نوع الفاتورة',
      data['status'] == 'returned'
          ? 'مرتجعة'
          : due > 0
          ? 'آجل'
          : 'نقدي',
    ),
    detail(
      isSale ? 'اسم العميل' : 'اسم المورد',
      partyName.isEmpty && isSale ? 'بيع نقدي' : partyName,
    ),
    if (partyPhone.isNotEmpty) detail('رقم الهاتف', partyPhone, numeric: true),
    if (!isSale && reference.isNotEmpty)
      detail('رقم فاتورة المورد', reference, numeric: true),
    pw.SizedBox(height: 9),
    table,
    pw.SizedBox(height: 9),
    summary(),
  ];
  if (thermal) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          (narrow ? 58 : 80) * PdfPageFormat.mm,
          double.infinity,
        ),
        margin: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        textDirection: pw.TextDirection.rtl,
        build: (_) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            ...content,
            pw.SizedBox(height: 8),
            pw.Divider(color: gold),
            centered(footer, size: 8),
          ],
        ),
      ),
    );
  } else {
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12 * PdfPageFormat.mm),
        maxPages: 100,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        textDirection: pw.TextDirection.rtl,
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Column(
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      txt(company, bold: true),
                      txt('$title — $number'),
                    ],
                  ),
                  pw.Divider(color: gold),
                ],
              ),
        footer: (context) => pw.Column(
          children: [
            pw.Container(height: 2, color: gold),
            pw.SizedBox(height: 5),
            centered(footer, size: 8),
            pw.SizedBox(height: 3),
            centered(
              'صفحة ${context.pageNumber} / ${context.pagesCount}',
              size: 7,
            ),
          ],
        ),
        build: (_) => content,
      ),
    );
  }
  return pdf.save();
}
