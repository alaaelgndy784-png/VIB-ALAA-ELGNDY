Warning: truncated output (original token count: 96086)
Total output lines: 5904

import 'invoice_serial_core.dart';
import 'pending_sale_data.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart' show AudioPlayer, DeviceFileSource;
import 'dart:convert';
import 'dart:io';
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' show DateFormat;
import 'package:local_auth/local_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

import 'product_import_data.dart';
import 'inventory_price_data.dart';
import 'inventory_rows.dart';

part 'cheques.dart';
part 'chat_alerts.dart';

part 'invoice_editor.dart';
part 'pending_sales.dart';
part 'product_import.dart';
part 'inventory_tools.dart';
part 'online_payments.dart';
part 'invoice_history.dart';
part 'invoice_serials.dart';
part 'invoice_a4.dart';
part 'invoice_parties.dart';
part 'business_reports.dart';
part 'invoice_lookup.dart';
part 'account_statements.dart';
part 'staff_purchases.dart';
part 'voucher_cancellations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeChequeTimeZones();
  runApp(const VibBootstrap());
}

const _vibApiKey = 'AIzaSyBDjNjPOhmTt0SbYUfCTQM8IteDCBxGfWk';
const _vibProjectId = 'vib-sales';
const _vibSenderId = '200962643703';
const _vibStorageBucket = 'vib-sales.firebasestorage.app';
const _managerFirebaseAppId = '1:200962643703:android:04784682cd1d95b22c65f2';
const _staffFirebaseAppId = '1:200962643703:android:fd5ac8ff4a1fae7c2c65f2';

bool staffApp = false;
final saleCostVisible = ValueNotifier<bool>(false);
final salePriceEditable = ValueNotifier<bool>(false);
Future<FirebaseOptions> _firebaseOptionsForThisApp() async {
  final packageName = (await PackageInfo.fromPlatform()).packageName;
  staffApp = packageName == 'com.alaa.vibsales.staffscan';
  final appId = packageName == 'com.alaa.vibsales.staffscan'
      ? _staffFirebaseAppId
      : _managerFirebaseAppId;
  return FirebaseOptions(
    apiKey: _vibApiKey,
    appId: appId,
    messagingSenderId: _vibSenderId,
    projectId: _vibProjectId,
    storageBucket: _vibStorageBucket,
  );
}

Future<FirebaseApp> _initializeVibFirebase() async {
  final options = await _firebaseOptionsForThisApp();
  final app = await Firebase.initializeApp(options: options);
  // Keep Firestore's Android cache enabled so previously loaded business data
  // remains available for browsing while the device is offline.
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  return app;
}

class VibBootstrap extends StatefulWidget {
  const VibBootstrap({super.key});
  @override State<VibBootstrap> createState() => _VibBootstrapState();
}

class _VibBootstrapState extends State<VibBootstrap> {
  late Future<FirebaseApp> initialization;
  @override void initState() { super.initState(); initialization = _initializeVibFirebase(); }
  @override Widget build(BuildContext context) => FutureBuilder<FirebaseApp>(future: initialization, builder: (context, snapshot) {
    if (snapshot.hasError) return MaterialApp(debugShowCheckedModeBanner: false, home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(backgroundColor: const Color(0xFF111111), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off, color: Color(0xFFD6AC55), size: 64), const SizedBox(height: 16), const Text('تعذر الاتصال بخدمة VIB', style: TextStyle(color: Colors.white, fontSize: 22)), const SizedBox(height: 12), FilledButton(onPressed: () => setState(() => initialization = _initializeVibFirebase()), child: const Text('إعادة المحاولة')),
    ]))))));
    if (snapshot.connectionState == ConnectionState.done) return const VibApp();
    return const MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(backgroundColor: Color(0xFF111111), body: Center(child: CircularProgressIndicator(color: Color(0xFFD6AC55)))));
  });
}

const gold = Color(0xFFD6AC55);
const vibBlue = Color(0xFF64B5F6);
const vibNeon = Color(0xFFB2FF59);
const vibRed = Color(0xFFFF6B6B);
final db = FirebaseFirestore.instance;
Timestamp? activeResetAt;

bool visibleAfterReset(Map<String, dynamic> data) {
  final resetAt = activeResetAt;
  if (resetAt == null) return true;
  final createdAt = data['createdAt'];
  if (createdAt is! Timestamp) return false;
  return createdAt.compareTo(resetAt) >= 0;
}

bool isTemporaryFirestoreOffline(Object error) => error is FirebaseException &&
    (error.code=='unavailable'||error.code=='deadline-exceeded'||error.code=='network-request-failed');

class VibApp extends StatelessWidget {
  const VibApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'VIB المبيعات',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xFF111111),
      colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF171717), foregroundColor: gold),
      textTheme: ThemeData.dark().textTheme.apply(bodyColor: vibBlue, displayColor: vibBlue),
      iconTheme: const IconThemeData(color: gold),
      inputDecorationTheme: const InputDecorationTheme(labelStyle: TextStyle(color: vibBlue), errorStyle: TextStyle(color: vibRed)),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: const Color(0xFF111111),
        indicatorColor: const Color(0xFF423416), iconTheme: WidgetStateProperty.all(const IconThemeData(color: gold))),
    ),
    home: const Directionality(textDirection: TextDirection.rtl, child: Gate()),
  );
}

class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, auth) {
      if (!auth.hasData) return const LoginPage();
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('users').doc(auth.data!.uid).snapshots(),
        builder: (context, user) {
          if (user.hasError) return const Center(child: Text('تعذر تحميل الحساب'));
          if (!user.hasData) return const Center(child: CircularProgressIndicator());
          final data = user.data!.data();
          if (data == null || data['active'] != true || !['owner', 'employee'].contains(data['role'])) {
            return Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('الحساب غير مفعّل. المدير يحدد فرعك ويفعّل دخولك.'),
              if (data == null) FilledButton(
                onPressed: () async {
                  final person = FirebaseAuth.instance.currentUser;
                  final email = person?.email ?? '';
                  final rawPhone = email.split('@').first;
                  if (person == null || rawPhone.isEmpty) return;
                  final accountPhone = '+$rawPhone';
                  try {
                    await db.collection('users').doc(person.uid).set({
                      'role': 'pending', 'active': false, 'name': accountPhone,
                      'phone': accountPhone, 'createdAt': FieldValue.serverTimestamp(),
                    });
                  } catch (_) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تعذر إرسال طلب التفعيل')));
                  }
                },
                child: const Text('طلب تفعيل الحساب'),
              ),
              TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('خروج')),
            ])));
          }
          activeResetAt = data['resetAt'] as Timestamp?;
          final showCost = data['role']=='owner' || data['showSaleCost']==true;
          if(saleCostVisible.value!=showCost)WidgetsBinding.instance.addPostFrameCallback((_)=>saleCostVisible.value=showCost);
          final editPrice=data['role']=='owner' || data['canEditSalePrice']==true;
          if(salePriceEditable.value!=editPrice)WidgetsBinding.instance.addPostFrameCallback((_)=>salePriceEditable.value=editPrice);
          final home = Home(canPurchase:data['canPurchase']==true,
            canViewCustomerBalance:data['canViewCustomerBalance']!=false,
            canViewCustomerStatement:data['canViewCustomerStatement']==true,
            canAddCustomer:data['canAddCustomer']==true,
            key:ValueKey('${auth.data!.uid}:${data['role']}'), uid: auth.data!.uid,
            role: data['role'] as String, branchId: (data['branchId'] ?? '') as String,
            name: (data['name'] ?? '') as String);
          return data['role'] == 'owner' ? FutureBuilder<void>(future:initializeRequestedInvoiceSeries(),builder:(context,ready){
            if(ready.hasError)return Scaffold(body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Text('تعذر تجهيز تسلسل الفواتير: ${ready.error}'),FilledButton(onPressed:()=>FirebaseAuth.instance.signOut(),child:const Text('خروج وإعادة المحاولة'))])));
            if(ready.connectionState!=ConnectionState.done)return const Scaffold(body:Center(child:CircularProgressIndicator()));
            return OwnerSecurity(child:home);}) : home;
        },
      );
    },
  );
}

class OwnerSecurity extends StatefulWidget {
  final Widget child;
  const OwnerSecurity({super.key, required this.child});
  @override State<OwnerSecurity> createState() => _OwnerSecurityState();
}

class _OwnerSecurityState extends State<OwnerSecurity> {
  final auth = LocalAuthentication();
  final password = TextEditingController();
  bool unlocked = false, checking = true, busy = false;
  String message = '';
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => biometric()); }
  Future<void> biometric() async {
    setState(() { checking = true; message = ''; });
    try {
      final available = await auth.canCheckBiometrics && await auth.isDeviceSupported();
      if (!available) throw Exception('البصمة غير متاحة على الجهاز');
      final ok = await auth.authenticate(localizedReason: 'استخدم بصمتك لفتح VIB MANAGER', options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true));
      if (mounted) setState(() { unlocked = ok; checking = false; if (!ok) message = 'لم يتم التحقق من البصمة'; });
    } catch (_) { if (mounted) setState(() { checking = false; message = 'استخدم الرقم السري كبديل'; }); }
  }
  Future<void> verifyPassword() async {
    if (password.text.length < 6) return;
    setState(() { busy = true; message = ''; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.email == null) throw Exception();
      await user!.reauthenticateWithCredential(EmailAuthProvider.credential(email: user.email!, password: password.text));
      if (mounted) setState(() => unlocked = true);
    } catch (_) { if (mounted) setState(() => message = 'الرقم السري غير صحيح'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) {
    if (unlocked) return widget.child;
    return Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.fingerprint, size: 86, color: gold), const Text('حماية VIB MANAGER', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 18),
      if (checking) const CircularProgressIndicator() else FilledButton.icon(onPressed: biometric, icon: const Icon(Icons.fingerprint), label: const Text('فتح بالبصمة')),
      const SizedBox(height: 18), TextField(controller: password, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الرقم السري البديل')),
      const SizedBox(height: 10), FilledButton(onPressed: busy ? null : verifyPassword, child: const Text('فتح بالرقم السري')),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(message, style: const TextStyle(color: Colors.redAccent))),
      TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('تسجيل الخروج')),
    ])))));
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController(), pin = TextEditingController();
  static const _secure = FlutterSecureStorage();
  String? error;
  bool busy = false;
  String? normalizedPhone() {
    var value = phone.text.replaceAll(RegExp(r'\D'), '');
    if (value.startsWith('00')) value = value.substring(2);
    if (value.startsWith('0')) value = '20${value.substring(1)}';
    if (!value.startsWith('20') || value.length != 12) return null;
    return '+$value';
  }

  String emailFor(String value) => '${value.replaceAll('+', '')}@vib.local';

  Future<void> login({required bool create}) async {
    setState(() { busy = true; error = null; });
    try {
      final number = normalizedPhone();
      final password = pin.text.trim();
      if (number == null) throw Exception('اكتب رقم مصري صحيح مثل 01012345678');
      if (!RegExp(r'^\d{6,}$').hasMatch(password)) throw Exception('الرقم السري لازم يكون 6 أرقام على الأقل');
      if (create) {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailFor(number), password: password);
        await db.collection('users').doc(credential.user!.uid).set({
          'role': 'pending', 'active': false, 'name': number, 'phone': number,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailFor(number), password: password);
      }
      await _secure.write(key: 'vib_saved_phone', value: number);
      await _secure.write(key: 'vib_saved_pin', value: password);
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' || 'invalid-credential' => 'الرقم أو الرقم السري غير صحيح',
        'email-already-in-use' => 'الرقم مسجل بالفعل؛ اضغط دخول',
        'weak-password' => 'اختر رقمًا سريًا أقوى',
        _ => e.message ?? 'تعذر تسجيل الدخول',
      };
      if (mounted) setState(() => error = message);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  Future<void> recoverPasswordByBiometric() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    FirebaseAuth? recoveryAuth;
    try {
      final savedPhone = (await _secure.read(key: 'vib_saved_phone') ?? '').trim();
      final savedPin = (await _secure.read(key: 'vib_saved_pin') ?? '').trim();
      if (savedPhone.isEmpty || savedPin.isEmpty) {
        throw Exception('الاسترجاع بالبصمة يعمل بعد تسجيل دخول ناجح مرة واحدة على نفس الموبايل.');
      }

      final entered = normalizedPhone();
      if (phone.text.trim().isNotEmpty && entered == null) {
        throw Exception('اكتب رقم الموبايل بصورة صحيحة');
      }
      if (entered != null && entered != savedPhone) {
        throw Exception('هذا الرقم ليس الحساب المحفوظ على هذا الموبايل.');
      }

      final localAuth = LocalAuthentication();
      final available = await localAuth.canCheckBiometrics && await localAuth.isDeviceSupported();
      if (!available) throw Exception('البصمة غير متاحة أو غير مفعلة على هذا الموبايل.');

      final verified = await localAuth.authenticate(
        localizedReason: 'استخدم بصمتك لاسترجاع الرقم السري في VIB',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!verified) throw Exception('لم يتم التحقق من البصمة.');

      FirebaseApp recoveryApp;
      try {
        recoveryApp = Firebase.app('vibLocalRecovery');
      } catch (_) {
        recoveryApp = await Firebase.initializeApp(
          name: 'vibLocalRecovery',
          options: await _firebaseOptionsForThisApp(),
        );
      }
      recoveryAuth = FirebaseAuth.instanceFor(app: recoveryApp);
      await recoveryAuth.signOut();

      final credential = await recoveryAuth.signInWithEmailAndPassword(
        email: emailFor(savedPhone),
        password: savedPin,
      );

      if (!mounted) return;
      final newPin = TextEditingController();
      final confirmPin = TextEditingController();
      String? localError;

      final replacement = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            title: const Text('إنشاء رقم سري جديد'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('تم التحقق من البصمة بنجاح. اكتب الرقم السري الجديد.'),
                const SizedBox(height: 12),
                TextField(
                  controller: newPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الرقم السري الجديد'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'تأكيد الرقم السري',
                    errorText: localError,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  final a = newPin.text.trim();
                  final b = confirmPin.text.trim();
                  if (a.length < 6 || int.tryParse(a) == null) {
                    update(() => localError = 'الرقم السري لازم يكون 6 أرقام على الأقل');
                    return;
                  }
                  if (a != b) {
                    update(() => localError = 'الرقمان غير متطابقين');
                    return;
                  }
                  Navigator.pop(dialog, a);
                },
                child: const Text('حفظ الرقم السري الجديد'),
              ),
            ],
          ),
        ),
      );

      newPin.dispose();
      confirmPin.dispose();

      if (replacement == null) {
        await recoveryAuth.signOut();
        return;
      }

      await credential.user!.updatePassword(replacement);
      await _secure.write(key: 'vib_saved_phone', value: savedPhone);
      await _secure.write(key: 'vib_saved_pin', value: replacement);
      await recoveryAuth.signOut();

      phone.text = savedPhone;
      pin.text = replacement;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تغيير الرقم السري بالبصمة بنجاح. اضغط دخول.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (recoveryAuth != null) {
        try { await recoveryAuth.signOut(); } catch (_) {}
      }
      final message = switch (e.code) {
        'invalid-credential' || 'wrong-password' =>
          'بيانات الاسترجاع المحفوظة قديمة. سجّل دخولك بالطريقة العادية مرة واحدة لتحديثها.',
        _ => e.message ?? 'تعذر تغيير الرقم السري',
      };
      if (mounted) setState(() => error = message);
    } catch (e) {
      if (recoveryAuth != null) {
        try { await recoveryAuth.signOut(); } catch (_) {}
      }
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('VIB', style: TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: gold)),
      const Text('المبيعات والمخزون', style: TextStyle(fontSize: 20)), const SizedBox(height: 28),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف المصري')),
      const SizedBox(height: 12),
      TextField(controller: pin, obscureText: true, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'رقم سري من 6 أرقام أو أكثر')),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.redAccent)),
      const SizedBox(height: 18),
      FilledButton(onPressed: busy ? null : () => login(create: false), child: const Text('دخول')),
      TextButton.icon(onPressed: busy ? null : recoverPasswordByBiometric, icon: const Icon(Icons.fingerprint), label: const Text('نسيت كلمة السر؟ استرجاع بالبصمة')),
      TextButton(onPressed: busy ? null : () => login(create: true), child: const Text('إنشاء حساب جديد')),
      const Text('استرجاع كلمة السر بالبصمة يعمل مجانًا على نفس الموبايل بعد أول تسجيل دخول ناجح. المدير يفعّل حساب الموظف ويحدد فرعه.'),
    ]),
  ))));
}

