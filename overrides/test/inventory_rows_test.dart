import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:flutter_test/flutter_test.dart';
import '../lib/inventory_rows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('StockPreview')..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for(final width in [360.0,564.0]) {
    testWidgets('numbered inventory with long names and colored quantity price total at $width', (tester) async {
      tester.view.physicalSize=Size(width,900);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final key=GlobalKey(); int quantity=12;
      Widget screen()=>RepaintBoundary(key:key,child:MaterialApp(theme:ThemeData(brightness:Brightness.dark,fontFamily:'StockPreview'),
        builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.3)),child:child!),
        home:Directionality(textDirection:TextDirection.rtl,child:Scaffold(appBar:AppBar(title:const Text('المخزون')),body:ListView(children:[
          InventoryProductCard(number:1,name:'حنفية غسالة كوبشة الحياة اسم المنتج كامل وطويل',quantity:quantity,unitPrice:25.50,
            actions:[IconButton(tooltip:'تعديل',onPressed:(){},icon:const Icon(Icons.edit)),IconButton(tooltip:'المخزون الرئيسي',onPressed:(){},icon:const Icon(Icons.warehouse)),IconButton(tooltip:'حذف المنتج',onPressed:(){},icon:const Icon(Icons.delete_forever))]),
          const InventoryProductCard(number:2,name:'جلبة نيكل الحياة 3 سم',quantity:0,unitPrice:74.80),
          const InventoryProductCard(number:3,name:'نبل نحاس طويل',quantity:-2,unitPrice:33),
        ])))));
      await tester.pumpWidget(screen());await tester.pumpAndSettle();
      expect(find.text('1'),findsOneWidget);expect(find.text('2'),findsOneWidget);expect(find.text('3'),findsOneWidget);
      expect(find.text('306.00'),findsOneWidget);expect(find.text('-66.00'),findsOneWidget);
      expect(tester.widget<Text>(find.text('12')).style!.color,InventoryProductCard.quantityColor);
      expect(tester.widget<Text>(find.text('25.50')).style!.color,InventoryProductCard.priceColor);
      expect(tester.widget<Text>(find.text('306.00')).style!.color,InventoryProductCard.totalColor);
      expect(tester.takeException(),isNull);
      final boundary=key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image=await boundary.toImage(pixelRatio:1.5);
        try {
          final png=await image.toByteData(format:ui.ImageByteFormat.png);
          await Directory('dist').create(recursive:true);
          await File('dist/VIB-INVENTORY-ROWS-${width.toInt()}.png').writeAsBytes(png!.buffer.asUint8List());
        } finally {image.dispose();}
      });
      quantity=10;await tester.pumpWidget(screen());await tester.pumpAndSettle();expect(find.text('255.00'),findsOneWidget);expect(find.text('306.00'),findsNothing);
    });
  }
  testWidgets('unknown stock does not publish a false zero total', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:InventoryProductCard(number:1,name:'صنف',quantity:null,unitPrice:20,quantityMessage:'تعذر التحميل'))));
    expect(find.text('تعذر التحميل'),findsOneWidget);expect(find.text('غير متاح'),findsOneWidget);expect(find.text('0.00'),findsNothing);
  });
}