const managerNavy = Color(0xFF080808);
const managerSurface = Color(0xFF171717);
const managerBorder = Color(0xFF756037);
ThemeData managerTheme(BuildContext context) => Theme.of(context).copyWith(
  scaffoldBackgroundColor: managerNavy,
  colorScheme: Theme.of(context).colorScheme.copyWith(surface: managerSurface, primary: gold),
  appBarTheme: const AppBarTheme(backgroundColor: managerNavy, foregroundColor: gold, centerTitle: true, elevation: 0),
  cardTheme: const CardThemeData(color: managerSurface, elevation: 0),
);

class OfflineCacheNotice extends StatelessWidget {
  const OfflineCacheNotice({super.key});
  @override Widget build(BuildContext context)=>StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
    stream:db.collection('settings').doc('cash').snapshots(includeMetadataChanges:true),
    builder:(context,snapshot){
      if(snapshot.hasError)return const SizedBox.shrink();
      if(!snapshot.hasData||!snapshot.data!.metadata.isFromCache)return const SizedBox.shrink();
      final pending=snapshot.data!.metadata.hasPendingWrites;
      return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:pendingSalesQuery(true).snapshots(includeMetadataChanges:true),builder:(context,queue){
        final queuedSales=queue.data?.docs.where((d)=>d.data()['managerOffline']==true&&d.data()['status']=='pending').length??0;
        return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:db.collection('managerOfflineVoucherCancellations').snapshots(includeMetadataChanges:true),builder:(context,vouchers){
          final queuedVouchers=vouchers.data?.docs.where((d)=>d.data()['status']=='pending').length??0;
          final queued=queuedSales+queuedVouchers;
          final message=queued>0?'وضع غير متصل • $queued عملية تنتظر المزامنة':pending?'وضع غير متصل • توجد تغييرات تنتظر المزامنة':'وضع غير متصل • المعروض من البيانات المحفوظة على هذا الجهاز';
          return Container(width:double.infinity,color:(pending||queued>0)?const Color(0xFF5A3B12):const Color(0xFF3B321C),padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),
            child:Text(message,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white,fontSize:12)));
        });
      });
    });
}

class Home extends StatefulWidget {
  final String uid, role, branchId, name;
  final bool canPurchase,canViewCustomerBalance,canViewCustomerStatement,canAddCustomer;
  const Home({super.key, required this.uid, required this.role, required this.branchId, required this.name,
    this.canPurchase=false,this.canViewCustomerBalance=true,this.canViewCustomerStatement=false,this.canAddCustomer=false});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int page = 0;
  Timer? _presenceTimer;
  bool _presenceWriteInFlight = false;
  @override void initState() { super.initState(); if(widget.role == 'owner') {ChequeReminders.instance.watch(widget.uid);ManagerOfflineSaleSync.instance.start();ManagerOfflineVoucherSync.instance.start();} else { WidgetsBinding.instance.addObserver(this); _writePresence(true); _presenceTimer=Timer.periodic(const Duration(seconds:20),(_)=>_writePresence(true)); } ChatAlerts.instance.watch(widget.uid,widget.role == 'owner'); }
  Future<void> _writePresence(bool online) async {
    if(widget.role!='employee' || _presenceWriteInFlight) return;
    _presenceWriteInFlight=true;
    try { await db.collection('presence').doc(widget.uid).set({'online':online,'lastSeen':FieldValue.serverTimestamp()},SetOptions(merge:true)); }
    catch (_) { /* A missed heartbeat expires automatically in the manager view. */ }
    finally { _presenceWriteInFlight=false; }
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { _writePresence(state==AppLifecycleState.resumed); }
  Future<void> _signOut() async { await _writePresence(false); await FirebaseAuth.instance.signOut(); }
  @override void dispose() { ChatAlerts.instance.stop(); if(widget.role == 'owner') {ChequeReminders.instance.stop();ManagerOfflineSaleSync.instance.stop();ManagerOfflineVoucherSync.instance.stop();} else { _presenceTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); _writePresence(false); } super.dispose(); }

  void openPage(String title, Widget child) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(data: widget.role == 'owner' ? managerTheme(context) : Theme.of(context),
        child: Scaffold(appBar: AppBar(title: Text(title)), body: child)),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.role == 'owner';
    if (owner) {
      return Theme(data: managerTheme(context), child: Scaffold(
        appBar: AppBar(
          backgroundColor: managerNavy,
          centerTitle: true,
          toolbarHeight: 78,
          title:const Column(mainAxisSize:MainAxisSize.min,children:[Text('VIB للتجارة والتوزيع',style:TextStyle(color:gold,fontWeight:FontWeight.w800,fontSize:22)),Text('ALAAELGNDY',style:TextStyle(color:gold,fontSize:14,letterSpacing:2))]),
          leading: const ChatShortcut(owner: true),
          actions: [
            Padding(padding: const EdgeInsetsDirectional.only(end: 12), child: IconButton.filledTonal(
              tooltip: 'الضبط', style: IconButton.styleFrom(backgroundColor: managerSurface, foregroundColor: gold),
              onPressed: () => openPage('الضبط', const Management()), icon: const Icon(Icons.settings_outlined))),
          ],
        ),
        body: Column(children:[const OfflineCacheNotice(),Expanded(child:OwnerDashboard(uid: widget.uid, branchId: widget.branchId, openPage: openPage))]),
      ));
    }

    return Scaffold(
      appBar: AppBar(toolbarHeight:78,title:const Column(mainAxisSize:MainAxisSize.min,children:[Text('VIB للتجارة والتوزيع',style:TextStyle(color:gold,fontSize:20)),Text('ALAAELGNDY',style:TextStyle(color:gold,fontSize:13))]), actions: [
        const ChatShortcut(owner: false),
        if(widget.canPurchase) IconButton(tooltip:'المشتريات',icon:const Icon(Icons.post_add),onPressed:()=>openPage('مشتريات الموظف',const Purchases(owner:false))),
        IconButton(tooltip: 'خروج', onPressed: _signOut, icon: const Icon(Icons.logout)),
      ]),
      body: page == 0
          ? Products(owner: false, uid: widget.uid, branchId: widget.branchId)
          : page == 1
              ? Sales(owner: false, branchId: widget.branchId)
              : page == 2
                  ? StaffCustomers(canViewBalance:widget.canViewCustomerBalance,canViewStatement:widget.canViewCustomerStatement,canAddCustomer:widget.canAddCustomer)
                  : ReceiptVouchers(owner: false, branchId: widget.branchId),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (i) => setState(() => page = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'المنتجات'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'المبيعات'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'العملاء'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), label: 'سند قبض'),
        ],
      ),
    );
  }
}

class OwnerDashboard extends StatelessWidget {
  final String uid, branchId;
  final void Function(String title, Widget child) openPage;
  const OwnerDashboard({super.key, required this.uid, required this.branchId, required this.openPage});

  Widget tile(String title, IconData icon, VoidCallback onTap, double height) => Material(
    color: managerSurface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: managerBorder)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: SizedBox(height: height, child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 66, height: 66, decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF3B321C), Color(0xFF080808)]),
          borderRadius: BorderRadius.circular(16), border: Border.all(color: gold),
          boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(3, 4), blurRadius: 5)]),
          child: Icon(icon, color: gold, size: 34)),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(title, textAlign: TextAlign.center,
          maxLines: 2, style: const TextStyle(color: gold, fontWeight: FontWeight.w700, fontSize: 18))),
      ],
    ))),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final height = ((constraints.maxHeight - 100) / 3).clamp(132.0, 176.0).toDouble();
    const gap = 12.0;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 20), children: [
      Row(children: [
        Expanded(child: tile('المنتجات', Icons.inventory_2_outlined, () => openPage('المنتجات', Products(owner: true, uid: uid, branchId: branchId)), height)),
        const SizedBox(width: gap),
        Expanded(child: tile('المبيعات', Icons.shopping_cart_outlined, () => openPage('المبيعات', const Sales(owner: true, branchId: 'main')), height)),
      ]),
      const SizedBox(height: gap),
      Row(children: [
        Expanded(child: tile('العملاء', Icons.groups_outlined, () => openPage('العملاء', const Accounts()), height)),
        const SizedBox(width: gap),
        Expanded(child: tile('المشتريات', Icons.post_add_outlined, () => openPage('المشتريات', const Purchases()), height)),
      ]),
      const SizedBox(height: gap),
      Row(children: [
        Expanded(child: tile('سندات القبض', Icons.payments_outlined, () => openPage('سندات القبض', ReceiptVouchers(owner: true, branchId: branchId)), height)),
        const SizedBox(width: gap),
        Expanded(child: tile('الموردين', Icons.local_shipping_outlined, () => openPage('الموردين', const Accounts(startWithSuppliers: true)), height)),
      ]),
      const SizedBox(height: gap),
      Row(children:[
        Expanded(child:tile('سندات صرف الموردين', Icons.receipt_long, () => openPage('سندات صرف الموردين', const SupplierPaymentVouchers()), 132)),
        const SizedBox(width:gap),
        Expanded(child:tile('مواعيد الشيكات',Icons.event_note,() => openPage('مواعيد الشيكات',ChequeAgenda(uid:uid)),132)),
      ]),
      const SizedBox(height: 12),
      const PendingSalesShortcut(owner:true),
      const SizedBox(height: 18),
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.info_outline, color: gold, size: 20), SizedBox(width: 8),
        Flexible(child: Text('الموظفون وباقي الإدارة داخل الضبط', textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFA7B8CE), fontSize: 13))),
      ]),
    ]);
  });
}
class Products extends StatefulWidget {
  final bool owner;
  final String uid, branchId;
  const Products({super.key, required this.owner, required this.uid, required this.branchId});
  @override
  State<Products> createState() => _ProductsState();
}
class _ProductsState extends State<Products> {
  String query = '';
  bool get owner => widget.owner;
  String get branchId => widget.branchId;
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('products').snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return const Center(child: Text('تعذر تحميل المنتجات'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snap.data!.docs.where((d) => d.data()['active'] == true && '${d.data()['name'] ?? ''}'.toLowerCase().contains(query)).toList()
        ..sort((a,b) => '${a.data()['name'] ?? ''}'.compareTo('${b.data()['name'] ?? ''}'));
      return Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(decoration: const InputDecoration(labelText: 'بحث عن منتج — اكتب أي حرف', prefixIcon: Icon(Icons.search)), onChanged: (value) => setState(() => query = value.trim().toLowerCase()))),
        if (owner) Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [FilledButton.icon(onPressed: () => productDialog(context), icon: const Icon(Icons.add), label: const Text('إضافة منتج')), OutlinedButton.icon(onPressed: () => openProductImport(context), icon: const Icon(Icons.upload_file), label: const Text('إضافة الأصناف من ملف'))])),
        if (owner) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: OutlinedButton.icon(onPressed: () => openInventoryPrices(context), icon: const Icon(Icons.price_change), label: const Text('زيادة / تخفيض أسعار الأصناف'))),
        if (!owner) Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => newSaleDialog(context, false, branchId), icon: const Icon(Icons.add_shopping_cart), label: const Text('فاتورة بيع جديدة')))),
        Expanded(child: docs.isEmpty ? const Center(child: Text('لا توجد منتجات بعد')) : ListView.builder(itemCount: docs.length, itemBuilder: (context, i) {
          final d = docs[i], p = d.data();
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.collection('stock').doc('main_${d.id}').snapshots(),
            builder: (context, stock) {
              final quantity = stock.hasError || !stock.hasData ? null : (stock.data?.data()?['quantity'] as num?)?.toInt() ?? 0;
              return InventoryProductCard(employee:!owner,number: i + 1, name: '${p['name'] ?? ''}', quantity: quantity,
                quantityMessage: stock.hasError ? 'تعذر التحميل' : 'جارٍ التحميل', unitPrice: p['price'] as num?,
                onTap: () => productDetails(context, d.id,employee:!owner), actions: owner ? [
                  IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit), onPressed: () => productDialog(context, id: d.id, data: p)),
                  IconButton(tooltip: 'المخزون الرئيسي', icon: const Icon(Icons.warehouse), onPressed: () => mainStockDialog(context, d.id, '${p['name']}')),
                  IconButton(tooltip: 'حذف المنتج', icon: const Icon(Icons.delete_forever, color: Colors.redAccent), onPressed: () => archiveProduct(context, d.id, '${p['name'] ?? ''}')),
                ] : const []);
            },
          );
        })),
      ]);
    },
  );
}

Future<void> productDetails(BuildContext context, String productId,{bool employee=false}) async {
  await showDialog<void>(context: context, builder: (c) => AlertDialog(
    title: const Text('تفاصيل الصنف'),
    content: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('products').doc(productId).snapshots(),
      builder: (c, product) {
        if (product.hasError) return const Text('تعذر تحميل تفاصيل الصنف');
        if (!product.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
        final data = product.data!.data();
        if (data == null || data['active'] == false) return const Text('الصنف غير متاح');
        String price(Object? value) => value is num ? '${value.toStringAsFixed(2)} ج.م' : 'غير مسجل';
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${data['name'] ?? ''}', style: TextStyle(color:employee ? Colors.lightBlueAccent : gold,fontSize:20)),
          const SizedBox(height: 12),
          Text('الفئة: ${data['category'] ?? 'غير مصنف'}'),
          const SizedBox(height: 8),
          Text('سعر الشراء: ${price(data['purchasePrice'])}',style:TextStyle(color:employee ? Colors.greenAccent : null)),
          const SizedBox(height: 8),
          Text('سعر البيع: ${price(data['price'])}',style:TextStyle(color:employee ? Colors.greenAccent : null)),
          const SizedBox(height: 8),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.collection('stock').doc('main_$productId').snapshots(),
            builder: (c, stock) {
              if (stock.hasError) return const Text('تعذر تحميل المخزون الرئيسي', style: TextStyle(color: Colors.redAccent));
              if (!stock.hasData) return const Text('جارٍ تحميل الكمية…');
              return Text('المتوفر في المخزون الرئيسي: ${(stock.data!.data()?['quantity'] as num?)?.toInt() ?? 0}',style:TextStyle(color:employee ? Colors.redAccent : null));
            },
          ),
        ]);
      },
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق'))],
  ));
}

Future<void> productDialog(BuildContext context, {String? id, Map<String, dynamic>? data}) async {
  final name = TextEditingController(text: '${data?['name'] ?? ''}');
  final price = TextEditingController(text: '${data?['price'] ?? ''}');
  final purchasePrice = TextEditingController(text: '${data?['purchasePrice'] ?? ''}');
  final category = TextEditingController(text: '${data?['category'] ?? ''}');
  await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(title: Text(id == null ? 'منتج جديد' : 'تعديل المنتج'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
    TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المنتج')),
    TextField(controller: category, decoration: const InputDecoration(labelText: 'الفئة')),
    TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر')),
    TextField(controller: purchasePrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'تكلفة شراء الوحدة لتقرير الأرباح')),
  ])), actions: [
    TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
    FilledButton(onPressed: () async {
      final amount = double.tryParse(price.text);
      final unitCost = purchasePrice.text.trim().isEmpty ? null : double.tryParse(purchasePrice.text.trim());
      if (name.text.trim().isEmpty || amount == null || !amount.isFinite || amount < 0 ||
          (purchasePrice.text.trim().isNotEmpty && (unitCost == null || !unitCost.isFinite || unitCost < 0))) return;
      final ref = id == null ? db.collection('products').doc() : db.collection('products').doc(id);
      try { await ref.set({'name': name.text.trim(), 'category': category.text.trim().isEmpty ? 'غير مصنف' : category.text.trim(), 'price': amount,
        if (unitCost != null) 'purchasePrice': unitCost,
        'active': true, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        if (dialogContext.mounted) Navigator.pop(dialogContext);
      } catch (_) { if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('فشل حفظ المنتج'))); }
    }, child: const Text('حفظ')),
  ]));
}

Future<void> archiveProduct(BuildContext context, String id, String name) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.delete_forever, color: Colors.redAccent),
        SizedBox(width: 8),
        Expanded(child: Text('حذف المنتج فعليًا')),
      ]),
      content: Text(
        'سيتم حذف "$name" من المنتجات وتصفير رصيده في كل المخازن.\n\n'
        'الفواتير والحركات القديمة ستظل محفوظة كسجل.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(c, true),
          icon: const Icon(Icons.delete_forever),
          label: const Text('حذف فعلي'),
        ),
      ],
    ),
  ) ?? false;

  if (!yes || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final notice = messenger.showSnackBar(
    const SnackBar(content: Text('جاري حذف المنتج...'), duration: Duration(minutes: 1)),
  );

  try {
    final stockDocs = await db.collection('stock').where('productId', isEqualTo: id).get();

    // Firestore production rules may forbid deleting stock documents.
    // Zero them first so product deletion still works safely.
    for (var i = 0; i < stockDocs.docs.length; i += 400) {
      final batch = db.batch();
      final chunk = stockDocs.docs.skip(i).take(400);
      for (final doc in chunk) {
        batch.update(doc.reference, {'quantity': 0});
      }
      await batch.commit();
    }

    await db.collection('products').doc(id).delete();

    final productCheck = await db.collection('products').doc(id).get();
    final stockCheck = await db.collection('stock').where('productId', isEqualTo: id).get();
    final stockNotZero = stockCheck.docs.any((d) => ((d.data()['quantity'] as num?)?.toInt() ?? 0) != 0);

    if (productCheck.exists || stockNotZero) {
      throw Exception('الحذف لم يكتمل بالكامل');
    }

    notice.close();
    if (context.mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('تم حذف المنتج وتصفير رصيده فعليًا')));
    }
  } catch (e) {
    notice.close();
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تعذر الحذف'),
          content: SelectableText('السبب: $e'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق')),
          ],
        ),
      );
    }
  }
}

class PurchaseDiscountDraft {
  double? baseCost;
  double percent = 0;
}

class SaleLine {
  String? productId;
  final quantity = TextEditingController(text: '1');
  final price = TextEditingController();
  final discount = PurchaseDiscountDraft();
  SaleLine({this.productId, double? unitPrice}) {
    if (unitPrice != null) price.text = unitPrice.toStringAsFixed(2);
  }
  void dispose() { quantity.dispose(); price.dispose(); }
}

InputDecoration _vibInvoiceInput(String label, {IconData? icon}) => InputDecoration(
  labelText: label,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
  prefixIcon: icon == null ? null : Icon(icon, size: 18, color: gold),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: Color(0xFF6F5A2A)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: gold, width: 1.4),
  ),
);

Widget _vibInvoicePanel({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(8)}) => Container(
  width: double.infinity,
  padding: padding,
  decoration: BoxDecoration(
    color: const Color(0xFF0B0B0B),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFF8C6F2A), width: .8),
  ),
  child: child,
);

Widget _vibMoneyRow(String label, String value, {Color? valueColor, bool bold = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(children: [
    Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
    Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontWeight: bold ? FontWeight.bold : FontWeight.w500, fontSize: bold ? 17 : 14)),
  ]),
);

Widget _vibInvoiceTableHeader({required String priceLabel}) => Container(
  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
  decoration: const BoxDecoration(
    color: Color(0xFFD6AC55),
    borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
  ),
  child: Row(children: [
    const SizedBox(width: 26, child: Text('م', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
    const Expanded(flex: 5, child: Text('المنتج', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
    Expanded(flex: 3, child: Text(priceLabel, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
    const Expanded(flex: 2, child: Text('العدد', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
    const Expanded(flex: 3, child: Text('الإجمالي', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
    const SizedBox(width: 36, child: Text('حذف', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11))),
  ]),
);

Future<void> groupedSaleDialog(BuildContext context, {required bool owner, required String branchId, String? initialProductId}) async {
  try {
    await _groupedSaleDialog(context, owner: owner, branchId: branchId, initialProductId: initialProductId);
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر تحميل بيانات الفاتورة. راجع الاتصال وصلاحيات الحساب وحاول مرة أخرى.')));
  }
}

Future<void> _groupedSaleDialog(BuildContext context, {required bool owner, required String branchId, String? initialProductId}) async {
  if(owner)await prepareInvoiceSerials('sales');
  final productsSnap = await db.collection('products').where('active', isEqualTo: true).get();
  var customersSnap = await db.collection('customers').get();
  final addedCustomers = <String, Map<String,dynamic>>{};
  if (!context.mounted) return;

  final products = productsSnap.docs.toList()
    ..sort((a, b) => '${a.data()['name'] ?? ''}'.compareTo('${b.data()['name'] ?? ''}'));
  if (products.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف منتجًا أولًا')));
    return;
  }

  QueryDocumentSnapshot<Map<String, dynamic>> productDoc(String id) => products.firstWhere((p) => p.id == id);
  final lines = <SaleLine>[];
  if (initialProductId != null && products.any((p) => p.id == initialProductId)) {
    final data = productDoc(initialProductId).data();
    lines.add(SaleLine(productId: initialProductId, unitPrice: (data['price'] as num?)?.toDouble() ?? 0));
  }

  String customerId = '';
  bool credit = false;
  bool allowShortage = false;
  bool allowBelowCost = false;
  bool saving = false, checkout = false;
  final paid = TextEditingController(text: '0');
  final reason = TextEditingController();
  final note = TextEditingController();
  final draftNumber = owner ? await invoiceDraftNumberPreview('sales') : 'يُخصص لدى المدير';
  final saleRef = db.collection('sales').doc();

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (outer) => StatefulBuilder(builder: (c, update) {
      double previewTotal = 0;
      for (final row in lines) {
        final q = int.tryParse(row.quantity.text.trim()) ?? 0;
        final p = double.tryParse(row.price.text.trim().replaceAll(',', '.')) ?? 0;
        previewTotal += q * p;
      }
      final selectedCustomer = customerId.isEmpty ? null : addedCustomers[customerId] ?? customersSnap.docs.firstWhere((d) => d.id == customerId).data();

      final previousBalance = (selectedCustomer?['balance'] as num?)?.toDouble() ?? 0;
      Future<void> editSelected(SaleLine row, {bool adding=false}) async {
        final product=productDoc(row.productId!).data();
        final result=await showInvoiceLineEditor(c,name:'${product['name'] ?? ''}',price:row.price,quantity:row.quantity,
          discount:row.discount,priceEditable:owner || salePriceEditable.value,allowDelete:!adding,saleScreen:true,
          unitCost:product['purchasePrice'] as num?,stockStream:invoiceMainStock(row.productId!));
        if(!c.mounted) {if(adding) row.dispose();return;}
        if(result==InvoiceLineEditAction.apply) update(() {if(adding) lines.add(row);});
        else if(result==InvoiceLineEditAction.delete) {update(()=>lines.remove(row));row.dispose();}
        else if(adding) row.dispose();
      }
      void addSelected(String id) async {
        if (saving || lines.length >= 50 || lines.any((row) => row.productId == id)) return;
        final product=productDoc(id).data();
        await editSelected(SaleLine(productId:id,unitPrice:(product['price'] as num?)?.toDouble() ?? 0),adding:true);
      }
      return InvoiceEditorFrame(
        title: checkout ? 'حفظ فاتورة المبيعات' : 'فاتورة مبيعات',checkout:checkout,total:previewTotal,
        tableMode:true,invoiceNumber:draftNumber,itemCount:lines.length,
        quantityCount:lines.fold<int>(0,(sum,row)=>sum+(int.tryParse(row.quantity.text) ?? 0)),
        headerAction:IgnorePointer(ignoring:saving,child:ChatShortcut(owner:owner)),
        toolbar:InvoiceProductsBar(inlineSearch:true,saleScreen:true,
          unitCosts:{for(final product in products) product.id:product.data()['purchasePrice'] as num?},stockStreamFor:invoiceMainStock,
          products:[for(final product in products) if(!lines.any((row)=>row.productId == product.id))
            (id:product.id,name:'${product.data()['name'] ?? ''}')],
          enabled:!saving && lines.length < 50,onSelect:addSelected,
          onSearch:() async {
            final id=await selectSaleProduct(c,products,lines.map((row)=>row.productId).whereType<String>().toSet());
            if(id != null && c.mounted) addSelected(id);
          },
        ),
        body:checkout ? ListView(children:[
          if(!owner && lines.length > 4) const Padding(padding:EdgeInsets.all(8),child:Text('أكثر من ٤ بنود: تُرسل للمدير، ولا تخصم المخزون أو تسجل الحسابات حتى الاعتماد.')),
          PurchaseSettlementPanel(total:previewTotal,previousBalance:previousBalance,credit:credit,
            paid:paid,enabled:!saving,partyLabel:'العميل',
            onModeChanged:(value)=>update(() => credit=value),onChanged:()=>update(() {})),
          OutlinedButton.icon(icon:const Icon(Icons.person_search),
            label:Text(customerId.isEmpty ? 'اسم العميل — اختيار عميل' : '${selectedCustomer?['name'] ?? ''}',softWrap:true),
            onPressed:saving ? null : () async {
              final id=await selectRegisteredCustomer(c);
              if(id == null || !c.mounted) return;
              final refreshed=await db.collection('customers').get();
              if(c.mounted) update(() {customersSnap=refreshed;customerId=id;});
            }),
          if(owner) FilledButton.icon(icon:const Icon(Icons.person_add_alt_1),
            label:const Text('إضافة عميل'),onPressed:saving ? null : () async {
              final result=await createInvoiceParty(c,'customers',false);
              if(result != null && c.mounted) update(() {
                addedCustomers[result.id]=result.data;customerId=result.id;
              });
            }),
          const SizedBox(height:10),

          if(owner) TextField(controller:note,enabled:!saving,maxLength:1000,decoration:_vibInvoiceInput('ملاحظة الفاتورة')),
          if(owner) ExpansionTile(title:const Text('صلاحيات المدير',style:TextStyle(fontSize:13)),children:[
            SwitchListTile(dense:true,title:const Text('السماح بالبيع رغم نقص الكمية'),value:allowShortage,onChanged:saving ? null : (v)=>update(()=>allowShortage=v)),
            SwitchListTile(dense:true,title:const Text('السماح بسعر أقل من التكلفة'),value:allowBelowCost,onChanged:saving ? null : (v)=>update(()=>allowBelowCost=v)),
            if(allowShortage || allowBelowCost) TextField(controller:reason,enabled:!saving,decoration:_vibInvoiceInput('سبب الاستثناء (إلزامي)')),
          ]),
        ]) : lines.isEmpty ? const Center(child:Text('اختر صنفًا من البحث أو القائمة')) : ListView(children:[
          for(var i=0;i<lines.length;i++) InvoiceCompactTableLine(
            key:ObjectKey(lines[i]),number:i+1,name:'${productDoc(lines[i].productId!).data()['name'] ?? ''}',
            price:lines[i].price,quantity:lines[i].quantity,onEdit:saving ? null : ()=>editSelected(lines[i]),
          ),
        ]),
        actions: [
          if(owner && MediaQuery.viewInsetsOf(c).bottom==0) TextButton.icon(icon:const Icon(Icons.edit_note),label:const Text('تعديل فاتورة مبيعات'),
            onPressed:saving ? null : () => editSaleByNumber(c)),
          TextButton(onPressed:saving ? null : () {if(checkout) {update(()=>checkout=false);} else {Navigator.pop(c);}},child:Text(checkout ? 'رجوع للبنود' : 'إلغاء')),
          FilledButton(onPressed: saving ? null : () async {
            FocusScope.of(c).unfocus();
            if (lines.isEmpty) {
              await showInvoiceSaveProblem(c, 'أضف منتجًا واحدًا على الأقل قبل حفظ الفاتورة');
              return;
            }
            if (!checkout) {update(() => checkout=true);return;}
            final entries = <SaleEntry>[];
            double total = 0;

            for (final row in lines) {
              final id = row.productId;
              final qty = int.tryParse(row.quantity.text.trim());
              final price = double.tryParse(row.price.text.trim().replaceAll(',', '.'));
              if (id == null || qty == null || qty <= 0 || price == null || !price.isFinite || price < 0 || entries.any((e) => e.id == id)) {
                await showInvoiceSaveProblem(c, 'راجع البنود: المنتج والكمية والسعر، ولا تكرر نفس المنتج');
                return;
              }
              final p = productDoc(id).data();
              final cost = (p['purchasePrice'] as num?)?.toDouble();
              if (cost != null && price < cost && !(owner && allowBelowCost)) {
                await showInvoiceSaveProblem(c, 'سعر ${p['name']} أقل من التكلفة');
                return;
              }
              entries.add((id: id, name: '${p['name'] ?? ''}', qty: qty, price:price,cost:cost,discount:row.discount.percent,basePrice:row.discount.baseCost ?? price));
              total += qty * price;
            }

            final payment = credit ? (double.tryParse(paid.text.trim().replaceAll(',', '.')) ?? -1) : total;
            if (payment < 0 || payment > total) {
              await showInvoiceSaveProblem(c, 'قيمة المدفوع غير صحيحة');
              return;
            }
            final due = total - payment;
            if ((!owner || due > 0) && customerId.isEmpty) {
              await showInvoiceSaveProblem(c, 'اختر عميلًا مسجلًا لربط الفاتورة ورصيد المديونية بحسابه');
              return;
            }
            if ((allowShortage || allowBelowCost) && reason.text.trim().isEmpty) {
              await showInvoiceSaveProblem(c, 'اكتب سبب الاستثناء');
              return;
            }

            update(() => saving = true);
            try {
              if (!owner && entries.length > 4) {
                await submitPendingSale(saleRef.id, entries, customerId, credit, payment, total);
                if (c.mounted) Navigator.pop(c);
                if (context.mounted) await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(
                  title:const Text('تم إرسال الفاتورة للمدير'),
                  content:const Text('في انتظار الاعتماد. لم يتم خصم المخزون أو تسجيل الحسابات بعد. تابع الحالة من المبيعات ← فواتير الموظف.'),
                  actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('تم'))]));
                return;
              }
              Map<String,dynamic> savedInvoice;
              try {
                savedInvoice = await commitGroupedSale(owner:owner,branchId:branchId,entries:entries,
                  total:total,payment:payment,credit:credit,customerId:customerId,saleRef:saleRef,
                  invoiceNote:note.text.trim(),allowShortage:allowShortage,allowBelowCost:allowBelowCost,overrideReason:reason.text.trim());
              } catch(e) {
                if(!owner||!isTemporaryFirestoreOffline(e)) rethrow;
                await submitManagerOfflineSale(id:saleRef.id,branchId:branchId,entries:entries,customerId:customerId,
                  credit:credit,paid:payment,total:total,note:note.text.trim(),allowShortage:allowShortage,
                  allowBelowCost:allowBelowCost,overrideReason:reason.text.trim());
                if(c.mounted)Navigator.pop(c);
                if(context.mounted)await showInvoiceSaveProblem(context,
                  'حُفظت الفاتورة محليًا في قائمة المزامنة. سيُخصم المخزون ويتحدث الحساب والصندوق بعد رجوع الإنترنت واعتماد العملية على الخادم.',
                  title:'الفاتورة تنتظر المزامنة',button:'تمام',success:true);
                return;
              }

              if (c.mounted) Navigator.pop(c);
              if (context.mounted) await showInvoiceSavedActions(context, 'sales', saleRef.id, savedInvoice);
            } catch (e) {
              if (c.mounted) {
                update(() => saving = false);
                final message = invoiceSaveFailureMessage(e);
                await showInvoiceSaveProblem(c, message);
              }
            }
          }, child:saving ? const InvoiceSaveButtonLabel(saving:true) : Text(checkout ? (!owner && lines.length > 4 ? 'إرسال للمدير' : 'تأكيد الحفظ') : (!owner && lines.length > 4 ? 'مراجعة وإرسال' : 'حفظ الفاتورة'))),
        ],
      );
    }),
  );

  for (final row in lines) { row.dispose(); }
  paid.dispose();
  reason.dispose(); note.dispose();
}

Future<void> saleDialog(BuildContext context, String productId, Map<String, dynamic> product, String uid, String branchId, {bool owner = false}) async {
  await groupedSaleDialog(context, owner: owner, branchId: branchId, initialProductId: productId);
}


class Sales extends StatefulWidget {
  final bool owner;
  final String branchId;
  const Sales({super.key, required this.owner, required this.branchId});
  @override
  State<Sales> createState() => _SalesState();
}
class _SalesState extends State<Sales> {
  @override void initState(){super.initState();if(widget.owner)prepareInvoiceSerials('sales').then((_){if(mounted)setState((){});}).catchError((Object e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر تجهيز أرقام المبيعات: $e')));});}
  DateTime selectedFrom = DateTime.now();
  DateTime selectedTo = DateTime.now();
  bool get owner => widget.owner;
  String get branchId => widget.branchId;
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: (owner ? db.collection('sales') : db.collection('sales').where('branchId', isEqualTo: branchId)).snapshots(),
    builder: (context, snap) {
    if (snap.hasError) return const Center(child: Text('تعذر عرض المبيعات'));
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final rows = snap.data!.docs
        .where((d) {
          final date = (d.data()['createdAt'] as Timestamp?)?.toDate();
          return visibleAfterReset(d.data()) && (owner || d.data()['branchId'] == branchId) &&
            date != null && !date.isBefore(movementReportBoundary(selectedFrom)) && date.isBefore(movementReportBoundary(selectedTo,next:true));
        })
        .toList()
      ..sort((a,b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12,12,12,4), child: FilledButton.icon(icon: const Icon(Icons.add_shopping_cart), label: const Text('فاتورة بيع جديدة'), onPressed: () => newSaleDialog(context, owner, branchId))),
      Padding(padding: const EdgeInsets.fromLTRB(12,4,12,8),child:SizedBox(width:double.infinity,child:OutlinedButton.icon(
        icon:const Icon(Icons.payments_outlined),label:const Text('سند قبض بدون فاتورة بيع'),
        onPressed:()=>createReceiptVoucher(context,branchId,owner:owner)))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),child: PendingSalesShortcut(owner:owner)),
      MovementPeriodControls(key:ValueKey('${selectedFrom.toIso8601String()}-${selectedTo.toIso8601String()}'),from:selectedFrom,to:selectedTo,enabled:true,onConfirm:(from,to)=>setState(() {selectedFrom=from;selectedTo=to;})),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Wrap(spacing: 8, runSpacing: 8, children: [
        if (owner) OutlinedButton.icon(icon: const Icon(Icons.summarize_outlined), label: const Text('تقرير حركة المبيعات'),
          onPressed: () => openVibReport(context, 'تقرير حركة المبيعات', const InvoiceMovementReportPage(type: 'sales'))),
        if (owner) OutlinedButton.icon(icon: const Icon(Icons.edit_note), label: const Text('تعديل فاتورة مبيعات'), onPressed: () => editSaleByNumber(context)),
      ])),
      Padding(padding: const EdgeInsets.all(8), child: Text('فواتير المبيعات • من ${DateFormat('dd/MM/yyyy').format(selectedFrom)} إلى ${DateFormat('dd/MM/yyyy').format(selectedTo)} • العدد: ${rows.length} • الإجمالي: ${movementReportMoney(rows.fold<int>(0,(sum,row){final value=row.data()['total'];return value is num && value.isFinite ? sum+(value*100).round() : sum;}))}',textAlign:TextAlign.center,style:const TextStyle(color:gold,fontWeight:FontWeight.bold))),
      Expanded(child: rows.isEmpty ? const Center(child: Text('لا توجد فواتير في هذا التاريخ')) : ListView(children: rows.map((d) {
        final sale = d.data();
        final paymentText = sale.containsKey('paid') ? ' • مدفوع ${sale['paid'] ?? 0} • باقي ${sale['due'] ?? 0}' : '';
        return Card(child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined, color: gold),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${sale['customerName'] ?? ''}'.trim().isEmpty ? 'بدون عميل مسجل' : '${sale['customerName']}',
              style: TextStyle(color:owner ? Colors.greenAccent : Colors.lightBlueAccent,fontWeight:FontWeight.bold,fontSize:16)),
            Text('رقم الفاتورة: ${invoiceDisplayNumber('sales',d.id,sale)}'),
          ]),
          subtitle: Text('فرع: ${sale['branchId']} • ${formatDate(sale['createdAt'])}$paymentText${sale['status'] == 'returned' ? ' • مرتجعة بالكامل' : ((sale['partialReturnTotal'] as num?) ?? 0) > 0 ? ' • مرتجع جزئي ${sale['partialReturnTotal']} ج.م' : ''}'),
          trailing: Text('${sale['total'] ?? 0} ج.م', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
          onTap: () => invoiceActions(context, 'sales', d.id, sale, canReturn: owner),
        ));
      }).toList())),
    ]);
  });
}

Future<void> newSaleDialog(BuildContext context, bool owner, String branchId) async {
  await groupedSaleDialog(context, owner: owner, branchId: owner ? 'main' : branchId);
}


class Branches extends StatelessWidget {
  const Branches({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('branches').snapshots(), builder: (context, snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    return Column(children: [FilledButton.icon(onPressed: () => branchDialog(context), icon: const Icon(Icons.add), label: const Text('فرع جديد')), Expanded(child: ListView(children: snap.data!.docs.map((d) => ListTile(title: Text('${d.data()['name'] ?? d.id}'), subtitle: Text('رمز الفرع: ${d.id}'), trailing: IconButton(icon: const Icon(Icons.inventory), onPressed: () => stockDialog(context, d.id)))).toList()))]);
  });
}
Future<void> branchDialog(BuildContext context) async {
  final name = TextEditingController();
  await showDialog<void>(context: context, builder: (c) => AlertDialog(title: const Text('فرع جديد'), content: TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الفرع')), actions: [FilledButton(onPressed: () async { if (name.text.trim().isEmpty) return; await db.collection('branches').add({'name': name.text.trim(), 'active': true}); if (c.mounted) Navigator.pop(c); }, child: const Text('حفظ'))]));
}
Future<void> stockDialog(BuildContext context, String branchId) async {
  final id = TextEditingController(), qty = TextEditingController();
  await showDialog<void>(context: context, builder: (c) => AlertDialog(title: const Text('نقل من المخزون الرئيسي'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: id, decoration: const InputDecoration(labelText: 'رمز المنتج')), TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية'))]), actions: [FilledButton(onPressed: () async {
    final q = int.tryParse(qty.text), p = id.text.trim(); if (q == null || q <= 0 || p.isEmpty) return;
    if (branchId == 'main') { ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('اختر فرعًا مختلفًا عن المخزون الرئيسي'))); return; }
    try { await db.runTransaction((tx) async {
      final mainRef = db.collection('stock').doc('main_$p'), branchRef = db.collection('stock').doc('${branchId}_$p');
      final main = await tx.get(mainRef), branch = await tx.get(branchRef), product = await tx.get(db.collection('products').doc(p));
      if (!product.exists || product.data()?['active'] != true) throw Exception('الصنف غير موجود أو غير نشط');
      final available = (main.data()?['quantity'] as num?)?.toInt() ?? 0;
      if (available < q) throw Exception('المخزون الرئيسي غير كافٍ');
      tx.set(mainRef, {'branchId': 'main', 'productId': p, 'quantity': available - q});
      tx.set(branchRef, {'branchId': branchId, 'productId': p, 'quantity': ((branch.data()?['quantity'] as num?)?.toInt() ?? 0) + q});
      final transferId = db.collection('stockMovements').doc().id;
      tx.set(db.collection('stockMovements').doc(), {'productId': p, 'productName': product.data()?['name'] ?? p, 'branchId': 'main', 'kind': 'transfer_out', 'quantity': -q, 'balanceAfter': available - q, 'referenceId': transferId, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
      tx.set(db.collection('stockMovements').doc(), {'productId': p, 'productName': product.data()?['name'] ?? p, 'branchId': branchId, 'kind': 'transfer_in', 'quantity': q, 'balanceAfter': ((branch.data()?['quantity'] as num?)?.toInt() ?? 0) + q, 'referenceId': transferId, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
    }); if (c.mounted) Navigator.pop(c);
    } catch (e) { if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('$e'))); }
  }, child: const Text('نقل'))]));
}

bool staffPresenceIsOnline(Map<String,dynamic>? presence,DateTime now) {
  final lastSeen=presence?['lastSeen'];
  if(presence?['online']!=true || lastSeen is! Timestamp) return false;
  final age=now.difference(lastSeen.toDate());
  return !age.isNegative && age<=const Duration(seconds:75);
}

class Staff extends StatefulWidget {
  const Staff({super.key});
  @override State<Staff> createState()=>_StaffState();
}
class _StaffState extends State<Staff> {
  Timer? _clock;
  @override void initState(){super.initState();_clock=Timer.periodic(const Duration(seconds:15),(_){if(mounted)setState((){});});}
  @override void dispose(){_clock?.cancel();super.dispose();}
  @override Widget build(BuildContext context)=>StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:db.collection('users').snapshots(),builder:(context,snapshot){
    if(snapshot.hasError)return const Center(child:Text('تعذر تحميل الموظفين'));
    if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
    final rows=snapshot.data!.docs.where((d)=>d.data()['role']!='deleted').toList();
    return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:db.collection('presence').snapshots(),builder:(context,presenceSnapshot){
      final presence={for(final d in presenceSnapshot.data?.docs??const <QueryDocumentSnapshot<Map<String,dynamic>>>[]) d.id:d.data()};
      final now=DateTime.now();
      return ListView.builder(itemCount:rows.length,itemBuilder:(context,i){final row=rows[i],data=row.data(),employee=data['role']=='employee';
        final online=employee && staffPresenceIsOnline(presence[row.id],now);
        return ListTile(title:Row(children:[
          if(employee) Padding(padding:const EdgeInsetsDirectional.only(end:7),child:Tooltip(message:online?'متصل الآن':'غير متصل',child:Container(width:10,height:10,decoration:BoxDecoration(color:online?Colors.greenAccent:Colors.grey,borderRadius:BorderRadius.circular(8))))),
          Expanded(child:Text('${i+1}. ${data['name'] ?? data['phone'] ?? row.id}',overflow:TextOverflow.ellipsis)),
        ]),
          subtitle:Text(data['role']=='owner'?'المدير':data['role']=='pending'?'بانتظار التفعيل':'${data['branchId'] ?? ''} • ${data['canPurchase']==true?'المشتريات مسموحة':'المشتريات ممنوعة'}'),
          trailing:data['role']=='owner'?const Icon(Icons.verified_user):Row(mainAxisSize:MainAxisSize.min,children:[
            IconButton(tooltip:'صلاحيات الموظف',icon:const Icon(Icons.manage_accounts),onPressed:()=>assignEmployee(context,row.id,data)),
            IconButton(tooltip:'حذف الموظف',icon:const Icon(Icons.delete_forever,color:Colors.redAccent),onPressed:()=>deleteEmployee(context,row.id,data)),
          ]));});
    });
  });
}
Future<void> deleteEmployee(BuildContext context,String id,Map<String,dynamic> data) async {
  final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('حذف الموظف'),
    content:Text('حذف ${data['name'] ?? ''} ومنع دخوله؟ الفواتير وسندات القبض القديمة تظل محفوظة.'),actions:[
      TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),
      FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('حذف الموظف'))]));
  if(yes!=true)return;
  try {await db.runTransaction((tx) async {
    final actor=FirebaseAuth.instance.currentUser!.uid;
    final profile=(await tx.get(db.collection('users').doc(actor))).data();
    final ref=db.collection('users').doc(id),target=(await tx.get(ref)).data();
    if(profile?['role']!='owner' || profile?['active']!=true || target?['role']=='owner' || actor==id)throw StateError('لا يمكن حذف المدير');
    if(target==null)throw StateError('الموظف غير موجود');
    tx.update(ref,{'role':'deleted','active':false,'canPurchase':false,'deletedAt':FieldValue.serverTimestamp(),'deletedBy':actor});
  });if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم حذف الموظف ومنع دخوله')));
  }catch(e){if(context.mounted)await showInvoiceSaveProblem(context,'تعذر حذف الموظف: $e');}
}

class Management extends StatelessWidget {
  const Management({super.key});
  Widget option(BuildContext context, String title, IconData icon, Widget page, {bool highlight = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(color: managerSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: highlight ? gold : managerBorder, width: highlight ? 1.5 : 1)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: Icon(icon, color: gold, size: 28),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 17)),
        trailing: const Icon(Icons.chevron_left, color: Color(0xFFA7B8CE)),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl,
          child: Theme(data: managerTheme(context), child: Scaffold(appBar: AppBar(title: Text(title)), body: page))))),
      )),
  );
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    option(context, 'الموظفون والصلاحيات', Icons.groups_outlined, const Staff(), highlight: true),
    option(context, 'الفروع والمخزون', Icons.storefront_outlined, const Branches()),
    option(context, 'جرد المخزون', Icons.inventory_2_outlined, const InventoryAudit()),
    option(context, 'عرض فواتير المبيعات', Icons.receipt_long_outlined, const InvoiceHistoryPage(type: 'sales')),
    option(context, 'عرض فواتير المشتريات', Icons.shopping_bag_outlined, const InvoiceHistoryPage(type: 'purchases')),
    option(context, 'إرجاع فاتورة مبيعات', Icons.assignment_return, const InvoiceReturnPage(type: 'sales')),
    option(context, 'إرجاع فاتورة مشتريات', Icons.assignment_return_outlined, const InvoiceReturnPage(type: 'purchases')),
    option(context, 'جيديا — روابط الدفع بالكارت', Icons.credit_card, const GeideaPayments()),
    option(context, 'الصندوق', Icons.account_balance_wallet_outlined, const CashBox()),
    option(context, 'المصروفات', Icons.receipt_long_outlined, const Expenses()),
    option(context, 'تقرير الأرباح', Icons.bar_chart_outlined, const ProfitReport()),
    option(context, 'تقرير بيع وشراء المنتج', Icons.swap_vert, const ItemMovementReport()),
    option(context, 'سجل حركات الحسابات', Icons.history, const AccountMovements()),
    option(context, 'الإعدادات والطباعة', Icons.settings_outlined, const AppSettings()),
    Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(color: const Color(0xFF30283B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF594051))),
      child: ListTile(leading: const Icon(Icons.restart_alt, color: Colors.redAccent),
        title: const Text('تصفير البرنامج', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_left, color: Colors.redAccent), onTap: () => resetProgram…56086 tokens truncated… i=int.tryParse('${e.key}'),q=e.value;if(i!=null&&q is num&&q.isFinite&&q>=0)returnedByLine[i]=q.toInt();}}
    final already=returnedByLine[sourceItemIndex]??0;if(qty<=0||quantity>qty-already)throw StateError('الكمية المطلوبة أكبر من المتبقي في الفاتورة');
    final productId='${item['productId']??''}';if(productId.isEmpty||productId=='null')throw StateError('الصنف لا يحتوي على رمز مخزون');
    final stockRef=db.collection('stock').doc('main_$productId'),stockSnap=await tx.get(stockRef),before=(stockSnap.data()?['quantity'] as num?)?.toInt()??0;
    if(before<quantity)throw StateError('المخزون الرئيسي لا يكفي لإرجاع الصنف: ${item['productName']??''}');
    final supplierId='${d['supplierId']??''}';if(supplierId.isEmpty)throw StateError('الفاتورة لا تحتوي على حساب مورد');
    final supplierRef=db.collection('suppliers').doc(supplierId),supplierSnap=await tx.get(supplierRef);if(!supplierSnap.exists)throw StateError('حساب المورد غير موجود');
    final cashRef=db.collection('settings').doc('cash'),cashSnap=await tx.get(cashRef);
    final settlement=returnSettlement(d,sales:false);
    final priorCash=((d['partialCashRefund'] as num?)?.toDouble()??0),priorDebt=((d['partialDebtReduction'] as num?)?.toDouble()??0);
    final cashAvailable=((settlement.cash*100).round()-(priorCash*100).round()).clamp(0,1000000000000).toInt();
    final debtAvailable=((settlement.debt*100).round()-(priorDebt*100).round()).clamp(0,1000000000000).toInt();
    final lineValue=(item['lineTotal'] as num?)?.toDouble()??qty*((item['unitCost'] as num?)?.toDouble()??0);
    final amount=((lineValue*100).round()*quantity/qty).round();
    final cashRefund=partialReturnCashCents(valueCents:amount,cashAvailableCents:cashAvailable,debtAvailableCents:debtAvailable),debtReduction=amount-cashRefund;
    final returnRef=db.collection('purchaseReturns').doc(),now=FieldValue.serverTimestamp();
    tx.set(stockRef,{'branchId':'main','productId':productId,'quantity':before-quantity},SetOptions(merge:true));
    tx.set(db.collection('stockMovements').doc(),{'productId':productId,'productName':item['productName'],'branchId':'main','kind':'purchase_return','quantity':-quantity,'balanceAfter':before-quantity,'referenceId':returnRef.id,'actorId':actor,'createdAt':now});
    final supplierBefore=(supplierSnap.data()?['balance'] as num?)?.toDouble()??0,supplierAfter=((supplierBefore*100).round()-debtReduction)/100;
    if(debtReduction>0){tx.update(supplierRef,{'balance':supplierAfter,'updatedAt':now});tx.set(db.collection('accountMovements').doc(),{'accountType':'suppliers','accountId':supplierId,'accountName':d['supplierName'],'kind':'purchase_return','amount':debtReduction/100,'balanceBefore':supplierBefore,'balanceAfter':supplierAfter,'referenceId':returnRef.id,'createdAt':now,'actorId':actor});}
    final cashBefore=(cashSnap.data()?['balance'] as num?)?.toDouble()??0,cashAfter=((cashBefore*100).round()+cashRefund)/100;
    if(cashRefund>0){tx.set(cashRef,{'balance':cashAfter,'updatedAt':now},SetOptions(merge:true));tx.set(db.collection('accountMovements').doc(),{'accountType':'cash','kind':'purchase_return','amount':cashRefund/100,'delta':cashRefund/100,'balanceBefore':cashBefore,'balanceAfter':cashAfter,'accountId':supplierId,'accountName':d['supplierName'],'referenceId':returnRef.id,'reason':'استرداد نقدية مرتجع صنف مشتريات','actorId':actor,'createdAt':now});}
    tx.set(returnRef,{'sourceInvoiceId':id,'returnType':'partial','sourceItemIndex':sourceItemIndex,'sourceLineKey':'$sourceItemIndex','sourceQuantity':quantity,'items':[{'sourceItemIndex':sourceItemIndex,'productId':productId,'productName':item['productName'],'quantity':quantity,'unitCost':item['unitCost']??0,'lineTotal':amount/100}],'total':amount/100,'cashRefund':cashRefund/100,'debtReduction':debtReduction/100,'supplierId':supplierId,'supplierName':d['supplierName'],'invoiceNumber':d['invoiceNumber'],'internalNumber':d['internalNumber'],'invoiceBarcode':d['invoiceBarcode'],'createdAt':now,'actorId':actor});
    final quantities=Map<String,dynamic>.from(rawReturned is Map?rawReturned:{});quantities['$sourceItemIndex']=already+quantity;
    final priorTotal=((d['partialReturnTotal'] as num?)?.toDouble()??0),priorCashTotal=((d['partialCashRefund'] as num?)?.toDouble()??0),priorDebtTotal=((d['partialDebtReduction'] as num?)?.toDouble()??0);
    tx.update(invoiceRef,{'partialReturnQuantities':quantities,'partialReturnTotal':((priorTotal*100).round()+amount)/100,'partialCashRefund':((priorCashTotal*100).round()+cashRefund)/100,'partialDebtReduction':((priorDebtTotal*100).round()+debtReduction)/100,'lastPartialReturnId':returnRef.id});
  });
}

({double cash, double debt}) returnSettlement(Map<String, dynamic> data, {required bool sales}) {
  double read(String key, double fallback) {
    final value = data[key];
    if (value == null) return fallback;
    if (value is! num || !value.isFinite || value < 0) throw StateError('قيمة تسوية الفاتورة غير صحيحة');
    return value.toDouble();
  }
  final total = data['total'] == null ? read('paid', 0) + read('due', 0) : read('total', 0);
  final paid = read('paid', total);
  final due = read('due', total - paid);
  if (((paid * 100).round() + (due * 100).round() - (total * 100).round()).abs() > 1) {
    throw StateError('إجمالي الفاتورة لا يطابق المدفوع والباقي');
  }
  if (sales) {
    final receipts = read('receiptPaid', 0);
    if (receipts > due + 0.005) throw StateError('التحصيل المرتبط أكبر من باقي الفاتورة');
    return (cash: paid + receipts, debt: (due - receipts).clamp(0, due).toDouble());
  }
  final postedCash = data['cashPosted'] == true ? paid : read('cashPaidPosted', 0);
  if (postedCash > paid + 0.005) throw StateError('المبلغ المسجل في الصندوق أكبر من المدفوع');
  return (cash: postedCash, debt: due);
}

Future<void> confirmReturn(BuildContext context, String type, String id, Map<String, dynamic> data) async {
  try {
    final current = (await db.collection(type).doc(id).get(const GetOptions(source: Source.server))).data();
    if (current == null || current['status'] == 'returned' || !visibleAfterReset(current)) throw StateError('الفاتورة غير متاحة للمرتجع');
    if (type == 'sales' || type == 'purchases') {
      final priorReturns = await db.collection(type=='sales'?'salesReturns':'purchaseReturns').where('sourceInvoiceId', isEqualTo: id)
          .get(const GetOptions(source: Source.server));
      if (priorReturns.docs.any((d) => d.data()['returnType'] == 'partial')) {
        if (context.mounted) await showInvoiceSaveProblem(context,
          'بدأ إرجاع أصناف منفردة من هذه الفاتورة. استخدم «إرجاع صنف من الفاتورة» للكميات المتبقية؛ لا يمكن إرجاع الفاتورة كاملة بعد بدء المرتجع الجزئي.',
          title: 'أكمل المرتجع الجزئي', button: 'تمام');
        return;
      }
    }
    if(type=='sales' && ((current['onlinePaid'] as num?)??0)>0){
      if(context.mounted){await showInvoiceSaveProblem(context,'الفاتورة لها سداد بالكارت. رد المبلغ من سجل جيديا وانتظر تأكيده قبل إرجاع الفاتورة.',title:'رد الكارت أولًا',button:'تمام');
        if(context.mounted)await openGeideaPayments(context,invoiceId:id);}
      return;
    }
    final sales = type == 'sales', settlement = returnSettlement(current, sales: type == 'sales');
    final partyId = '${current[sales ? 'customerId' : 'supplierId'] ?? ''}';
    final party = partyId.isEmpty ? null : (await db.collection(sales ? 'customers' : 'suppliers').doc(partyId).get(const GetOptions(source: Source.server))).data();
    final balance = (party?['balance'] as num?)?.toDouble() ?? 0;
    final after = ((balance * 100).round() - (settlement.debt * 100).round()) / 100;
    if (!context.mounted) return;
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('مراجعة وتأكيد المرتجع'), content: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('الفاتورة: $id\n${sales ? 'العميل' : 'المورد'}: ${current[sales ? 'customerName' : 'supplierName'] ?? ''}'),
      Text(sales ? 'ستُضاف كميات الفاتورة إلى المخزون.' : 'ستُخصم كميات الفاتورة من المخزون الرئيسي.'),
      Text('تخفيض الذمة: ${settlement.debt.toStringAsFixed(2)} ج.م'),
      if(party != null) Text('الرصيد الحالي: ${balance.toStringAsFixed(2)}\nالرصيد بعد المرتجع: ${after.toStringAsFixed(2)} • ${accountBalanceLabel(after,supplier:!sales)}'),
      Text('${sales ? 'رد من الصندوق' : 'استرداد إلى الصندوق'}: ${settlement.cash.toStringAsFixed(2)} ج.م'),
      if(!sales) const Text('سندات الصرف العامة للمورد تظل مسجلة. أي رصيد سالب بعد المرتجع يُحسب مبلغًا لك عند المورد، ولا يُرد من الصندوق مرة أخرى.'),
      if(sales) const Text('سندات القبض المرتبطة بهذه الفاتورة تدخل في رد النقدية. سندات القبض العامة تظل محفوظة؛ أي زيادة بعد المرتجع تصبح رصيدًا للعميل عندك.'),
      const Text('الفاتورة الأصلية تظل محفوظة، ولا يمكن إرجاعها مرتين. الأرصدة تُراجع مجددًا عند التنفيذ.'),
    ])), actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('تأكيد المرتجع'))])) ?? false;
    if (!yes || !context.mounted) return;
    await returnInvoice(type, id, expectedSignature: invoiceReturnSignature(current));
    if (context.mounted) await showInvoiceSaveProblem(context,'تم تسجيل المرتجع وتحديث المخزون والذمة والصندوق وحفظ الفاتورة الأصلية.',title:'تم تسجيل المرتجع',button:'تمام',success:true);
  } catch (e) { if (context.mounted) await showInvoiceSaveProblem(context,'تعذر المرتجع: $e',title:'لم يتم تسجيل المرتجع',button:'رجوع'); }
}

String accountBalanceLabel(num balance, {required bool supplier}) => balance < 0
  ? (supplier ? 'رصيد لك عند المورد' : 'رصيد للعميل عندك')
  : balance == 0 ? 'الحساب متعادل' : supplier ? 'المتبقي عليك للمورد' : 'المتبقي على العميل';

String invoiceReturnSignature(Map<String,dynamic> data) => jsonEncode({for(final key in
  ['status','revision','items','productId','quantity','branchId','stockBranchId','customerId','supplierId','total','due','paid','receiptPaid','onlinePaid','onlinePaymentEver','cashPosted','cashPaidPosted','partialReturnQuantities','partialReturnTotal','partialCashRefund','partialDebtReduction']) key:data[key]});

Future<void> returnInvoice(String type, String id, {String? expectedSignature}) async {
  if (!['sales', 'purchases'].contains(type)) throw StateError('نوع الفاتورة غير صحيح');
  final preflight = (await db.collection(type).doc(id).get()).data();
  if (preflight == null) throw Exception('الفاتورة غير موجودة');
  await db.runTransaction((tx) async {
    final invoiceRef = db.collection(type).doc(id);
    final invoiceSnap = await tx.get(invoiceRef);
    final d = invoiceSnap.data();
    if (d == null) throw Exception('الفاتورة غير موجودة');
    final actor = FirebaseAuth.instance.currentUser!.uid;
    final profile = await tx.get(db.collection('users').doc(actor));
    if (profile.data()?['active'] != true || profile.data()?['role'] != 'owner') throw StateError('المرتجعات للمدير فقط');
    if (!visibleAfterReset(d)) throw StateError('الفاتورة تخص دورة قديمة');
    if (expectedSignature != null && invoiceReturnSignature(d) != expectedSignature) throw StateError('الفاتورة تغيّرت؛ افتح مراجعة المرتجع من جديد');
    if(type=='sales' && ((d['onlinePaid'] as num?)??0)>0)throw StateError('يجب تأكيد رد مبلغ الكارت أولًا');
    if (d['status'] == 'returned') throw Exception('الفاتورة مرتجعة بالفعل');
    final returnedLines=d['partialReturnQuantities'];
    if(((d['partialReturnTotal'] as num?)?.toDouble()??0)>0||(returnedLines is Map&&returnedLines.isNotEmpty))throw StateError('الفاتورة بدأ لها مرتجع أصناف؛ أكمل الأصناف المتبقية بدل إرجاعها كاملة');

    final now = FieldValue.serverTimestamp();
    var items = <Map<String, dynamic>>[];
    final rawItems = d['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      for (final raw in rawItems) {
        if (raw is Map) items.add(Map<String, dynamic>.from(raw));
      }
    }
    if (items.isEmpty) {
      items.add({
        'productId': d['productId'],
        'productName': d['productName'],
        'quantity': d['quantity'] ?? 0,
        'unitPrice': d['unitPrice'],
        'unitCost': d['unitCost'],
        'lineTotal': d['total'],
      });
    }

    items = groupedReturnItems(items);
    if (type == 'sales') {
      final branchId = '${d['stockBranchId'] ?? d['branchId']}';
      if (branchId.isEmpty || branchId == 'null') throw StateError('مخزون الفاتورة غير مسجل');
      final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final item in items) {
        final productId = '${item['productId']}';
        stockSnaps[productId] = await tx.get(db.collection('stock').doc('${branchId}_$productId'));
      }

      DocumentSnapshot<Map<String, dynamic>>? customerSnap;
      final customerId = '${d['customerId'] ?? ''}';
      final due = returnSettlement(d, sales: true).debt;
      if (due > 0 && customerId.isEmpty) throw StateError('الفاتورة الآجلة بدون حساب عميل؛ راجع الفاتورة');
      if (customerId.isNotEmpty) {
        customerSnap = await tx.get(db.collection('customers').doc(customerId));
      }

      DocumentSnapshot<Map<String, dynamic>>? cashSnap;
      final hasFinancialFields = d.containsKey('paid') || d.containsKey('due');
      final paid = hasFinancialFields ? returnSettlement(d, sales: true).cash : 0;
      if (paid > 0) {
        cashSnap = await tx.get(db.collection('settings').doc('cash'));
        if (((cashSnap.data()?['balance'] as num?)?.toDouble() ?? 0) < paid) throw Exception('رصيد الصندوق لا يكفي لرد المبلغ المحصل');
      }
      if (customerSnap != null && !customerSnap.exists) throw Exception('حساب العميل غير موجود');
      // General receipts are account-level credit and remain posted. Only
      // this invoice's receiptPaid is refunded; unrelated collections are retained.

      final ret = db.collection('salesReturns').doc();
      for (final item in items) {
        final productId = '${item['productId']}';
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final stockRef = db.collection('stock').doc('${branchId}_$productId');
        final before = (stockSnaps[productId]?.data()?['quantity'] as num?)?.toInt() ?? 0;
        tx.set(stockRef, {'branchId': branchId, 'productId': productId, 'quantity': before + qty}, SetOptions(merge: true));
        tx.set(db.collection('stockMovements').doc(), {
          'productId': productId,
          'productName': item['productName'],
          'branchId': branchId,
          'kind': 'sales_return',
          'quantity': qty,
          'balanceAfter': before + qty,
          'referenceId': ret.id,
          'actorId': FirebaseAuth.instance.currentUser!.uid,
          'createdAt': now,
        });
      }

      if (customerSnap != null && customerSnap.exists && due > 0) {
        final beforeCustomer = (customerSnap.data()?['balance'] as num?)?.toDouble() ?? 0;
        final afterCustomer = ((beforeCustomer * 100).round() - (due * 100).round()) / 100;
        tx.update(db.collection('customers').doc(customerId), {'balance': afterCustomer, 'updatedAt': now});
        tx.set(db.collection('accountMovements').doc(), {
          'accountType': 'customers',
          'accountId': customerId,
          'accountName': d['customerName'],
          'kind': 'sales_return',
          'amount': due,
          'balanceBefore': beforeCustomer,
          'balanceAfter': afterCustomer,
          'referenceId': ret.id,
          'createdAt': now,
          'actorId': FirebaseAuth.instance.currentUser!.uid,
        });
      }

      if (cashSnap != null && paid > 0) {
        final beforeCash = (cashSnap.data()?['balance'] as num?)?.toDouble() ?? 0;
        final afterCash = ((beforeCash * 100).round() - (paid * 100).round()) / 100;
        tx.set(db.collection('settings').doc('cash'), {'balance': afterCash, 'updatedAt': now}, SetOptions(merge: true));
        tx.set(db.collection('accountMovements').doc(), {
          'accountType': 'cash',
          'kind': 'sales_return',
          'accountId': customerId,
          'accountName': d['customerName'],
          'amount': paid,
          'delta': -paid,
          'balanceBefore': beforeCash,
          'balanceAfter': afterCash,
          'referenceId': ret.id,
          'reason': 'رد قيمة فاتورة مبيعات',
          'createdAt': now,
          'actorId': FirebaseAuth.instance.currentUser!.uid,
        });
      }

      tx.set(ret, {...d, 'sourceInvoiceId': id, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': now});
      tx.update(invoiceRef, {'status': 'returned', 'returnedAt': now, 'returnId': ret.id});
    } else {
      final supplierRef = db.collection('suppliers').doc('${d['supplierId']}');
      final supplier = await tx.get(supplierRef);
      if (!supplier.exists) throw Exception('حساب المورد غير موجود');
      final oldBalance = (supplier.data()?['balance'] as num?)?.toDouble() ?? 0;
      final refund = returnSettlement(d, sales: false).cash;
      final cashRef = db.collection('settings').doc('cash');
      final cash = await tx.get(cashRef);
      final cashBefore = (cash.data()?['balance'] as num?)?.toDouble() ?? 0;
      final due = returnSettlement(d, sales: false).debt;
      final supplierAfter = ((oldBalance * 100).round() - (due * 100).round()) / 100;
      final cashAfter = ((cashBefore * 100).round() + (refund * 100).round()) / 100;

      final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final item in items) {
        final productId = '${item['productId']}';
        stockSnaps[productId] = await tx.get(db.collection('stock').doc('main_$productId'));
      }
      for (final item in items) {
        final productId = '${item['productId']}';
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final before = (stockSnaps[productId]?.data()?['quantity'] as num?)?.toInt() ?? 0;
        if (before < qty) throw Exception('المخزون الرئيسي لا يكفي لإرجاع الصنف: ${item['productName'] ?? ''}');
      }

      final ret = db.collection('purchaseReturns').doc();
      for (final item in items) {
        final productId = '${item['productId']}';
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final stockRef = db.collection('stock').doc('main_$productId');
        final before = (stockSnaps[productId]?.data()?['quantity'] as num?)?.toInt() ?? 0;
        tx.set(stockRef, {'branchId': 'main', 'productId': productId, 'quantity': before - qty}, SetOptions(merge: true));
        tx.set(db.collection('stockMovements').doc(), {
          'productId': productId,
          'productName': item['productName'],
          'branchId': 'main',
          'kind': 'purchase_return',
          'quantity': -qty,
          'balanceAfter': before - qty,
          'referenceId': ret.id,
          'actorId': FirebaseAuth.instance.currentUser!.uid,
          'createdAt': now,
        });
      }

      if (refund > 0) {
        tx.set(cashRef, {'balance': cashAfter, 'updatedAt': now}, SetOptions(merge: true));
        tx.set(db.collection('accountMovements').doc(), {'accountType': 'cash', 'kind': 'purchase_return', 'amount': refund, 'delta': refund, 'balanceBefore': cashBefore, 'balanceAfter': cashAfter, 'accountId': d['supplierId'], 'accountName': d['supplierName'], 'referenceId': ret.id, 'reason': 'استرداد نقدية مرتجع مشتريات', 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': now});
      }
      tx.update(supplierRef, {'balance': supplierAfter, 'updatedAt': now});
      tx.set(ret, {...d, 'sourceInvoiceId': id, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': now});
      tx.set(db.collection('accountMovements').doc(), {
        'accountType': 'suppliers',
        'accountId': d['supplierId'],
        'accountName': d['supplierName'],
        'kind': 'purchase_return',
        'amount': due,
        'balanceBefore': oldBalance,
        'balanceAfter': supplierAfter,
        'referenceId': ret.id,
        'createdAt': now,
        'actorId': FirebaseAuth.instance.currentUser!.uid,
      });
      tx.update(invoiceRef, {'status': 'returned', 'returnedAt': now, 'returnId': ret.id});
    }
  });
}


class ItemMovementReport extends StatefulWidget {
  const ItemMovementReport({super.key});
  @override State<ItemMovementReport> createState() => _ItemMovementReportState();
}

class _ItemMovementReportState extends State<ItemMovementReport> {
  String? productId, branchId='main';
  DateTimeRange? range;
  String movementView='sales';

  Future<Map<String,String>> _movementCounterparties(List<QueryDocumentSnapshot<Map<String,dynamic>>> rows) async {
    final result=<String,String>{},invoices=<String,Map<String,dynamic>?>{},people=<String,String>{};
    for(final row in rows) {
      final d=row.data(),kind='${row.data()['kind'] ?? ''}',ref='${row.data()['referenceId'] ?? ''}';
      final type=kind=='sale' || kind=='saleCorrection' || kind=='correction_sale' || kind=='correction_return' ? 'sales'
        : kind=='purchase' || kind=='purchaseCorrection' ? 'purchases' : kind=='sales_return'?'salesReturns':kind=='purchase_return'?'purchaseReturns':null;
      final lines=<String>[];
      try {
        if(type!=null && ref.isNotEmpty){
          final key='$type/$ref';
          if(!invoices.containsKey(key))invoices[key]=(await db.collection(type).doc(ref).get(const GetOptions(source:Source.server))).data();
          final invoice=invoices[key];
          if(invoice!=null){
            final purchase=type=='purchases' || type=='purchaseReturns';
            lines.add('${purchase?'المورد':'العميل'}: ${invoice[purchase?'supplierName':'customerName'] ?? 'غير مسجل'}');
            lines.add('فاتورة: ${invoiceDisplayNumber(purchase?'purchases':'sales',ref,invoice)}');
          }else lines.add('مرجع الفاتورة: $ref');
        }else {
          final fallback=_movementFallbackParty(d);if(fallback.isNotEmpty)lines.add(fallback);
          if(ref.isNotEmpty)lines.add('المرجع: $ref');
        }
        final actor='${d['actorId'] ?? ''}';
        if(actor.isNotEmpty){
          if(!people.containsKey(actor))people[actor]='${(await db.collection('users').doc(actor).get(const GetOptions(source:Source.server))).data()?['name'] ?? actor}';
          lines.add('المستخدم: ${people[actor]}');
        }
      }catch(e){lines.add('تعذر تأكيد بيانات الطرف؛ المرجع: $ref');}
      result[row.id]=lines.join('\n');
    }return result;
  }

  String _movementFallbackParty(Map<String, dynamic> data) {
    final kind = '${data['kind'] ?? ''}';
    if (kind == 'transfer_in') return 'تحويل وارد من المخزون';
    if (kind == 'transfer_out') return 'تحويل إلى فرع';
    if (kind == 'adjustment') {
      final reason = '${data['reason'] ?? ''}'.trim();
      return reason.isEmpty ? 'تسوية مخزون' : 'سبب التسوية: $reason';
    }
    return '';
  }

  Future<void> _chooseMovementProduct(List<QueryDocumentSnapshot<Map<String,dynamic>>> products) async {
    var query = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final filtered = products.where((d) =>
            (d.data()['name']?.toString() ?? '').toLowerCase().contains(q)).toList();
          return AlertDialog(
            title: const Text('ابحث عن منتج'),
            content: SizedBox(
              width: double.maxFinite,
              height: 420,
              child: Column(children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'اكتب اسم المنتج',
                  ),
                  onChanged: (value) => setDialogState(() => query = value),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                    ? const Center(child: Text('لا توجد منتجات مطابقة'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final product = filtered[index];
                          return ListTile(
                            title: Text(product.data()['name']?.toString() ?? ''),
                            onTap: () => Navigator.pop(dialogContext, product.id),
                          );
                        },
                      ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (selected != null && mounted) setState(() => productId = selected);
  }

  Future<void> _printMovementReport(BuildContext context,String productName,List<QueryDocumentSnapshot<Map<String,dynamic>>> rows,
      Map<String,String> parties,ProductPeriodTotals total) async {
    try {
      final font=pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final bytes=await createProductTracePdf(productName,rows.map((r)=>{...r.data(),'id':r.id}).toList(),parties,total,font,range:range);
      await Printing.layoutPdf(name:'VIB-PRODUCT-MOVEMENT.pdf',onLayout:(_)async=>bytes);
    }catch(e){if(context.mounted)await showInvoiceSaveProblem(context,'تعذر طباعة حركة المنتج: $e');}
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
      future: Future.wait([db.collection('products').get(), db.collection('branches').get()]),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text('تعذر تحميل المنتجات أو الفروع: ${snap.error}', style: const TextStyle(color: Colors.redAccent)),
          );
        }
        if (!snap.hasData) return const LinearProgressIndicator();
        final products = snap.data![0].docs.where((d) => d.data()['active'] != false).toList();
        final branches = snap.data![1].docs;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(children: [
            Builder(builder: (context) {
              final selected = products.where((d) => d.id == productId).toList();
              final selectedName = selected.isEmpty
                  ? 'اضغط للبحث واختيار المنتج'
                  : (selected.first.data()['name']?.toString() ?? '');
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: products.isEmpty ? null : () => _chooseMovementProduct(products),
                child: InputDecorator(
                  decoration: _vibInvoiceInput('اختر المنتج', icon: Icons.inventory_2_outlined)
                      .copyWith(suffixIcon: const Icon(Icons.search)),
                  child: Text(selectedName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: selected.isEmpty ? Colors.white54 : null)),
                ),
              );
            }),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: branchId,
                isExpanded: true,
                decoration: _vibInvoiceInput('الفرع'),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('كل الفروع')),
                  const DropdownMenuItem(value: 'main', child: Text('المخزون الرئيسي')),
                  ...branches.where((d)=>d.id!='main').map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}', overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => branchId = v),
              )),
              const SizedBox(width: 6),
            ]),
            MovementPeriodControls(from:range?.start ?? DateTime(DateTime.now().year,DateTime.now().month,1),
              to:range?.end ?? DateTime.now(),enabled:true,onConfirm:(a,b)=>setState(()=>range=DateTimeRange(start:a,end:b))),
            TextButton(onPressed:()=>setState(()=>range=null),child:const Text('عرض كل الحركات')),
            const SizedBox(height: 7),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: products.isEmpty ? null : () {
                  if (productId == null) setState(() => productId = products.first.id);
                },
                icon: const Icon(Icons.manage_search_rounded),
                label: Text(productId == null ? 'عرض تقرير أول منتج' : 'تحديث تقرير المنتج'),
              ),
            ),
          ]),
        );
      },
    ),
    Expanded(
      child: productId == null
          ? const Center(child: Text('اختر المنتج لعرض تاريخه كامل'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('stockMovements').where('productId', isEqualTo: productId).snapshots(includeMetadataChanges:true),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('تعذر تحميل حركة المنتج: ${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                  ));
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                final rows = snap.data!.docs.where((d) {
                  final x = d.data();
                  if (!visibleAfterReset(x)) return false;
                  final date = (x['createdAt'] as Timestamp?)?.toDate();
                  return (branchId == null || x['branchId'] == branchId) &&
                      (range == null || (date != null && !date.isBefore(movementReportBoundary(range!.start)) && date.isBefore(movementReportBoundary(range!.end,next:true))));
                }).toList()
                  ..sort((a, b) => ((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                      .compareTo((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));

                final reportRows = rows.where((d) {
                  final kind='${d.data()['kind'] ?? ''}';
                  final sales = kind=='sale' || kind=='saleCorrection' || kind=='correction_sale' ||
                      kind=='correction_return' || kind=='sales_return';
                  final purchases = kind=='purchase' || kind=='purchaseCorrection' || kind=='purchase_return';
                  return movementView=='sales' ? sales : purchases;
                }).toList();
                final reportQuantity = reportRows.fold<num>(0, (sum, d) => sum + (((d.data()['quantity'] as num?) ?? 0).abs()));
                final incoming = rows.fold<num>(0, (sum, d) => sum + (((d.data()['quantity'] as num?) ?? 0).clamp(0, 999999999)));
                final outgoing = rows.fold<num>(0, (sum, d) => sum + ((-((d.data()['quantity'] as num?) ?? 0)).clamp(0, 999999999)));

                return FutureBuilder<List<dynamic>>(
                  future: Future.wait([
                    _movementCounterparties(rows),
                    branchId == null
                        ? db.collection('stock').where('productId', isEqualTo: productId).get(const GetOptions(source:Source.server))
                        : db.collection('stock').doc('${branchId}_$productId').get(const GetOptions(source:Source.server)),
                    db.collection('products').doc(productId).get(),
                  ]),
                  builder: (context, details) {
                    if(details.hasError)return Center(child:Text('تعذر تأكيد رصيد المنتج: ${details.error}'));
                    if (!details.hasData) return const Center(child: CircularProgressIndicator());

                    final parties = details.data![0] as Map<String, String>;
                    int currentQty = 0;
                    final stockResult = details.data![1];
                    if (stockResult is QuerySnapshot<Map<String, dynamic>>) {
                      currentQty = stockResult.docs.fold<int>(0, (sum, d) => sum + ((d.data()['quantity'] as num?)?.toInt() ?? 0));
                    } else if (stockResult is DocumentSnapshot<Map<String, dynamic>>) {
                      currentQty = (stockResult.data()?['quantity'] as num?)?.toInt() ?? 0;
                    }

                    final productSnap = details.data![2] as DocumentSnapshot<Map<String, dynamic>>;
                    final productName = '${productSnap.data()?['name'] ?? 'المنتج'}';

                    final ProductPeriodTotals totals;
                    try {totals=summarizeProductPeriod(snap.data!.docs.where((d)=>visibleAfterReset(d.data()) && (branchId==null || d.data()['branchId']==branchId)).map((d)=>d.data()).toList(),currentQty,range);}on StateError catch(e){return Center(child:Text('${e.message}'));}
                    return Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: _vibInvoicePanel(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                          child: Column(children: [
                            Row(children: [
                              Expanded(child: Text(productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                              Text('الموجود الآن: $currentQty', style: const TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 17)),
                            ]),
                            Text('أول المدة: ${totals.opening} • آخر المدة: ${totals.closing}'),
                            if(totals.gap!=0)Text('فرق غير مطابق لآخر حركة مسجلة: ${totals.gap}',style:const TextStyle(color:Colors.redAccent)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Expanded(child: Text('إجمالي الداخل: $incoming', style: const TextStyle(color: Colors.greenAccent))),
                              Expanded(child: Text('إجمالي الخارج: $outgoing', style: const TextStyle(color: Colors.redAccent))),
                              Text('الحركات: ${rows.length}'),
                            ]),
                            const SizedBox(height: 5),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: rows.isEmpty || snap.data!.metadata.isFromCache || snap.data!.metadata.hasPendingWrites ? null : () => _printMovementReport(context, productName, rows, parties, totals),
                                icon: const Icon(Icons.picture_as_pdf, size: 18),
                                label: const Text('تقرير PDF'),
                              ),
                            ),
                          ]),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Column(children: [
                          Row(children: [
                            Expanded(child: ChoiceChip(
                              label: const Text('العملاء اللي اشتروا'),
                              selected: movementView=='sales',
                              onSelected: (_) => setState(() => movementView='sales'),
                            )),
                            const SizedBox(width: 6),
                            Expanded(child: ChoiceChip(
                              label: const Text('الموردين اللي اشتريت منهم'),
                              selected: movementView=='purchases',
                              onSelected: (_) => setState(() => movementView='purchases'),
                            )),
                          ]),
                          Text('عدد الحركات: ${reportRows.length} • إجمالي الكمية: $reportQuantity'),
                        ]),
                      ),
                      Expanded(
                        child: reportRows.isEmpty
                            ? Center(child: Text(movementView=='sales'
                                ? 'لا توجد فواتير بيع لهذا الصنف في الفترة المختارة'
                                : 'لا توجد فواتير شراء لهذا الصنف في الفترة المختارة'))
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: reportRows.length,
                                itemBuilder: (context, index) {
                                  final row = reportRows[index];
                                  final x = row.data();
                                  final qty = (x['quantity'] as num?) ?? 0;
                                  final positive = qty >= 0;
                                  final party = parties[row.id] ?? '';
                                  final kind = '${x['kind']}';
                                  final action = movementName(kind);

                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 3),
                                    child: ListTile(
                                      dense: true,
                                      visualDensity: const VisualDensity(vertical: -2),
                                      leading: CircleAvatar(
                                        radius: 18,
                                        backgroundColor: positive ? const Color(0xFF123C25) : const Color(0xFF441B1B),
                                        child: Icon(positive ? Icons.south : Icons.north, size: 18, color: positive ? Colors.greenAccent : Colors.redAccent),
                                      ),
                                      title: Text(action, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text([
                                        if (party.isNotEmpty) party,
                                        'التاريخ: ${receiptReportStamp(x,DateTime.now())}',
                                        'الفرع: ${x['branchId'] == 'main' ? 'المخزون الرئيسي' : x['branchId']}',
                                      ].join('\n')),
                                      isThreeLine: true,
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('${positive ? '+' : ''}$qty', style: TextStyle(color: positive ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                                          Text('الرصيد ${x['balanceAfter'] ?? '-'}', style: const TextStyle(fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ]);
                  },
                );
              },
            ),
    ),
  ]);
}


class InvoiceCustomerChoiceRow extends StatelessWidget {
  final int number;
  final String name;
  final num balance;
  final VoidCallback onTap;
  const InvoiceCustomerChoiceRow({super.key, required this.number, required this.name,
    required this.balance, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(textDirection: TextDirection.rtl, children: [
        SizedBox(width: 32, child: Text('$number.', textAlign: TextAlign.right,
          textDirection: TextDirection.ltr, style: const TextStyle(color: gold, fontWeight: FontWeight.bold))),
        const SizedBox(width: 4),
        Expanded(child: Text(name, textDirection: TextDirection.rtl,
          textAlign:TextAlign.right,style:TextStyle(color:staffApp ? Colors.lightBlueAccent : null,fontWeight:FontWeight.w600))),
        const SizedBox(width: 8),
        Text('${balance.toStringAsFixed(2)} ج.م', textDirection: TextDirection.rtl,
          style:TextStyle(color:staffApp ? Colors.redAccent : Colors.greenAccent,fontWeight:FontWeight.bold)),
      ]),
    ),
  );
}

double invoiceCustomerChoicesHeight(BuildContext context) =>
  (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom - 240)
    .clamp(100.0, 360.0).toDouble();

Future<String?> selectRegisteredCustomer(BuildContext context) async {
  String query = '';
  return showDialog<String>(context: context, builder: (dialog) => StatefulBuilder(
    builder: (dialog, update) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      title: const Text('اختيار عميل مسجل'),
      content: SizedBox(width: 500, height: invoiceCustomerChoicesHeight(dialog), child: Column(children: [
        TextField(autofocus: true, decoration: const InputDecoration(labelText: 'بحث بالاسم أو رقم الهاتف', prefixIcon: Icon(Icons.search)),
          onChanged: (value) => update(() => query = value.trim().toLowerCase())),
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('customers').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const Center(child: Text('تعذر تحميل العملاء؛ راجع صلاحيات الحساب'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snapshot.data!.docs.where((d) => d.data()['active'] != false &&
              '${d.data()['name'] ?? ''} ${d.data()['phone'] ?? ''}'.toLowerCase().contains(query)).toList()
              ..sort((a, b) => '${a.data()['name']}'.compareTo('${b.data()['name']}'));
            if (rows.isEmpty) return const Center(child: Text('لا يوجد عملاء مطابقون'));
            return ListView.builder(itemCount: rows.length, itemBuilder: (context, index) {
              final row = rows[index];
              return InvoiceCustomerChoiceRow(number: index + 1,
                name: '${row.data()['name'] ?? ''}', balance: (row.data()['balance'] as num?) ?? 0,
                onTap: () => Navigator.pop(dialog, row.id));
            });
          },
        )),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إلغاء'))],
    ),
  ));
}

Future<String?> selectSaleProduct(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> products, Set<String> added) =>
  showInvoiceProductChoices(context,saleScreen:true,
    products:[for(final p in products) (id:p.id,name:'${p.data()['name'] ?? ''}')],
    excluded:added,unitCosts:{for(final p in products) p.id:p.data()['purchasePrice'] as num?},
    stockStreamFor:invoiceMainStock,
  );

class StaffCustomers extends StatefulWidget {
  final bool canViewBalance,canViewStatement,canAddCustomer;
  const StaffCustomers({super.key,this.canViewBalance=true,this.canViewStatement=false,this.canAddCustomer=false});
  @override
  State<StaffCustomers> createState() => _StaffCustomersState();
}
class _StaffCustomersState extends State<StaffCustomers> {
  String query = '';
  Future<void> addCustomer() async {
    final created = await createInvoiceParty(context, 'customers', false);
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إضافة العميل')));
    }
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    if (widget.canAddCustomer) Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: SizedBox(width: double.infinity,
      child: FilledButton.icon(onPressed: addCustomer, icon: const Icon(Icons.person_add), label: const Text('إضافة عميل جديد')))),
    Padding(padding: const EdgeInsets.all(12), child: TextField(decoration: const InputDecoration(labelText: 'بحث عن عميل بالاسم أو الهاتف', prefixIcon: Icon(Icons.search)),
      onChanged: (value) => setState(() => query = value.trim().toLowerCase()))),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('customers').snapshots(), builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('تعذر تحميل العملاء'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data!.docs.where((d) => d.data()['active'] != false && '${d.data()['name'] ?? ''} ${d.data()['phone'] ?? ''}'.toLowerCase().contains(query)).toList();
      if (rows.isEmpty) return const Center(child: Text('لا يوجد عملاء مطابقون'));
      return ListView.builder(itemCount: rows.length, itemBuilder: (context, index) {
        final data = rows[index].data();
        final balance=(data['balance'] as num?) ?? 0;
        return ListTile(title: Text('${data['name'] ?? ''}',style:const TextStyle(color:Colors.lightBlueAccent,fontWeight:FontWeight.bold)),
          subtitle: Text('الهاتف: ${data['phone'] ?? 'غير مسجل'}',style:const TextStyle(color:Colors.redAccent)),
          trailing: Wrap(crossAxisAlignment:WrapCrossAlignment.center,children:[
            if(widget.canViewBalance)Text('المتبقي: ${balance.toStringAsFixed(2)} ج.م',style:const TextStyle(color:Colors.greenAccent,fontWeight:FontWeight.bold)),
            if(widget.canViewStatement)IconButton(tooltip:'كشف حساب من تاريخ إلى تاريخ',icon:const Icon(Icons.summarize_outlined),
              onPressed:()=>openVibReport(context,'كشف حساب العميل ${data['name'] ?? ''}',
                AccountStatementPage(collection:'customers',id:rows[index].id))),
          ]));
      });
    })),
  ]);
}

void openStaffChat(BuildContext context, {required bool owner, String initialDraft = ''}) {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(
    textDirection: TextDirection.rtl,
    child: owner ? const StaffChatInbox() : StaffChatPage(employeeId: uid, owner: false, title: 'محادثة المدير', initialDraft: initialDraft),
  )));
}

class ChatShortcut extends StatelessWidget {
  final bool owner;
  final bool showLabel;
  final String initialDraft;
  const ChatShortcut({super.key, required this.owner, this.showLabel = false, this.initialDraft = ''});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    Widget button(bool unread) {
      final icon = Stack(clipBehavior:Clip.none,children:[
        const Icon(Icons.chat_bubble_outline,color:gold),
        if(unread)const Positioned(top:-7,right:-8,child:Icon(Icons.notifications_active,size:16,color:Colors.lightBlueAccent)),
      ]);
      return showLabel
          ? TextButton.icon(onPressed: () => openStaffChat(context, owner: owner, initialDraft: initialDraft), icon: icon,
              label: Text(owner ? 'محادثات الموظفين' : 'محادثة المدير'))
          : IconButton(tooltip: owner ? 'محادثات الموظفين' : 'محادثة المدير', icon: icon,
              onPressed: () => openStaffChat(context, owner: owner));
    }
    bool unread(Map<String, dynamic>? data) {
      if (data == null || data['lastSenderRole'] == (owner ? 'owner' : 'employee')) return false;
      final sent = data['lastMessageAt'] as Timestamp?;
      final seen = data[owner ? 'ownerReadAt' : 'employeeReadAt'] as Timestamp?;
      return sent != null && (seen == null || sent.compareTo(seen) > 0);
    }
    if (owner) return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('staffChats').snapshots(),
      builder: (context, snapshot) => button(snapshot.data?.docs.any((d) => unread(d.data())) ?? false));
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: db.collection('staffChats').doc(uid).snapshots(),
      builder: (context, snapshot) => button(unread(snapshot.data?.data())));
  }
}

class StaffChatInbox extends StatelessWidget {
  const StaffChatInbox({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('محادثات الموظفين'),actions:const [ChatAlertsButton()]),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('users').where('role', isEqualTo: 'employee').snapshots(),
      builder: (context, employees) {
        if (employees.hasError) return const Center(child: Text('تعذر تحميل الموظفين'));
        if (!employees.hasData) return const Center(child: CircularProgressIndicator());
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('staffChats').snapshots(), builder: (context, chats) {
          if (chats.hasError) return const Center(child: Text('تعذر تحميل المحادثات؛ راجع صلاحيات المحادثة'));
          if (!chats.hasData) return const Center(child: CircularProgressIndicator());
          final threads = {for (final d in chats.data!.docs) d.id: d.data()};
          final rows = employees.data!.docs.where((d) => d.data()['active'] == true).toList()
            ..sort((a, b) => ((threads[b.id]?['lastMessageAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
              .compareTo((threads[a.id]?['lastMessageAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
          if (rows.isEmpty) return const Center(child: Text('لا يوجد موظفون مفعلون بعد'));
          return ListView.builder(itemCount: rows.length, itemBuilder: (context, index) {
            final employee = rows[index], thread = threads[employee.id];
            final sent = thread?['lastMessageAt'] as Timestamp?, seen = thread?['ownerReadAt'] as Timestamp?;
            final unread = thread?['lastSenderRole'] == 'employee' && sent != null && (seen == null || sent.compareTo(seen) > 0);
            final name = '${employee.data()['name'] ?? employee.data()['phone'] ?? employee.id}';
            return Card(child: ListTile(
              leading: Stack(clipBehavior:Clip.none,children:[
                const Icon(Icons.person_outline,color:gold),
                if(unread)const Positioned(top:-7,right:-8,child:Icon(Icons.notifications_active,size:16,color:Colors.lightBlueAccent)),
              ]),
              title: Text(name), subtitle: Text('${thread?['lastText'] ?? 'ابدأ محادثة مع الموظف'}', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl,
                child: StaffChatPage(employeeId: employee.id, owner: true, title: name)))),
            ));
          });
        });
      },
    ),
  );
}

String chatProblem(Object? error) {
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') return 'Firebase رفض صلاحيات المحادثة (permission-denied). يلزم نشر قواعد المحادثة والتأكد من تفعيل الحساب.';
    if (error.code == 'unavailable') return 'خدمة المحادثة غير متاحة حاليًا؛ راجع الإنترنت وحاول مرة أخرى (unavailable).';
    if (error.code == 'unauthenticated') return 'جلسة الدخول انتهت؛ سجّل الدخول مرة أخرى (unauthenticated).';
    return 'تعذر الاتصال بالمحادثة: ${error.code}';
  }
  return 'تعذر إكمال المحادثة: $error';
}

class ChatVoicePlayer extends StatefulWidget {
  final String encoded;
  final int seconds;
  const ChatVoicePlayer({super.key,required this.encoded,required this.seconds});
  @override State<ChatVoicePlayer> createState() => _ChatVoicePlayerState();
}
class _ChatVoicePlayerState extends State<ChatVoicePlayer> {
  AudioPlayer? player;
  File? audioFile;
  StreamSubscription<void>? completed;
  bool playing = false, busy = false;
  @override void dispose() { completed?.cancel(); player?.dispose(); final file = audioFile; if(file != null) file.exists().then((exists) { if(exists) file.delete(); }); super.dispose(); }
  Future<void> toggle() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (playing) { await player!.pause(); if(mounted) setState(() => playing = false); }
      else {
        if (player == null) {
          player = AudioPlayer();
          completed = player!.onPlayerComplete.listen((_) { if(mounted) setState(() => playing = false); });
          final dir = await getTemporaryDirectory();
          audioFile = File('${dir.path}/vib-play-${DateTime.now().microsecondsSinceEpoch}.m4a');
          await audioFile!.writeAsBytes(base64Decode(widget.encoded));
        }
        await player!.play(DeviceFileSource(audioFile!.path));
        if(mounted) setState(() => playing = true);
      }
    } catch(e) { if(mounted) await showInvoiceSaveProblem(context,'تعذر تشغيل الصوت: $e',title:'تشغيل الصوت',button:'تمام'); }
    finally { if(mounted) setState(() => busy = false); }
  }
  @override Widget build(BuildContext context) => Row(mainAxisSize:MainAxisSize.min,children:[
    IconButton(tooltip:playing ? 'إيقاف الصوت' : 'تشغيل الرسالة الصوتية',onPressed:busy ? null : toggle,icon:Icon(playing ? Icons.pause_circle : Icons.play_circle,color:gold)),
    Flexible(child:Text('رسالة صوتية • ${widget.seconds} ثانية')),
  ]);
}

class StaffChatPage extends StatefulWidget {
  final String employeeId, title, initialDraft;
  final bool owner;
  const StaffChatPage({super.key, required this.employeeId, required this.owner, required this.title, this.initialDraft = ''});
  @override
  State<StaffChatPage> createState() => _StaffChatPageState();
}
class _StaffChatPageState extends State<StaffChatPage> with WidgetsBindingObserver {
  AudioRecorder? recorder;
  Timer? recordingTimer;
  bool recording = false, recordingBusy = false;
  int recordingSeconds = 0;
  String? audioDraft;
  int audioSeconds = 0;

  Future<void> toggleRecording() async {
    if (sending || recordingBusy) return;
    setState(() => recordingBusy = true);
    try {
      if (recording) {
        recordingTimer?.cancel();
        final path = await recorder!.stop();
        final duration = recordingSeconds.clamp(1,60).toInt();
        if (path == null) throw StateError('لم يتم تسجيل الصوت');
        final file = File(path), bytes = await File(path).readAsBytes();
        await file.delete();
        if (bytes.isEmpty || bytes.length > 600000) throw StateError('حجم التسجيل غير مناسب؛ سجل مرة أخرى');
        if (mounted) setState(() { recording = false; audioDraft = base64Encode(bytes); audioSeconds = duration; });
      } else {
        recorder ??= AudioRecorder();
        if (!await recorder!.hasPermission()) throw StateError('اسمح للتطبيق باستخدام الميكروفون من إعدادات الهاتف');
        final dir = await getTemporaryDirectory();
        await recorder!.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 16000, numChannels: 1), path: '${dir.path}/vib-record-${DateTime.now().microsecondsSinceEpoch}.m4a');
        if (!mounted) { await recorder!.cancel(); return; }
        setState(() { recording = true; recordingSeconds = 0; });
        recordingTimer = Timer.periodic(const Duration(seconds:1), (_) {
          if (!mounted) return;
          setState(() => recordingSeconds++);
          if (recordingSeconds >= 60) toggleRecording();
        });
      }
    } catch(e) {
      recordingTimer?.cancel();
      await recorder?.cancel();
      if (mounted) { setState(() => recording = false); await showInvoiceSaveProblem(context,'تعذر التسجيل: $e',title:'تسجيل الصوت',button:'تمام'); }
    } finally { if (mounted) setState(() => recordingBusy = false); }
  }


  late final TextEditingController message;
  bool sending = false;
  Timestamp? lastMarked;
  DocumentReference<Map<String, dynamic>>? pendingRef;
  String? pendingText;
  DocumentReference<Map<String, dynamic>> get thread => db.collection('staffChats').doc(widget.employeeId);
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); message = TextEditingController(text: widget.initialDraft); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if(state != AppLifecycleState.resumed && recording && !recordingBusy) toggleRecording(); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); recordingTimer?.cancel(); recorder?.dispose(); message.dispose(); super.dispose(); }

  Future<void> markRead(Timestamp? date) async {
    if (date == null || lastMarked == date) return;
    lastMarked = date;
    try { await thread.set({widget.owner ? 'ownerReadAt' : 'employeeReadAt': date}, SetOptions(merge: true)); }
    catch (_) { if (lastMarked == date) lastMarked = null; }
  }

  Future<void> send() async {
    final audio = audioDraft;
    final text = audio == null ? message.text.trim() : 'رسالة صوتية';
    if (sending || recording || recordingBusy || text.isEmpty) return;
    if (text.length > 2000) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرسالة بحد أقصى 2000 حرف'))); return; }
    if (pendingRef == null || pendingText != (audio ?? text)) { pendingRef = thread.collection('messages').doc(); pendingText = audio ?? text; }
    final ref = pendingRef!;
    setState(() => sending = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await db.runTransaction((tx) async {
        final prior = await tx.get(ref);
        if (prior.exists) {
          if (prior.data()?['senderId'] != uid || prior.data()?['text'] != text || prior.data()?['audioBase64'] != audio) throw Exception('راجع الرسالة قبل إعادة الإرسال');
          return;
        }
        final sender = (await tx.get(db.collection('users').doc(uid))).data();
        final employee = (await tx.get(db.collection('users').doc(widget.employeeId))).data();
        if (sender?['active'] != true || employee?['active'] != true || employee?['role'] != 'employee') throw Exception('الحساب غير مفعل');
        final role = '${sender?['role'] ?? ''}';
        if (role != 'owner' && (role != 'employee' || uid != widget.employeeId)) throw Exception('المحادثة غير مسموحة لهذا الحساب');
        final now = FieldValue.serverTimestamp();
        tx.set(ref, {'senderId': uid, 'senderName': '${sender?['name'] ?? ''}', 'senderRole': role, 'text': text, if(audio != null) 'audioBase64': audio, if(audio != null) 'audioSeconds': audioSeconds, if(audio != null) 'audioMime': 'audio/mp4', 'createdAt': now});
        tx.set(thread, {'employeeId': widget.employeeId, 'employeeName': '${employee?['name'] ?? ''}', 'branchId': '${employee?['branchId'] ?? ''}',
          'lastMessageId': ref.id, 'lastText': text, 'lastSenderId': uid, 'lastSenderRole': role, 'lastMessageAt': now}, SetOptions(merge: true));
      });
      if (!mounted) return;
      if(audio == null) message.clear(); setState(() { audioDraft = null; audioSeconds = 0; }); pendingRef = null; pendingText = null;
    } catch (e) {
      if (mounted) await showInvoiceSaveProblem(context,chatProblem(e),title:'المحادثة',button:'تمام');
    } finally { if (mounted) setState(() => sending = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title),actions:const [ChatAlertsButton()]),
    body: Column(children: [
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: thread.collection('messages').orderBy('createdAt', descending: true).limit(50).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(chatProblem(snapshot.error), textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: () async { await FirebaseAuth.instance.currentUser?.getIdToken(true); if(mounted) setState(() {}); }, child: const Text('إعادة المحاولة'))])));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!.docs;
          if (rows.isEmpty) return const Center(child: Text('اكتب رسالتك لبدء المحادثة'));
          final latest = rows.first.data()['createdAt'] as Timestamp?;
          WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && ModalRoute.of(context)?.isCurrent == true) markRead(latest); });
          return ListView.builder(reverse: true, padding: const EdgeInsets.all(12), itemCount: rows.length, itemBuilder: (context, index) {
            final data = rows[index].data();
            final mine = data['senderId'] == FirebaseAuth.instance.currentUser!.uid;
            return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .85),
              margin: const EdgeInsets.symmetric(vertical: 5), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: mine ? const Color(0xFF463A20) : const Color(0xFF222222), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${data['senderName'] ?? ''}${data['senderRole'] == 'owner' ? ' • المدير' : ''}', style: const TextStyle(color: gold, fontSize: 12)),
                const SizedBox(height: 5), if(data['audioBase64'] is String) ChatVoicePlayer(key: ValueKey(rows[index].id), encoded:data['audioBase64'], seconds:(data['audioSeconds'] as num?)?.toInt() ?? 0) else SelectableText('${data['text'] ?? ''}'),
                const SizedBox(height: 5), Text(formatDate(data['createdAt']), style: const TextStyle(fontSize: 10, color: Colors.white60)),
              ]),
            ));
          });
        },
      )),
      if(recording) Row(mainAxisAlignment:MainAxisAlignment.center,children:[Text('جارٍ التسجيل: $recordingSeconds / 60 ثانية',style:const TextStyle(color:Colors.red)),TextButton(onPressed:recordingBusy ? null : () async { recordingTimer?.cancel(); await recorder?.cancel(); if(mounted) setState(() => recording=false); },child:const Text('إلغاء التسجيل'))]),
      if(audioDraft != null) Row(children:[Expanded(child:ChatVoicePlayer(key:ValueKey(audioDraft),encoded:audioDraft!,seconds:audioSeconds)),IconButton(tooltip:'حذف التسجيل',onPressed:sending ? null : () => setState(() {audioDraft=null;audioSeconds=0;}),icon:const Icon(Icons.delete_outline))]),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(10), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: TextField(controller: message, enabled: !sending && !recording && audioDraft == null, minLines: 1, maxLines: 5, maxLength: 2000,
          decoration: const InputDecoration(hintText: 'اكتب رسالتك هنا…', border: OutlineInputBorder(), counterText: ''))),
        const SizedBox(width: 4), IconButton(tooltip: recording ? 'إيقاف التسجيل' : 'تسجيل رسالة صوتية', onPressed:sending || recordingBusy || audioDraft != null ? null : toggleRecording, icon:Icon(recording ? Icons.stop_circle : Icons.mic,color:recording ? Colors.red : gold)),
        IconButton.filled(tooltip: 'إرسال الرسالة', onPressed: sending || recording || recordingBusy ? null : send,
          icon: sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send)),
      ]))),
    ]),
  );
}

List<Map<String, dynamic>> saleItems(Map<String, dynamic> sale) =>
  sale['items'] is List && (sale['items'] as List).isNotEmpty
    ? (sale['items'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList()
    : [{'productId': sale['productId'], 'productName': sale['productName'], 'quantity': sale['quantity'],
        'unitPrice': sale['unitPrice'], 'lineTotal': sale['total'], 'purchasePriceAtSale': sale['purchasePriceAtSale'] ?? 0}];

Future<void> editSaleByNumber(BuildContext context) => findInvoiceForEdit(context, 'sales');

Future<void> assertSaleEditable(Map<String, dynamic> data) async {
  if(data['onlinePaymentEver']==true)throw StateError('الفاتورة لها سداد بالكارت؛ أنشئ فاتورة جديدة');
  if (invoiceHasLinkedVoucher(data)) throw Exception('الفاتورة مرتبطة بسند قبض ولا يمكن تعديلها');
  final customerId = '${data['customerId'] ?? ''}';
  if (customerId.isEmpty) return;
  final receipts = await db.collection('receipts').where('customerId', isEqualTo: customerId).get(const GetOptions(source:Source.server));
  final date = data['createdAt'] as Timestamp?;
  for (final receipt in receipts.docs) {
    final r = receipt.data(), receiptDate = receipt.data()['createdAt'] as Timestamp?;
    if (r['invoiceId'] == data['id'] ||
        ('${r['invoiceId'] ?? ''}'.isEmpty && (date == null || receiptDate == null || receiptDate.compareTo(date) >= 0))) {
      throw Exception('الفاتورة مرتبطة بسند قبض؛ السندات القديمة غير المحددة لفاتورة تحتاج مراجعة المدير');
    }
  }
}

// Amounts are integer cents. Remove only this invoice's old debt, then apply its new debt.
Map<String,int> saleCorrectionAccountDeltas(String oldCustomer,String newCustomer,int oldDue,int newDue) {
  if(oldDue<0 || newDue<0 || (oldDue>0 && oldCustomer.isEmpty) || (newDue>0 && newCustomer.isEmpty))
    throw StateError('الفاتورة الآجلة تحتاج حساب عميل');
  final result=<String,int>{};
  if(oldCustomer.isNotEmpty) result[oldCustomer]=-oldDue;
  if(newCustomer.isNotEmpty) result[newCustomer]=(result[newCustomer] ?? 0)+newDue;
  return result;
}

Future<void> replaceSaleLocally(String id, int revision, String requestId,
    List<Map<String, dynamic>> replacements, double payment, {String? correctedCustomerId}) async {
  int cents(num value) => (value * 100).round();
  final actor = FirebaseAuth.instance.currentUser!.uid;
  final ref = db.collection('sales').doc(id), edit = db.collection('invoiceEdits').doc(requestId);
  final key = jsonEncode({'id': id, 'revision': revision, 'items': replacements, 'paid': payment, 'customerId':correctedCustomerId});
  final preflight = (await ref.get()).data();
  if (preflight == null) throw Exception('رقم الفاتورة غير موجود');
  await assertSaleEditable({...preflight, 'id': id});
  await db.runTransaction((tx) async {
    final profile = (await tx.get(db.collection('users').doc(actor))).data();
    if (profile?['role'] != 'owner' || profile?['active'] != true) throw Exception('تعديل الفاتورة متاح للمدير فقط');
    final saved = (await tx.get(edit)).data();
    if (saved != null) {
      if (saved['requestKey'] != key || saved['actorId'] != actor) throw Exception('طلب تعديل مختلف');
      return;
    }
    final old = (await tx.get(ref)).data();
    if (old == null || old['status'] != 'completed' || (old['revision'] ?? 0) != revision) throw Exception('الفاتورة غير متاحة أو اتعدلت؛ افتحها من جديد');
    if(old['onlinePaymentEver']==true)throw StateError('الفاتورة لها سداد بالكارت؛ أنشئ فاتورة جديدة');
    if (invoiceHasLinkedVoucher(old)) throw Exception('الفاتورة مرتبطة بسند قبض');
    if (old['paid'] is! num || old['due'] is! num || cents(old['total']) - cents(old['paid']) != cents(old['due'])) throw Exception('الفاتورة القديمة تحتاج مراجعة المدفوع والباقي');
    final oldCustomerId = '${old['customerId'] ?? ''}';
    final customerId=correctedCustomerId ?? oldCustomerId;
    final partyChanged=customerId!=oldCustomerId;
    final oldCustomerRef=oldCustomerId.isEmpty ? null : db.collection('customers').doc(oldCustomerId);
    final oldCustomer=oldCustomerRef==null ? null : (await tx.get(oldCustomerRef)).data();
    final customerRef = customerId.isEmpty ? null : db.collection('customers').doc(customerId);
    final customer = partyChanged ? (customerRef == null ? null : (await tx.get(customerRef)).data()) : oldCustomer;
    if(partyChanged && (customer==null || customer['active']==false)) throw StateError('اختر عميلًا مسجلًا ونشطًا');
    final latestReceiptId = '${oldCustomer?['lastReceiptId'] ?? ''}';
    if (latestReceiptId.isNotEmpty) {
      final receipt = (await tx.get(db.collection('receipts').doc(latestReceiptId))).data();
      final at = receipt?['createdAt'] as Timestamp?, created = old['createdAt'] as Timestamp?;
      if (receipt != null && (receipt['invoiceId'] == id || ('${receipt['invoiceId'] ?? ''}'.isEmpty &&
          (at == null || created == null || at.compareTo(created) >= 0)))) throw Exception('يوجد سند قبض مرتبط بالفاتورة أو برصيد العميل قبل تحديد الفواتير');
    }
    final cashRef = db.collection('settings').doc('cash');
    final cash = (await tx.get(cashRef)).data();
    final original = saleItems(old), oldQuantities = <String, int>{};
    for (final item in original) {
      final p = '${item['productId']}'; oldQuantities[p] = (oldQuantities[p] ?? 0) + (item['quantity'] as num).toInt();
    }
    final ids = {...oldQuantities.keys, ...replacements.map((x) => '${x['productId']}')};
    final stockBranch = '${old['stockBranchId'] ?? old['branchId']}';
    final stocks = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    final products = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final p in ids) {
      stocks[p] = await tx.get(db.collection('stock').doc('${stockBranch}_$p'));
      products[p] = await tx.get(db.collection('products').doc(p));
    }
    final items = <Map<String, dynamic>>[], newQuantities = <String, int>{};
    var total = 0;
    for (final line in replacements) {
      final p = '${line['productId']}', product = products[p]!.data();
      final q = line['quantity'] as int, price = cents(line['unitPrice']);
      if (product == null || q <= 0 || q > 1000000 || price < 0 || newQuantities.containsKey(p)) throw Exception('راجع الأصناف والأسعار والكميات');
      if (product['active'] != true && !oldQuantities.containsKey(p)) throw Exception('الصنف غير نشط');
      final prior = original.where((x) => x['productId'] == p).toList();
      final unchangedPrice=prior.isNotEmpty && prior.every((x)=>cents(x['unitPrice'])==price);
      if (!unchangedPrice && price < cents((product['purchasePrice'] as num?) ?? 0)) throw Exception('سعر البيع أقل من التكلفة');
      newQuantities[p] = q; total += q * price;
      items.add({'productId': p, 'productName': product['name'], 'quantity': q, 'unitPrice': price / 100,
        'lineTotal': q * price / 100, 'purchasePriceAtSale': prior.isEmpty ? product['purchasePrice'] ?? 0 : prior.first['purchasePriceAtSale'] ?? 0});
    }
    final paid = cents(payment), due = total - paid;
    if (items.isEmpty || items.length > 50 || total > 1000000000000 || !payment.isFinite || paid < 0 || due < 0) throw Exception('راجع المدفوع وبنود الفاتورة');
    if (due > 0 && (customer == null || customer['active'] == false)) throw Exception('الفاتورة الآجلة تحتاج عميلًا نشطًا');
    final deltas=saleCorrectionAccountDeltas(oldCustomerId,customerId,cents(old['due']),due);
    final debtDelta = deltas[customerId] ?? 0, cashDelta = paid - cents(old['paid']);
    final cashBefore = cents((cash?['balance'] as num?) ?? 0), balanceBefore = cents((customer?['balance'] as num?) ?? 0);
    if(cents(old['due'])>0 && oldCustomer==null) throw StateError('حساب العميل السابق غير موجود؛ راجع الفاتورة');
    for (final p in ids) {
      final before = (stocks[p]!.data()?['quantity'] as num?)?.toInt() ?? 0;
      final delta = (oldQuantities[p] ?? 0) - (newQuantities[p] ?? 0), after = before + delta;
      if (delta < 0 && after < 0) throw Exception('المخزون غير كافٍ للصنف ${products[p]!.data()?['name']}');
      if (delta == 0) continue;
      tx.set(stocks[p]!.reference, {'branchId': stockBranch, 'productId': p, 'quantity': after, 'lastSaleId': id}, SetOptions(merge: true));
      tx.set(db.collection('stockMovements').doc('${requestId}_$p'), {'productId': p, 'productName': products[p]!.data()?['name'],
        'branchId': stockBranch, 'kind': 'saleCorrection', 'quantity': delta, 'balanceAfter': after,
        'referenceId': id, 'editId': requestId, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
    }
    for(final entry in deltas.entries) {
      if(entry.value==0) continue;
      final account=entry.key==customerId ? customer : oldCustomer;
      final before=cents((account?['balance'] as num?) ?? 0);
      tx.update(db.collection('customers').doc(entry.key), {'balance':(before+entry.value)/100,'updatedAt':FieldValue.serverTimestamp()});
      tx.set(db.collection('accountMovements').doc('${requestId}_${entry.key==customerId ? 'customer' : 'previousCustomer'}'), {
        'accountType':'customers','accountId':entry.key,'accountName':account?['name'] ?? '',
        'kind':'saleCorrection','amount':entry.value/100,'balanceBefore':before/100,'balanceAfter':(before+entry.value)/100,
        'referenceId':id,'editId':requestId,'reason':partyChanged ? 'تصحيح عميل فاتورة المبيعات' : 'تصحيح فاتورة مبيعات',
        'actorId':actor,'createdAt':FieldValue.serverTimestamp()});
    }
    if (cashDelta != 0) {
      tx.set(cashRef, {'balance': (cashBefore + cashDelta) / 100, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      tx.set(db.collection('accountMovements').doc('${requestId}_cash'), {'accountType': 'cash', 'accountId': customerId,
        'accountName': customer?['name'] ?? '', 'kind': 'saleCorrection', 'amount': cashDelta.abs() / 100, 'delta': cashDelta / 100,
        'balanceBefore': cashBefore / 100, 'balanceAfter': (cashBefore + cashDelta) / 100,
        'referenceId': id, 'editId': requestId, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
    }
    tx.update(ref, {'items': items, 'itemCount': items.length, 'stockIndex': {for (var i = 0; i < items.length; i++) '${items[i]['productId']}': i},
      'total': total / 100, 'paid': paid / 100, 'due': due / 100, 'paymentStatus': due > 0 ? 'credit' : 'cash',
      'revision': revision + 1, 'updatedAt': FieldValue.serverTimestamp(), 'lastEditedBy': actor,
      if(partyChanged) 'customerId':customerId,
      if(partyChanged) 'customerName':customer?['name'] ?? '',
      if(partyChanged) 'customerPhone':customer?['phone'] ?? '',
      if(partyChanged) 'customerPreviousBalance':balanceBefore/100,
      'customerBalanceAfter': customer == null ? 0 : (balanceBefore + debtDelta) / 100,
      'productId': items.length == 1 ? items.first['productId'] : '', 'productName': items.length == 1 ? items.first['productName'] : '',
      'quantity': items.length == 1 ? items.first['quantity'] : 0, 'unitPrice': items.length == 1 ? items.first['unitPrice'] : 0});
    tx.set(edit, {'invoiceId': id, 'invoiceType': 'sales', 'beforeItems': original, 'afterItems': items,
      'customerIdBefore':oldCustomerId,'customerIdAfter':customerId,
      'customerNameBefore':old['customerName'] ?? '', 'customerNameAfter':customer?['name'] ?? '',
      'totalBefore': old['total'], 'totalAfter': total / 100, 'paidBefore': old['paid'], 'paidAfter': paid / 100,
      'revision': revision + 1, 'requestKey': key, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
  });
}

bool unallocatedReceiptAfter(Map<String, dynamic> invoice, Map<String, dynamic> receipt) {
  if ('${receipt['invoiceId'] ?? ''}'.isNotEmpty) return false;
  final created = invoice['createdAt'] as Timestamp?, at = receipt['createdAt'] as Timestamp?;
  return created == null || at == null || at.compareTo(created) >= 0;
}

Future<void> assertNoUnallocatedReceipt(Map<String, dynamic> invoice) async {
  final customerId = '${invoice['customerId'] ?? ''}';
  if (customerId.isEmpty) return;
  final receipts = await db.collection('receipts').where('customerId', isEqualTo: customerId).get();
  if (receipts.docs.any((r) => unallocatedReceiptAfter(invoice, r.data()))) {
    throw Exception('يوجد سند قبض عام بعد الفاتورة؛ حدد الفواتير الخاصة به قبل المرتجع');
  }
}
