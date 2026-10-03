import 'invoice_serial_core.dart';
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
part 'product_import.dart';
part 'inventory_tools.dart';
part 'online_payments.dart';
part 'invoice_history.dart';
part 'invoice_serials.dart';

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

Future<FirebaseOptions> _firebaseOptionsForThisApp() async {
  final packageName = (await PackageInfo.fromPlatform()).packageName;
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
  return Firebase.initializeApp(options: options);
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
final db = FirebaseFirestore.instance;
Timestamp? activeResetAt;

bool visibleAfterReset(Map<String, dynamic> data) {
  final resetAt = activeResetAt;
  if (resetAt == null) return true;
  final createdAt = data['createdAt'];
  if (createdAt is! Timestamp) return false;
  return createdAt.compareTo(resetAt) >= 0;
}

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
          final home = Home(key:ValueKey('${auth.data!.uid}:${data['role']}'), uid: auth.data!.uid, role: data['role'] as String, branchId: (data['branchId'] ?? '') as String, name: (data['name'] ?? '') as String);
          return data['role'] == 'owner' ? OwnerSecurity(child: home) : home;
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

const managerNavy = Color(0xFF101E33);
const managerSurface = Color(0xFF192D45);
const managerBorder = Color(0xFF30445D);
ThemeData managerTheme(BuildContext context) => Theme.of(context).copyWith(
  scaffoldBackgroundColor: managerNavy,
  colorScheme: Theme.of(context).colorScheme.copyWith(surface: managerSurface, primary: gold),
  appBarTheme: const AppBarTheme(backgroundColor: managerNavy, foregroundColor: Colors.white, centerTitle: true, elevation: 0),
  cardTheme: const CardThemeData(color: managerSurface, elevation: 0),
);

class Home extends StatefulWidget {
  final String uid, role, branchId, name;
  const Home({super.key, required this.uid, required this.role, required this.branchId, required this.name});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int page = 0;
  @override void initState() { super.initState(); if(widget.role == 'owner') ChequeReminders.instance.watch(widget.uid); ChatAlerts.instance.watch(widget.uid,widget.role == 'owner'); }
  @override void dispose() { ChatAlerts.instance.stop(); if(widget.role == 'owner') ChequeReminders.instance.stop(); super.dispose(); }

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
          title: const Text('VIB', style: TextStyle(color: gold, fontWeight: FontWeight.w800, fontSize: 38, letterSpacing: 2)),
          leading: const ChatShortcut(owner: true),
          actions: [
            Padding(padding: const EdgeInsetsDirectional.only(end: 12), child: IconButton.filledTonal(
              tooltip: 'الضبط', style: IconButton.styleFrom(backgroundColor: managerSurface, foregroundColor: gold),
              onPressed: () => openPage('الضبط', const Management()), icon: const Icon(Icons.settings_outlined))),
          ],
        ),
        body: OwnerDashboard(uid: widget.uid, branchId: widget.branchId, openPage: openPage),
      ));
    }

    return Scaffold(
      appBar: AppBar(title: Text('VIB | ${widget.name}'), actions: [
        const ChatShortcut(owner: false),
        IconButton(tooltip: 'خروج', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout)),
      ]),
      body: page == 0
          ? Products(owner: false, uid: widget.uid, branchId: widget.branchId)
          : page == 1
              ? Sales(owner: false, branchId: widget.branchId)
              : page == 2
                  ? const StaffCustomers()
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
        Container(width: 66, height: 66, decoration: const BoxDecoration(color: Color(0xFF263B53), shape: BoxShape.circle),
          child: Icon(icon, color: gold, size: 34)),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(title, textAlign: TextAlign.center,
          maxLines: 2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18))),
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
              return InventoryProductCard(number: i + 1, name: '${p['name'] ?? ''}', quantity: quantity,
                quantityMessage: stock.hasError ? 'تعذر التحميل' : 'جارٍ التحميل', unitPrice: p['price'] as num?,
                onTap: () => productDetails(context, d.id), actions: owner ? [
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

Future<void> productDetails(BuildContext context, String productId) async {
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
          Text('${data['name'] ?? ''}', style: const TextStyle(color: gold, fontSize: 20)),
          const SizedBox(height: 12),
          Text('الفئة: ${data['category'] ?? 'غير مصنف'}'),
          const SizedBox(height: 8),
          Text('سعر الشراء: ${price(data['purchasePrice'])}'),
          const SizedBox(height: 8),
          Text('سعر البيع: ${price(data['price'])}'),
          const SizedBox(height: 8),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: db.collection('stock').doc('main_$productId').snapshots(),
            builder: (c, stock) {
              if (stock.hasError) return const Text('تعذر تحميل المخزون الرئيسي', style: TextStyle(color: Colors.redAccent));
              if (!stock.hasData) return const Text('جارٍ تحميل الكمية…');
              return Text('المتوفر في المخزون الرئيسي: ${(stock.data!.data()?['quantity'] as num?)?.toInt() ?? 0}');
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
      final selectedCustomer = customerId.isEmpty ? null : customersSnap.docs.firstWhere((d) => d.id == customerId);

      final previousBalance = (selectedCustomer?.data()['balance'] as num?)?.toDouble() ?? 0;
      void addSelected(String id) {
        if (saving || lines.length >= (owner ? 50 : 4) || lines.any((row) => row.productId == id)) return;
        final product=productDoc(id).data();
        update(() => lines.add(SaleLine(productId:id,unitPrice:(product['price'] as num?)?.toDouble() ?? 0)));
      }
      return InvoiceEditorFrame(
        title: checkout ? 'حفظ فاتورة المبيعات' : 'فاتورة مبيعات',checkout:checkout,total:previewTotal,
        headerAction:IgnorePointer(ignoring:saving,child:ChatShortcut(owner:owner)),
        toolbar:InvoiceProductsBar(
          unitCosts:{for(final product in products) product.id:product.data()['purchasePrice'] as num?},stockStreamFor:invoiceMainStock,
          products:[for(final product in products) if(!lines.any((row)=>row.productId == product.id))
            (id:product.id,name:'${product.data()['name'] ?? ''}')],
          enabled:!saving && lines.length < (owner ? 50 : 4),onSelect:addSelected,
          onSearch:() async {
            final id=await selectSaleProduct(c,products,lines.map((row)=>row.productId).whereType<String>().toSet());
            if(id != null && c.mounted) addSelected(id);
          },
        ),
        body:checkout ? ListView(children:[
          OutlinedButton.icon(icon:const Icon(Icons.person_search),
            label:Text(customerId.isEmpty ? 'اسم العميل — اختيار عميل' : '${selectedCustomer?.data()['name'] ?? ''}',softWrap:true),
            onPressed:saving ? null : () async {
              final id=await selectRegisteredCustomer(c);
              if(id == null || !c.mounted) return;
              final refreshed=await db.collection('customers').get();
              if(c.mounted) update(() {customersSnap=refreshed;customerId=id;});
            }),
          const SizedBox(height:10),
          PurchaseSettlementPanel(total:previewTotal,previousBalance:previousBalance,credit:credit,
            paid:paid,enabled:!saving,partyLabel:'العميل',
            onModeChanged:(value)=>update(() => credit=value),onChanged:()=>update(() {})),
          if(owner) ExpansionTile(title:const Text('صلاحيات المدير',style:TextStyle(fontSize:13)),children:[
            SwitchListTile(dense:true,title:const Text('السماح بالبيع رغم نقص الكمية'),value:allowShortage,onChanged:saving ? null : (v)=>update(()=>allowShortage=v)),
            SwitchListTile(dense:true,title:const Text('السماح بسعر أقل من التكلفة'),value:allowBelowCost,onChanged:saving ? null : (v)=>update(()=>allowBelowCost=v)),
            if(allowShortage || allowBelowCost) TextField(controller:reason,enabled:!saving,decoration:_vibInvoiceInput('سبب الاستثناء (إلزامي)')),
          ]),
        ]) : lines.isEmpty ? const Center(child:Text('اختر صنفًا من البحث أو القائمة')) : ListView(children:[
          for(var i=0;i<lines.length;i++) PurchaseInvoiceLine(
            key:ObjectKey(lines[i]),number:i+1,name:'${productDoc(lines[i].productId!).data()['name'] ?? ''}',
            cost:lines[i].price,quantity:lines[i].quantity,enabled:!saving,priceEditable:owner,
            onChanged:()=>update(() {}),onDelete:() {final row=lines.removeAt(i);row.dispose();update(() {});},
            onChoose:() async {
              final row=lines[i];
              final id=await selectSaleProduct(c,products,lines.where((other)=>other != row).map((other)=>other.productId).whereType<String>().toSet());
              if(id == null || !c.mounted) return;
              update(() {row.productId=id;row.price.text=((productDoc(id).data()['price'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);});
            },
          ),
        ]),
        actions: [
          TextButton(onPressed:saving ? null : () {if(checkout) {update(()=>checkout=false);} else {Navigator.pop(c);}},child:Text(checkout ? 'رجوع للبنود' : 'إلغاء')),
          FilledButton(onPressed: saving ? null : () async {
            FocusScope.of(c).unfocus();
            if (!owner && lines.length > 4) {
              await showInvoiceSaveProblem(c, 'فاتورة الموظف تقبل حتى 4 أصناف مختلفة لضمان حفظ المخزون والحسابات معًا. استخدم فاتورة أخرى لباقي الأصناف.');
              return;
            }
            if (lines.isEmpty) {
              await showInvoiceSaveProblem(c, 'أضف منتجًا واحدًا على الأقل قبل حفظ الفاتورة');
              return;
            }
            if (!checkout) {update(() => checkout=true);return;}
            final entries = <({String id, String name, int qty, double price, double? cost})>[];
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
              entries.add((id: id, name: '${p['name'] ?? ''}', qty: qty, price: price, cost: cost));
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
                final savedInvoice = await db.runTransaction<Map<String, dynamic>>((tx) async {
                final actor = FirebaseAuth.instance.currentUser!.uid;
                final actorProfile = (await tx.get(db.collection('users').doc(actor))).data();
                if (actorProfile?['active'] != true || (!owner && actorProfile?['role'] != 'employee')) {
                  throw Exception('الحساب غير مفعل');
                }
                final actualBranch = owner ? branchId : '${actorProfile?['branchId'] ?? ''}';
                if (actualBranch.isEmpty || (!owner && entries.length > 4)) {
                  throw Exception('فاتورة الموظف تقبل حتى 4 أصناف مختلفة');
                }
                final requestKey = jsonEncode({'customerId': customerId, 'credit': credit, 'paid': payment,
                  'items': entries.map((e) => {'id': e.id, 'qty': e.qty, 'price': e.price}).toList()});
                final priorSale = (await tx.get(saleRef)).data();
                if (priorSale != null) {
                  if (priorSale['employeeId'] != actor || priorSale['requestKey'] != requestKey) {
                    throw Exception('الفاتورة محفوظة بالفعل ببيانات مختلفة');
                  }
                  return priorSale;
                }
                final liveProducts = <String, Map<String, dynamic>>{};
                for (final e in entries) {
                  final product = (await tx.get(db.collection('products').doc(e.id))).data();
                  if (product == null || product['active'] != true) throw Exception('الصنف غير متاح');
                  if (!owner && (product['price'] as num?)?.toDouble() != e.price) {
                    throw Exception('سعر الصنف اتغير؛ افتح الفاتورة من جديد');
                  }
                  final cost = (product['purchasePrice'] as num?)?.toDouble();
                  if (cost != null && e.price < cost && !(owner && allowBelowCost)) {
                    throw Exception('سعر البيع أقل من التكلفة');
                  }
                  liveProducts[e.id] = product;
                }
                final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
                for (final e in entries) {
                  stockSnaps[e.id] = await tx.get(db.collection('stock').doc('main_${e.id}'));
                }

                DocumentSnapshot<Map<String, dynamic>>? customerSnap;
                if (customerId.isNotEmpty) customerSnap = await tx.get(db.collection('customers').doc(customerId));

                DocumentSnapshot<Map<String, dynamic>>? cashSnap;
                if (payment > 0) cashSnap = await tx.get(db.collection('settings').doc('cash'));

                final invoiceSerial=owner ? await readInvoiceSerial(tx,'sales',saleRef.id) : null;
                if(invoiceSerial!=null)writeInvoiceSerial(tx,invoiceSerial);
                final items = <Map<String, dynamic>>[];
                for (final e in entries) {
                  final current = (stockSnaps[e.id]?.data()?['quantity'] as num?)?.toInt() ?? 0;
                  if (current < e.qty && !(owner && allowShortage)) {
                    throw Exception('الكمية غير متاحة للصنف ${e.name}');
                  }
                  final after = current - e.qty;
                  final lineTotal = e.qty * e.price;

                  items.add({
                    'productId': e.id,
                    'productName': '${liveProducts[e.id]!['name']}',
                    'quantity': e.qty,
                    'unitPrice': e.price,
                    'lineTotal': lineTotal,
                    'purchasePriceAtSale': (liveProducts[e.id]!['purchasePrice'] as num?)?.toDouble() ?? 0,
                  });

                  tx.set(db.collection('stock').doc('main_${e.id}'), {
                    'branchId': 'main',
                    'productId': e.id,
                    'quantity': after,
                    'lastSaleId': saleRef.id,
                  }, SetOptions(merge: true));

                  tx.set(db.collection('stockMovements').doc('${saleRef.id}_${e.id}'), {
                    'productId': e.id,
                    'productName': '${liveProducts[e.id]!['name']}',
                    'branchId': 'main',
                    'kind': 'sale',
                    'quantity': -e.qty,
                    'balanceAfter': after,
                    'referenceId': saleRef.id,
                    'actorId': actor,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }

                double previousCustomerBalance = 0;
                double customerBalanceAfter = 0;
                String customerName = '';
                String customerPhone = '';

                if (customerId.isNotEmpty) {
                  if (customerSnap == null || !customerSnap.exists || customerSnap.data()?['active'] == false) throw Exception('العميل غير موجود أو غير نشط');
                  previousCustomerBalance = (customerSnap.data()?['balance'] as num?)?.toDouble() ?? 0;
                  customerBalanceAfter = previousCustomerBalance + due;
                  customerName = '${customerSnap.data()?['name'] ?? ''}';
                  customerPhone = '${customerSnap.data()?['phone'] ?? ''}';
                  if (due > 0) {
                    tx.update(db.collection('customers').doc(customerId), {
                      'balance': customerBalanceAfter,
                      'lastSaleId': saleRef.id,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    tx.set(db.collection('accountMovements').doc('${saleRef.id}_customer'), {
                      'accountType': 'customers',
                      'accountId': customerId,
                      'accountName': customerName,
                      'kind': 'sale',
                      'amount': due,
                      'balanceBefore': previousCustomerBalance,
                      'balanceAfter': customerBalanceAfter,
                      'referenceId': saleRef.id,
                      'createdAt': FieldValue.serverTimestamp(),
                      'actorId': actor,
                    });
                  }
                }

                if (payment > 0) {
                  final beforeCash = (cashSnap?.data()?['balance'] as num?)?.toDouble() ?? 0;
                  final afterCash = beforeCash + payment;
                  tx.set(db.collection('settings').doc('cash'), {
                    'balance': afterCash,
                    'lastSaleId': saleRef.id,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                  tx.set(db.collection('accountMovements').doc('${saleRef.id}_cash'), {
                    'accountType': 'cash',
                    'kind': 'sale',
                    'accountId': customerId,
                    'accountName': customerName,
                    'amount': payment,
                    'delta': payment,
                    'balanceBefore': beforeCash,
                    'balanceAfter': afterCash,
                    'referenceId': saleRef.id,
                    'reason': 'تحصيل فاتورة مبيعات',
                    'actorId': actor,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }

                final invoiceData = <String, dynamic>{
                  'id': saleRef.id,
                  if(invoiceSerial!=null)'internalNumber':invoiceSerial.data['internalNumber'],
                  if(invoiceSerial!=null)'invoiceBarcode':invoiceSerial.data['invoiceBarcode'],
                  'branchId': actualBranch,
                  'stockBranchId': 'main',
                  'requestKey': requestKey,
                  'stockIndex': {for (var i = 0; i < items.length; i++) items[i]['productId'] as String: i},
                  'cashBefore': (cashSnap?.data()?['balance'] as num?)?.toDouble() ?? 0,
                  'cashAfter': ((cashSnap?.data()?['balance'] as num?)?.toDouble() ?? 0) + payment,
                  'employeeId': actor,
                  'customerId': customerId,
                  'customerName': customerName,
                  'customerPhone': customerPhone,
                  'customerPreviousBalance': previousCustomerBalance,
                  'customerBalanceAfter': customerBalanceAfter,
                  'items': items,
                  'itemCount': items.length,
                  'total': total,
                  'paid': payment,
                  'due': due,
                  'paymentStatus': due > 0 ? 'credit' : 'cash',
                  'status': 'completed',
                  'createdAt': FieldValue.serverTimestamp(),
                  if (items.length == 1) 'productId': items.first['productId'],
                  if (items.length == 1) 'productName': items.first['productName'],
                  if (items.length == 1) 'quantity': items.first['quantity'],
                  if (items.length == 1) 'unitPrice': items.first['unitPrice'],
                  if (owner && (allowShortage || allowBelowCost)) 'managerOverride': {
                    'reason': reason.text.trim(),
                    'allowShortage': allowShortage,
                    'allowBelowCost': allowBelowCost,
                    'actorId': actor,
                  },
                };
                tx.set(saleRef, invoiceData);
                return {...invoiceData, 'createdAt': Timestamp.now()};
                });

              if (c.mounted) Navigator.pop(c);
              if (context.mounted) await showInvoiceSavedActions(context, 'sales', saleRef.id, savedInvoice);
            } catch (e) {
              if (c.mounted) {
                update(() => saving = false);
                final message = invoiceSaveFailureMessage(e);
                await showInvoiceSaveProblem(c, message);
              }
            }
          }, child:saving ? const InvoiceSaveButtonLabel(saving:true) : Text(checkout ? 'تأكيد الحفظ' : 'إضافة')),
        ],
      );
    }),
  );

  for (final row in lines) { row.dispose(); }
  paid.dispose();
  reason.dispose();
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
  DateTime selectedDate = DateTime.now();
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
            date != null && date.year == selectedDate.year && date.month == selectedDate.month && date.day == selectedDate.day;
        })
        .toList()
      ..sort((a,b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(icon: const Icon(Icons.add_shopping_cart), label: const Text('فاتورة بيع جديدة'), onPressed: () => newSaleDialog(context, owner, branchId))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(icon: const Icon(Icons.calendar_month), label: const Text('فواتير المبيعات'), onPressed: () async {
          final date = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
          if (date != null && mounted) setState(() => selectedDate = date);
        }),
        TextButton(onPressed: () => setState(() => selectedDate = DateTime.now()), child: const Text('فواتير اليوم')),
        if (owner) OutlinedButton.icon(icon: const Icon(Icons.edit_note), label: const Text('تعديل فاتورة'), onPressed: () => editSaleByNumber(context)),
      ])),
      Padding(padding: const EdgeInsets.all(8), child: Text('فواتير ${selectedDate.day}/${selectedDate.month}/${selectedDate.year} • العدد: ${rows.length}')),
      Expanded(child: rows.isEmpty ? const Center(child: Text('لا توجد فواتير في هذا التاريخ')) : ListView(children: rows.map((d) {
        final sale = d.data();
        final rawItems = (sale['items'] as List?) ?? const [];
        final itemCount = rawItems.isNotEmpty ? rawItems.length : 1;
        final itemText = rawItems.isNotEmpty
            ? rawItems.take(3).map((e) => '${(e as Map)['productName'] ?? ''} × ${e['quantity'] ?? 0}').join(' • ')
            : '${sale['productName'] ?? ''} × ${sale['quantity'] ?? 0}';
        final paymentText = sale.containsKey('paid') ? ' • مدفوع ${sale['paid'] ?? 0} • باقي ${sale['due'] ?? 0}' : '';
        return Card(child: ListTile(
          title: Text('رقم الفاتورة: ${invoiceDisplayNumber('sales',d.id,sale)}\n$itemText${itemCount > 3 ? ' • +${itemCount - 3} أصناف' : ''}'),
          subtitle: Text('فرع: ${sale['branchId']} • ${formatDate(sale['createdAt'])}$paymentText${sale['status'] == 'returned' ? ' • مرتجع' : ''}'),
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

class Staff extends StatelessWidget {
  const Staff({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('users').snapshots(), builder: (context, snap) {
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    return ListView(children: snap.data!.docs.map((d) {
      final data = d.data();
      return ListTile(
        title: Text('${data['name'] ?? data['phone'] ?? d.id}'),
        subtitle: Text('${data['phone'] ?? ''} • ${data['role'] == 'pending' ? 'بانتظار التفعيل' : (data['branchId'] ?? 'المدير')}'),
        trailing: data['role'] == 'owner' ? const Icon(Icons.verified_user) :
          TextButton(onPressed: () => assignEmployee(context, d.id, data), child: const Text('تحديد الفرع')),
      );
    }).toList());
  });
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
    option(context, 'حركة المنتجات', Icons.swap_vert, const ItemMovementReport()),
    option(context, 'سجل حركات الحسابات', Icons.history, const AccountMovements()),
    option(context, 'الإعدادات والطباعة', Icons.settings_outlined, const AppSettings()),
    Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(color: const Color(0xFF30283B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF594051))),
      child: ListTile(leading: const Icon(Icons.restart_alt, color: Colors.redAccent),
        title: const Text('تصفير البرنامج', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_left, color: Colors.redAccent), onTap: () => resetProgram(context)))),
    ListTile(leading: const Icon(Icons.logout, color: Color(0xFFA7B8CE)), title: const Text('تسجيل الخروج'),
      onTap: () => FirebaseAuth.instance.signOut()),
  ]);
}

class InventoryAudit extends StatefulWidget {
  const InventoryAudit({super.key});
  @override State<InventoryAudit> createState() => _InventoryAuditState();
}

class Expenses extends StatelessWidget {
  const Expenses({super.key});
  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: () => expenseDialog(context), icon: const Icon(Icons.add), label: const Text('تسجيل مصروف'))),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('accountMovements').where('accountType', isEqualTo: 'expenses').snapshots(), builder: (context, snap) {
      if (snap.hasError) return const Center(child: Text('تعذر تحميل المصروفات'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snap.data!.docs.where((d) => visibleAfterReset(d.data())).toList()
        ..sort((a,b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
      final total = rows.fold<double>(0, (sum, row) => sum + ((row.data()['amount'] as num?)?.toDouble() ?? 0));
      return Column(children: [ListTile(title: const Text('إجمالي المصروفات المسجلة'), trailing: Text('${total.toStringAsFixed(2)} ج.م')), Expanded(child: ListView(children: rows.map((row) { final data = row.data(); return ListTile(title: Text('${data['reason'] ?? ''}'), subtitle: Text('${data['category'] ?? 'عام'} • ${formatDate(data['createdAt'])}'), trailing: Text('${data['amount']} ج.م')); }).toList()))]);
    }))]);
}

Future<void> expenseDialog(BuildContext context) async {
  final category = TextEditingController(), reason = TextEditingController(), amount = TextEditingController();
  await showDialog<void>(context: context, builder: (dialog) => AlertDialog(title: const Text('مصروف جديد'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
    TextField(controller: category, decoration: const InputDecoration(labelText: 'الفئة، مثل إيجار أو رواتب')),
    TextField(controller: reason, decoration: const InputDecoration(labelText: 'وصف المصروف')),
    TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ')),
  ])), actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إلغاء')), FilledButton(onPressed: () async {
    final value = double.tryParse(amount.text.trim());
    if (value == null || !value.isFinite || value <= 0 || reason.text.trim().isEmpty) return;
    try {
      await db.runTransaction((tx) async {
        final cashRef = db.collection('settings').doc('cash'), snap = await tx.get(cashRef);
        final before = (snap.data()?['balance'] as num?)?.toDouble() ?? 0;
        if (before < value) throw Exception('رصيد الصندوق غير كافٍ');
        final ref = db.collection('accountMovements').doc();
        tx.set(cashRef, {'balance': before - value, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        tx.set(ref, {'accountType': 'expenses', 'category': category.text.trim().isEmpty ? 'عام' : category.text.trim(), 'reason': reason.text.trim(), 'amount': value, 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
        tx.set(db.collection('accountMovements').doc(), {'accountType': 'cash', 'kind': 'expense', 'accountId': ref.id, 'accountName': category.text.trim(), 'amount': value, 'delta': -value, 'balanceBefore': before, 'balanceAfter': before - value, 'reason': reason.text.trim(), 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
      });
      if (dialog.mounted) Navigator.pop(dialog);
    } catch (e) { if (dialog.mounted) ScaffoldMessenger.of(dialog).showSnackBar(SnackBar(content: Text('تعذر حفظ المصروف: $e'))); }
  }, child: const Text('حفظ المصروف'))]));
}

class _InventoryAuditState extends State<InventoryAudit> {
  String category = 'الكل';

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('products').snapshots(),
    builder: (context, products) {
      if (products.hasError) return const Center(child: Text('تعذر تحميل الأصناف'));
      if (!products.hasData) return const Center(child: CircularProgressIndicator());

      final rows = products.data!.docs.where((p) => p.data()['active'] == true).toList();
      final categories = {'الكل', ...rows.map((p) => '${p.data()['category'] ?? 'غير مصنف'}')}.toList()..sort();
      final selected = categories.contains(category) ? category : 'الكل';

      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('stock').snapshots(),
        builder: (context, stock) {
          if (stock.hasError) return const Center(child: Text('تعذر تحميل المخزون'));
          if (!stock.hasData) return const Center(child: CircularProgressIndicator());

          final amounts = <String, int>{};
          for (final entry in stock.data!.docs) {
            final data = entry.data();
            final id = '${data['productId'] ?? ''}';
            if (id.isNotEmpty) {
              amounts[id] = (amounts[id] ?? 0) + ((data['quantity'] as num?)?.toInt() ?? 0);
            }
          }

          final filtered = rows
              .where((p) => selected == 'الكل' || '${p.data()['category'] ?? 'غير مصنف'}' == selected)
              .toList()
            ..sort((a, b) => '${a.data()['name']}'.compareTo('${b.data()['name']}'));

          final auditRows = filtered.map((p) {
            final data = p.data();
            return <String, dynamic>{
              'id': p.id,
              'name': data['name'] ?? '',
              'category': data['category'] ?? 'غير مصنف',
              'purchasePrice': (data['purchasePrice'] as num?)?.toDouble() ?? 0,
              'price': (data['price'] as num?)?.toDouble() ?? 0,
              'quantity': amounts[p.id] ?? 0,
            };
          }).toList();

          final totalCost = auditRows.fold<double>(0, (sum, row) => sum + ((row['purchasePrice'] as num).toDouble() * (row['quantity'] as num).toDouble()));
          final totalSale = auditRows.fold<double>(0, (sum, row) => sum + ((row['price'] as num).toDouble() * (row['quantity'] as num).toDouble()));

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: DropdownButtonFormField<String>(
                value: selected,
                decoration: const InputDecoration(labelText: 'الفئة'),
                items: categories.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setState(() => category = v ?? 'الكل'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
                Text('عدد الأصناف: ${filtered.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('إجمالي المخزون بسعر التكلفة: ${totalCost.toStringAsFixed(2)} ج.م'),
                Text('إجمالي المخزون بسعر البيع: ${totalSale.toStringAsFixed(2)} ج.م', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => openInventoryPrices(context), icon: const Icon(Icons.price_change), label: const Text('زيادة / تخفيض الأسعار')),
                  OutlinedButton.icon(onPressed: auditRows.isEmpty ? null : () => printInventoryAudit(context, selected, auditRows, 'a4'), icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF A4')),
                  OutlinedButton.icon(onPressed: auditRows.isEmpty ? null : () => printInventoryAudit(context, selected, auditRows, '80'), icon: const Icon(Icons.print), label: const Text('طباعة 80 مم')),
                ]),
              ]))),
            ),
            Expanded(
              child: ListView.builder(itemCount: filtered.length, itemBuilder: (context, index) {
                final p = filtered[index];
                final data = p.data();
                final qty = amounts[p.id] ?? 0;
                return InventoryProductCard(number: index + 1, name: '${data['name']}', quantity: qty, unitPrice: data['price'] as num?,
                  detail: 'الفئة: ${data['category'] ?? 'غير مصنف'} • سعر الشراء: ${data['purchasePrice'] ?? 'غير مسجل'} ج.م',
                  actions: [
                    IconButton(tooltip: 'حذف المنتج', icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => archiveProduct(context, p.id, '${data['name'] ?? ''}')),
                  ],
                );
              }),
            ),
          ]);
        },
      );
    },
  );
}

Future<void> printInventoryAudit(BuildContext context, String category, List<Map<String, dynamic>> rows, String paper) async {
  try {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final pdf = pw.Document();
    final totalCost = rows.fold<double>(0, (sum, row) => sum + ((row['purchasePrice'] as num?)?.toDouble() ?? 0) * ((row['quantity'] as num?)?.toDouble() ?? 0));
    final totalSale = rows.fold<double>(0, (sum, row) => sum + ((row['price'] as num?)?.toDouble() ?? 0) * ((row['quantity'] as num?)?.toDouble() ?? 0));
    final thermal = paper != 'a4';

    pdf.addPage(pw.MultiPage(
      pageFormat: invoicePageFormat(paper),
      theme: pw.ThemeData.withFont(base: font, bold: font),
      build: (_) => [
        pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text('VIB للتجارة والتوزيع', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: thermal ? 12 : 20, fontWeight: pw.FontWeight.bold)),
          pw.Text('جرد المخزون - الفئة: $category', textAlign: pw.TextAlign.center),
          pw.Text('التاريخ: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}', textAlign: pw.TextAlign.center),
          pw.Divider(),
          pw.Text('عدد الأصناف: ${rows.length}'),
          pw.Text('الإجمالي بسعر التكلفة: ${totalCost.toStringAsFixed(2)} ج.م'),
          pw.Text('الإجمالي بسعر البيع: ${totalSale.toStringAsFixed(2)} ج.م'),
          pw.SizedBox(height: 8),
        ])),
        for (var i = 0; i < rows.length; i++)
          pw.Directionality(textDirection: pw.TextDirection.rtl, child: pw.Container(
            padding: pw.EdgeInsets.symmetric(vertical: thermal ? 3 : 5),
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: .4))),
            child: pw.Text('${i + 1}- ${rows[i]['name']} | الكمية ${rows[i]['quantity']} | شراء ${rows[i]['purchasePrice']} | بيع ${rows[i]['price']}', style: pw.TextStyle(fontSize: thermal ? 8 : 10)),
          )),
      ],
    ));

    await Printing.layoutPdf(name: 'VIB-INVENTORY-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.pdf', onLayout: (_) => pdf.save());
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء جرد المخزون: $e')));
  }
}


class ProfitReport extends StatefulWidget {
  const ProfitReport({super.key});
  @override State<ProfitReport> createState() => _ProfitReportState();
}

class _ProfitReportState extends State<ProfitReport> {
  String period = 'day';
  @override Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (period) {
      'week' => today.subtract(Duration(days: today.weekday - 1)),
      'month' => DateTime(now.year, now.month, 1),
      _ => today,
    };
    final end = switch (period) {
      'week' => start.add(const Duration(days: 7)),
      'month' => DateTime(now.year, now.month + 1, 1),
      _ => start.add(const Duration(days: 1)),
    };
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'day', label: Text('يومي')),
          ButtonSegment(value: 'week', label: Text('أسبوعي')),
          ButtonSegment(value: 'month', label: Text('شهري'))],
        selected: {period}, onSelectionChanged: (v) => setState(() => period = v.first))),
      Text('من ${DateFormat('dd/MM/yyyy').format(start)} إلى ${DateFormat('dd/MM/yyyy').format(end.subtract(const Duration(days: 1)))}'),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('products').snapshots(),
        builder: (context, productsSnap) {
          if (productsSnap.hasError) return const Center(child: Text('تعذر تحميل تكلفة الأصناف'));
          if (!productsSnap.hasData) return const Center(child: CircularProgressIndicator());
          final products = {for (final p in productsSnap.data!.docs) p.id: p.data()};
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('sales')
              .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
              .where('createdAt', isLessThan: Timestamp.fromDate(end)).snapshots(),
            builder: (context, salesSnap) {
              if (salesSnap.hasError) return const Center(child: Text('تعذر تحميل المبيعات'));
              if (!salesSnap.hasData) return const Center(child: CircularProgressIndicator());
              final sales = salesSnap.data!.docs.where((d) => visibleAfterReset(d.data())).toList();
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db.collection('salesReturns').where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start)).where('createdAt', isLessThan: Timestamp.fromDate(end)).snapshots(),
                builder: (context, returnsSnap) {
                  if (returnsSnap.hasError) return const Center(child: Text('تعذر تحميل المرتجعات'));
                  if (!returnsSnap.hasData) return const Center(child: CircularProgressIndicator());
                  final returns = returnsSnap.data!.docs.where((d) => visibleAfterReset(d.data())).toList();
              double revenue = 0, knownCost = 0;
              int missingCost = 0;
              for (final event in [...sales.map((d) => (data: d.data(), sign: 1)), ...returns.map((d) => (data: d.data(), sign: -1))]) {
                final sale = event.data;
                revenue += event.sign * ((sale['total'] as num?)?.toDouble() ?? 0);
                final rawItems = (sale['items'] as List?) ?? const [];
                if (rawItems.isNotEmpty) {
                  for (final raw in rawItems) {
                    if (raw is! Map) continue;
                    final qty = (raw['quantity'] as num?)?.toDouble() ?? 0;
                    final storedCost = (raw['purchasePriceAtSale'] as num?)?.toDouble();
                    final currentCost = products['${raw['productId']}']?['purchasePrice'];
                    final cost = storedCost ?? (currentCost is num ? currentCost.toDouble() : null);
                    if (cost != null && cost >= 0) {
                      knownCost += event.sign * qty * cost;
                    } else {
                      missingCost++;
                    }
                  }
                } else {
                  final qty = (sale['quantity'] as num?)?.toDouble() ?? 0;
                  final cost = products['${sale['productId']}']?['purchasePrice'];
                  if (cost is num && cost >= 0) {
                    knownCost += event.sign * qty * cost.toDouble();
                  } else {
                    missingCost++;
                  }
                }
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('accountMovements').where('accountType', isEqualTo: 'expenses').snapshots(), builder: (context, expensesSnap) {
                if (expensesSnap.hasError) return const Center(child: Text('تعذر تحميل المصروفات'));
                if (!expensesSnap.hasData) return const Center(child: CircularProgressIndicator());
                final expenses = expensesSnap.data!.docs.where((d) { final data = d.data(); final date = (data['createdAt'] as Timestamp?)?.toDate(); return visibleAfterReset(data) && date != null && !date.isBefore(start) && date.isBefore(end); }).fold<double>(0, (sum, d) => sum + ((d.data()['amount'] as num?)?.toDouble() ?? 0));
              return ListView(padding: const EdgeInsets.all(16), children: [
                ListTile(title: const Text('عدد فواتير البيع'), trailing: Text('${sales.length}')),
                ListTile(title: const Text('عدد المرتجعات خلال الفترة'), trailing: Text('${returns.length}')),
                ListTile(title: const Text('صافي المبيعات بعد المرتجعات'), trailing: Text('${revenue.toStringAsFixed(2)} ج.م')),
                ListTile(title: const Text('تكلفة الأصناف المعروفة'), trailing: Text('${knownCost.toStringAsFixed(2)} ج.م')),
                ListTile(title: const Text('المصروفات'), trailing: Text('${expenses.toStringAsFixed(2)} ج.م')),
                ListTile(title: const Text('الربح الإجمالي التقديري'),
                  trailing: Text('${(revenue - knownCost).toStringAsFixed(2)} ج.م',
                    style: const TextStyle(color: gold, fontWeight: FontWeight.bold))),
                ListTile(title: const Text('الربح بعد المصروفات'), trailing: Text('${(revenue - knownCost - expenses).toStringAsFixed(2)} ج.م')),
                if (missingCost > 0) Text('الربح المعروض تقديري: تكلفة الشراء غير مسجلة في $missingCost فاتورة، ولذلك قد يكون الربح الفعلي أقل. أضف تكلفة شراء الأصناف أولًا.'),
                const SizedBox(height: 16),
                const Text('هذا تقدير حسب سعر الشراء المسجل حاليًا للصنف. يشمل المصروفات المسجلة في الفترة، وقد يختلف إذا تغيرت التكلفة بعد البيع.'),
              ]);
              });
              });
            },
          );
        },
      )),
    ]);
  }
}

class Purchases extends StatefulWidget {
  final bool owner;
  const Purchases({super.key, this.owner = true});
  @override State<Purchases> createState()=>_PurchasesState();
}
class _PurchasesState extends State<Purchases>{
  bool get owner=>widget.owner;
  @override void initState(){super.initState();if(owner)prepareInvoiceSerials('purchases').then((_){if(mounted)setState((){});}).catchError((Object e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('تعذر تجهيز أرقام المشتريات: $e')));});}
  @override
  Widget build(BuildContext context) => Column(children: [
    if (owner) Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, children: [
      FilledButton.icon(onPressed: () => purchaseDialog(context), icon: const Icon(Icons.add), label: const Text('فاتورة مشتريات جديدة')),
      OutlinedButton.icon(onPressed: () => scannedPurchaseDialog(context), icon: const Icon(Icons.camera_alt), label: const Text('تصوير فاتورة مشتريات')),
    ])),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('purchases').orderBy('createdAt', descending: true).limit(300).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('تعذر تحميل المشتريات'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!.docs.where((d) => visibleAfterReset(d.data())).toList();
        if (rows.isEmpty) return const Center(child: Text('لا توجد فواتير مشتريات بعد'));
        return ListView(children: rows.map((d) {
          final p = d.data();
          final rawItems = (p['items'] as List?) ?? const [];
          final itemCount = rawItems.isNotEmpty ? rawItems.length : 1;
          final itemText = rawItems.isNotEmpty
              ? rawItems.take(3).map((e) => '${(e as Map)['productName'] ?? ''} × ${e['quantity'] ?? 0}').join(' • ')
              : '${p['productName'] ?? ''} × ${p['quantity'] ?? 0}';
          return Card(child: ListTile(
            title: Text('فاتورة ${invoiceDisplayNumber('purchases',d.id,p)} • ${p['supplierName'] ?? ''}'),
            subtitle: Text('$itemText${itemCount > 3 ? ' • +${itemCount - 3} أصناف' : ''}\n${formatDate(p['createdAt'])}${p['status'] == 'returned' ? ' • مرتجع' : ''}'),
            isThreeLine: true,
            trailing: Text('${p['total'] ?? 0} ج.م', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
            onTap: () => invoiceActions(context, 'purchases', d.id, p, canReturn: owner),
          ));
        }).toList());
      },
    )),
  ]);
}

String formatDate(dynamic value) => value is Timestamp ? DateFormat('dd/MM/yyyy HH:mm').format(value.toDate()) : 'جارٍ الحفظ';

class ScannedLine {
  String? productId;
  final quantity = TextEditingController(text: '1');
  final cost = TextEditingController();
  final discount = PurchaseDiscountDraft();
  ScannedLine({this.productId});
  void dispose() { quantity.dispose(); cost.dispose(); }
}

String _ocrKey(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0621-\u064a]'), '');
String _ocrNumber(String value) => value.replaceAllMapped(RegExp(r'[٠-٩]'), (m) => '${m.group(0)!.runes.first - 0x660}').replaceAll('٫', '.').replaceAll('٬', '');

Future<void> scannedPurchaseDialog(BuildContext context) async {
  final products = await db.collection('products').where('active', isEqualTo: true).get();
  final suppliers = await db.collection('suppliers').get();
  if (!context.mounted) return;
  if (products.docs.isEmpty || suppliers.docs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف الأصناف والمورد أولًا'))); return;
  }
  final source = await showModalBottomSheet<ImageSource>(context: context, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
    ListTile(leading: const Icon(Icons.camera_alt), title: const Text('التقاط صورة'), onTap: () => Navigator.pop(c, ImageSource.camera)),
    ListTile(leading: const Icon(Icons.photo_library), title: const Text('اختيار صورة'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
  ])));
  if (source == null) return;
  XFile? photo;
  try { photo = await ImagePicker().pickImage(source: source, imageQuality: 90, maxWidth: 2400); }
  catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر فتح الكاميرا: $e'))); return; }
  if (photo == null || !context.mounted) return;
  final notice = ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري قراءة الفاتورة...'), duration: Duration(minutes: 1)));
  String text = '';
  try { text = await TesseractOcr.extractText(photo.path, config: const OCRConfig(language: 'ara+eng', engine: OCREngine.tesseract)); }
  catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذرت القراءة التلقائية. يمكنك إدخال الفاتورة يدويًا.'))); }
  notice.close();
  if (!context.mounted) return;
  String? supplierId;
  final whole = _ocrKey(text);
  for (final s in suppliers.docs) {
    final name = _ocrKey('${s.data()['name'] ?? ''}');
    if (name.length >= 3 && whole.contains(name)) { supplierId = s.id; break; }
  }
  final lines = <ScannedLine>[];
  for (final row in text.split('\n')) {
    final normalized = _ocrKey(row);
    for (final p in products.docs) {
      final name = _ocrKey('${p.data()['name'] ?? ''}');
      if (name.length >= 3 && normalized.contains(name) && !lines.any((e) => e.productId == p.id)) {
        lines.add(ScannedLine(productId: p.id)); break;
      }
    }
  }
  if (lines.isEmpty) lines.add(ScannedLine());
  final invoice = TextEditingController();
  final paid = TextEditingController(text: '0');
  final markup = TextEditingController();
  bool saving = false;
  await showDialog<void>(context: context, barrierDismissible: false, builder: (outer) => StatefulBuilder(builder: (c, update) => AlertDialog(
    title: const Text('مراجعة فاتورة المشتريات'),
    content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Image.file(File(photo!.path), height: 140),
      const Text('راجع المورد والكمية وسعر الشراء لكل صنف؛ القراءة من الصورة قد تخطئ.', style: TextStyle(color: gold)),
      ExpansionTile(title: const Text('النص المستخرج من الصورة'), children: [SelectableText(text.isEmpty ? 'لم يتم التعرف على النص' : text)]),
      DropdownButtonFormField<String>(initialValue: supplierId, isExpanded: true, decoration: const InputDecoration(labelText: 'المورد *'), items: suppliers.docs.where((d) => d.data()['active'] != false).map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}', overflow: TextOverflow.ellipsis))).toList(), onChanged: saving ? null : (v) => update(() => supplierId = v)),
      TextField(controller: invoice, decoration: const InputDecoration(labelText: 'رقم فاتورة المورد')),
      for (var i = 0; i < lines.length; i++) Card(key: ObjectKey(lines[i]), child: Padding(padding: const EdgeInsets.all(8), child: Column(children: [
        Row(children: [Expanded(child: Text('الصنف ${i + 1}')), IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: saving ? null : () => update(() => lines.removeAt(i).dispose()))]),
        DropdownButtonFormField<String>(initialValue: lines[i].productId, isExpanded: true, decoration: const InputDecoration(labelText: 'الصنف المسجل *'), items: products.docs.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}', overflow: TextOverflow.ellipsis))).toList(), onChanged: saving ? null : (v) => update(() => lines[i].productId = v)),
        TextField(controller: lines[i].quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية *')),
        TextField(controller: lines[i].cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر الشراء للوحدة *')),
      ]))),
      TextButton.icon(onPressed: saving || lines.length >= 30 ? null : () => update(() => lines.add(ScannedLine())), icon: const Icon(Icons.add), label: const Text('إضافة صنف')),
      TextField(controller: paid, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المدفوع للمورد الآن')),
      TextField(controller: markup, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'زيادة سعر البيع % (اختياري؛ مثل 5 أو 10)'), onChanged: (_) => update(() {})),
      if (double.tryParse(_ocrNumber(markup.text.replaceAll(',', '.'))) case final percent?)
        for (final row in lines)
          if (row.productId != null)
            if (double.tryParse(_ocrNumber(row.cost.text.replaceAll(',', '.'))) case final cost?)
              Text('${products.docs.firstWhere((p) => p.id == row.productId).data()['name']}: سعر البيع المقترح ${(cost * (1 + percent / 100)).toStringAsFixed(2)} ج.م'),
    ]))),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(onPressed: saving ? null : () async {
      final entries = <({String id, int qty, double cost})>[];
      var total = 0.0;
      for (final row in lines) {
        final qty = int.tryParse(_ocrNumber(row.quantity.text.trim()));
        final cost = double.tryParse(_ocrNumber(row.cost.text.trim().replaceAll(',', '.')));
        if (row.productId == null || qty == null || qty <= 0 || cost == null || !cost.isFinite || cost < 0 || entries.any((e) => e.id == row.productId)) {
          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('راجع كل صنف وكمية وسعر؛ لا تكرر الصنف'))); return;
        }
        entries.add((id: row.productId!, qty: qty, cost: cost)); total += qty * cost;
      }
      final payment = double.tryParse(_ocrNumber(paid.text.trim().replaceAll(',', '.')));
      final increase = markup.text.trim().isEmpty ? null : double.tryParse(_ocrNumber(markup.text.trim().replaceAll(',', '.')));
      if (markup.text.trim().isNotEmpty && (increase == null || !increase.isFinite || increase < 0 || increase > 1000)) {
        ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('اكتب نسبة زيادة صحيحة من 0 إلى 1000'))); return;
      }
      if (!total.isFinite || supplierId == null || payment == null || !payment.isFinite || payment < 0 || payment > total) {
        ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('اختر المورد وتأكد من المبلغ المدفوع'))); return;
      }
      update(() => saving = true);
      try {
        final supplier = suppliers.docs.firstWhere((e) => e.id == supplierId).data();
        await prepareInvoiceSerials('purchases');
        final purchaseRef = db.collection('purchases').doc();
        await db.runTransaction((tx) async {
          final supplierRef = db.collection('suppliers').doc(supplierId);
          final supplierSnap = await tx.get(supplierRef);
          if (!supplierSnap.exists) throw StateError('المورد غير موجود');

          final stocks = <String, DocumentSnapshot<Map<String, dynamic>>>{};
          for (final e in entries) {
            stocks[e.id] = await tx.get(db.collection('stock').doc('main_${e.id}'));
          }

          final before = (supplierSnap.data()?['balance'] as num?)?.toDouble() ?? 0;
          final cashRef = db.collection('settings').doc('cash');
          final cashSnapshot = await tx.get(cashRef);
          final invoiceSerial=await readInvoiceSerial(tx,'purchases',purchaseRef.id);
          final cashBefore = (cashSnapshot.data()?['balance'] as num?)?.toDouble() ?? 0;
          if (cashBefore < payment) throw Exception('رصيد الصندوق لا يكفي لسداد المشتريات');
          writeInvoiceSerial(tx,invoiceSerial);
          final due = total - payment;
          final actor = FirebaseAuth.instance.currentUser!.uid;
          final items = <Map<String, dynamic>>[];
          if (payment > 0) {
            tx.set(cashRef, {'balance': cashBefore - payment, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
            tx.set(db.collection('accountMovements').doc(), {'accountType': 'cash', 'kind': 'purchasePayment', 'amount': payment, 'delta': -payment, 'balanceBefore': cashBefore, 'balanceAfter': cashBefore - payment, 'accountId': supplierId, 'accountName': supplier['name'], 'referenceId': purchaseRef.id, 'reason': 'سداد فاتورة مشتريات', 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
          }

          tx.update(supplierRef, {'balance': before + due, 'updatedAt': FieldValue.serverTimestamp()});

          for (final e in entries) {
            final p = products.docs.firstWhere((d) => d.id == e.id).data();
            final old = (stocks[e.id]?.data()?['quantity'] as num?)?.toInt() ?? 0;
            final lineTotal = e.qty * e.cost;

            items.add({
              'productId': e.id,
              'productName': p['name'],
              'quantity': e.qty,
              'unitCost': e.cost,
              'lineTotal': lineTotal,
            });

            tx.set(db.collection('stock').doc('main_${e.id}'), {
              'branchId': 'main',
              'productId': e.id,
              'quantity': old + e.qty,
            }, SetOptions(merge: true));

            tx.update(db.collection('products').doc(e.id), {
              'purchasePrice': e.cost,
              if (increase != null) 'price': double.parse((e.cost * (1 + increase / 100)).toStringAsFixed(2)),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            tx.set(db.collection('stockMovements').doc(), {
              'productId': e.id,
              'productName': p['name'],
              'branchId': 'main',
              'kind': 'purchase',
              'quantity': e.qty,
              'balanceAfter': old + e.qty,
              'referenceId': purchaseRef.id,
              'actorId': actor,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          tx.set(purchaseRef, {
            'invoiceNumber': invoice.text.trim(),
                  'internalNumber': invoiceSerial.data['internalNumber'],
                  'invoiceBarcode': invoiceSerial.data['invoiceBarcode'],
            'source': 'camera',
            'supplierPreviousBalance': before,
            'supplierBalanceAfter': before + due,
            'supplierId': supplierId,
            'supplierName': supplier['name'],
            'items': items,
            'itemCount': items.length,
            'total': total,
            'paid': payment,
                  'cashPosted': true,
            'due': due,
            'status': 'completed',
            'actorId': actor,
            'createdAt': FieldValue.serverTimestamp(),
            if (items.length == 1) 'productId': items.first['productId'],
            if (items.length == 1) 'productName': items.first['productName'],
            if (items.length == 1) 'quantity': items.first['quantity'],
            if (items.length == 1) 'unitCost': items.first['unitCost'],
          });

          tx.set(db.collection('accountMovements').doc(), {
            'accountType': 'suppliers',
            'accountId': supplierId,
            'accountName': supplier['name'],
            'kind': 'purchase',
            'amount': due,
            'balanceBefore': before,
            'balanceAfter': before + due,
            'referenceId': purchaseRef.id,
            'paid': payment,
            'createdAt': FieldValue.serverTimestamp(),
            'actorId': actor,
          });
        });
        if (c.mounted) Navigator.pop(c);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الفاتورة وتحديث المخزون وحساب المورد')));
      } catch (e) {
        if (c.mounted) { update(() => saving = false); ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'))); }
      }
    }, child: const Text('تأكيد وحفظ'))],
  )));
  for (final row in lines) { row.dispose(); }
  invoice.dispose(); paid.dispose(); markup.dispose();
}

Future<String?> pickPurchaseProduct(
  BuildContext context,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> products,
  Set<String> excluded,
) => showInvoiceProductChoices(context,
  products:[for(final p in products) (id:p.id,name:'${p.data()['name'] ?? ''}')],
  excluded:excluded,unitCosts:{for(final p in products) p.id:p.data()['purchasePrice'] as num?},
  stockStreamFor:invoiceMainStock,
);
double purchaseInvoicePayment(double total, bool credit, String paid) => credit
    ? double.tryParse(paid.trim().replaceAll(',', '.')) ?? -1 : total;

class PurchaseInvoiceLine extends StatefulWidget {
  final int number;
  final String name;
  final TextEditingController cost, quantity;
  final bool enabled;
  final bool priceEditable;
  final bool totalEditable;
  final PurchaseDiscountDraft? discountDraft;
  final VoidCallback onChoose, onDelete, onChanged;
  const PurchaseInvoiceLine({super.key, required this.number, required this.name, required this.cost,
    required this.quantity, required this.enabled, required this.onChoose, required this.onDelete, required this.onChanged,this.priceEditable = true,this.totalEditable = false,this.discountDraft});
  @override
  State<PurchaseInvoiceLine> createState() => _PurchaseInvoiceLineState();
}

class _PurchaseInvoiceLineState extends State<PurchaseInvoiceLine> {
  final _total = TextEditingController();
  final _discount = TextEditingController();
  late PurchaseDiscountDraft _draft;
  String? _discountError;
  bool _updatingCost = false;
  String? _totalError;
  @override
  void initState() {
    super.initState();
    _draft = widget.discountDraft ?? PurchaseDiscountDraft();
    _draft.baseCost ??= double.tryParse(widget.cost.text.replaceAll(',', '.')) ?? 0;
    _discount.text = _draft.percent.toString();
    widget.cost.addListener(_costChanged);
    widget.quantity.addListener(_syncTotal);
    _syncTotal();
  }
  @override
  void didUpdateWidget(covariant PurchaseInvoiceLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cost != widget.cost || oldWidget.quantity != widget.quantity) {
      oldWidget.cost.removeListener(_costChanged);
      oldWidget.quantity.removeListener(_syncTotal);
      widget.cost.addListener(_costChanged);
      widget.quantity.addListener(_syncTotal);
      _syncTotal();
    }
  }
  void _costChanged() {
    if (_updatingCost) return;
    _draft.baseCost = double.tryParse(widget.cost.text.replaceAll(',', '.')) ?? 0;
    _draft.percent = 0;
    _discount.text = '0';
    _discountError = null;
    _syncTotal();
  }
  void _applyDiscount(String text) {
    final percent = double.tryParse(text.trim().replaceAll(',', '.'));
    final valid = percent != null && percent.isFinite && percent >= 0 && percent <= 100;
    _updatingCost = true;
    if (valid) {
      _draft.percent = percent;
      widget.cost.text = ((_draft.baseCost ?? 0) * (1 - percent / 100)).toString();
    } else {
      widget.cost.text = ''; // Existing invoice validation prevents saving an invalid discount.
    }
    _updatingCost = false;
    _syncTotal();
    setState(() => _discountError = valid ? null : 'من 0 إلى 100');
    widget.onChanged();
  }
  void _stepDiscount(double step) {
    final value = (double.tryParse(_discount.text.replaceAll(',', '.')) ?? _draft.percent);
    _discount.text = (value + step).clamp(0, 100).toString();
    _applyDiscount(_discount.text);
  }
  void _syncTotal() {
    if (_updatingCost) return;
    final qty = int.tryParse(widget.quantity.text.trim()) ?? 0;
    final cost = double.tryParse(widget.cost.text.trim().replaceAll(',', '.')) ?? 0;
    final value = qty * cost;
    final text = value.isFinite ? value.toStringAsFixed(2) : '';
    if (_total.text != text) _total.text = text;
    _totalError = null;
  }
  void _costFromTotal(String text) {
    final qty = int.tryParse(widget.quantity.text.trim()) ?? 0;
    final amount = double.tryParse(text.trim().replaceAll(',', '.'));
    final valid = qty > 0 && amount != null && amount.isFinite && amount >= 0;
    _updatingCost = true;
    // Retain division precision: rounding the unit cost to cents changes
    // the supplier's line total when the quantity does not divide evenly.
    widget.cost.text = valid ? (amount / qty).toString() : '';
    if (valid) {
      final netCost = amount / qty;
      final base = _draft.baseCost ?? 0;
      if (base > 0 && netCost <= base) {
        _draft.percent = (1 - netCost / base) * 100;
      } else {
        _draft.baseCost = netCost;
        _draft.percent = 0;
      }
      _discount.text = _draft.percent.toStringAsFixed(2);
      _discountError = null;
    }
    _updatingCost = false;
    setState(() => _totalError = valid ? null : qty <= 0 ? 'أدخل العدد أولًا' : 'إجمالي غير صحيح');
    widget.onChanged();
  }
  @override
  void dispose() {
    widget.cost.removeListener(_costChanged);
    widget.quantity.removeListener(_syncTotal);
    _total.dispose();
    _discount.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final number = widget.number, name = widget.name;
    final cost = widget.cost, quantity = widget.quantity;
    final enabled = widget.enabled, priceEditable = widget.priceEditable;
    final onChoose = widget.onChoose, onDelete = widget.onDelete, onChanged = widget.onChanged;
    final total = (int.tryParse(quantity.text.trim()) ?? 0) *
      (double.tryParse(cost.text.trim().replaceAll(',', '.')) ?? 0);
    Widget field(TextEditingController controller, String label, {bool integer = false}) => TextField(
      controller: controller, enabled: enabled && (integer || priceEditable), textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13),
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      decoration: InputDecoration(labelText: label, floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: const TextStyle(fontSize: 11), isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8), border: const OutlineInputBorder()),
      onChanged: (_) => onChanged());
    return Container(margin: const EdgeInsets.only(bottom: 5), padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: const Color(0xFF121212), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4A3A18))),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 5), child: Text('$number.', style: const TextStyle(fontSize: 12, color: gold))),
          const SizedBox(width: 5),
          Expanded(child: InkWell(onTap: enabled ? onChoose : null,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(name, softWrap: true, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))))),
          IconButton(tooltip: 'تغيير الصنف', onPressed: enabled ? onChoose : null,
            padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            icon: const Icon(Icons.search, size: 18, color: gold)),
          IconButton(tooltip: 'حذف البند', onPressed: enabled ? onDelete : null,
            padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent)),
        ]),
        const SizedBox(height: 3),
        Row(children: [
          Expanded(flex: 4, child: field(cost, 'السعر')),
          const SizedBox(width: 5), Expanded(flex: 2, child: field(quantity, 'العدد', integer: true)),
          const SizedBox(width: 5), Expanded(flex: 4, child: widget.totalEditable ? TextField(
            controller: _total, enabled: enabled && priceEditable, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: gold),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'الإجمالي', errorText: _totalError,
              floatingLabelBehavior: FloatingLabelBehavior.always, labelStyle: const TextStyle(fontSize: 11),
              isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
              border: const OutlineInputBorder()), onChanged: _costFromTotal,
          ) : Column(children: [
            const Text('الإجمالي', style: TextStyle(fontSize: 11)),
            FittedBox(fit: BoxFit.scaleDown, child: Text(total.toStringAsFixed(2),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: gold))),
          ])),
        ]),
        if(widget.totalEditable) Padding(padding:const EdgeInsets.only(top:6),child:Row(children:[
          IconButton(tooltip:'تقليل نسبة الخصم',onPressed:enabled && priceEditable ? ()=>_stepDiscount(-1) : null,
            constraints:const BoxConstraints.tightFor(width:32,height:32),padding:EdgeInsets.zero,
            icon:const Icon(Icons.remove,size:18,color:gold)),
          Expanded(child:TextField(controller:_discount,enabled:enabled && priceEditable,textAlign:TextAlign.center,
            keyboardType:const TextInputType.numberWithOptions(decimal:true),style:const TextStyle(fontSize:12),
            decoration:InputDecoration(labelText:'خصم %',errorText:_discountError,isDense:true,
              floatingLabelBehavior:FloatingLabelBehavior.always,contentPadding:const EdgeInsets.symmetric(horizontal:5,vertical:7),
              border:const OutlineInputBorder()),onChanged:_applyDiscount)),
          IconButton(tooltip:'زيادة نسبة الخصم',onPressed:enabled && priceEditable ? ()=>_stepDiscount(1) : null,
            constraints:const BoxConstraints.tightFor(width:32,height:32),padding:EdgeInsets.zero,
            icon:const Icon(Icons.add,size:18,color:gold)),
        ])),
      ]));
  }
}

class PurchaseSettlementPanel extends StatelessWidget {
  final double total, previousBalance;
  final bool credit, enabled;
  final TextEditingController paid;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onChanged;
  final String partyLabel;
  const PurchaseSettlementPanel({super.key, required this.total, required this.previousBalance,
    required this.credit, required this.paid, required this.enabled, required this.onModeChanged, required this.onChanged,this.partyLabel = 'المورد'});
  @override
  Widget build(BuildContext context) {
    final payment = purchaseInvoicePayment(total, credit, paid.text);
    final due = payment.isFinite ? (total - payment).clamp(0, double.infinity).toDouble() : total;
    Widget money(String label, double value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
        Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 6), Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft,
          child: FittedBox(fit: BoxFit.scaleDown, child: Text('${value.toStringAsFixed(2)} ج.م',
            style: TextStyle(fontSize: bold ? 16 : 13, color: bold ? gold : Colors.white,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal))))),
      ]));
    return _vibInvoicePanel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      money('إجمالي الفاتورة', total, bold: true),
      Row(children: [
        Expanded(child: ChoiceChip(label: const Text('نقدي', style: TextStyle(fontSize: 12)),
          showCheckmark: false, selected: !credit, onSelected: enabled ? (_) => onModeChanged(false) : null)),
        const SizedBox(width: 6),
        Expanded(child: ChoiceChip(label: const Text('آجل', style: TextStyle(fontSize: 12)),
          showCheckmark: false, selected: credit, onSelected: enabled ? (_) => onModeChanged(true) : null)),
      ]),
      if (credit) TextField(controller: paid, enabled: enabled, style: const TextStyle(fontSize: 13),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'المدفوع نقدًا الآن', isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 7, horizontal: 5)), onChanged: (_) => onChanged())
      else money('المدفوع نقدًا الآن', payment),
      money('باقي هذه الفاتورة', due, bold: true),
      money('الرصيد السابق', previousBalance),
      money(partyLabel == 'العميل' ? 'إجمالي المديونية' : 'المتبقي للمورد', previousBalance + due, bold: true),
    ]));
  }
}

Future<void> purchaseDialog(BuildContext context) async {
  final products = await db.collection('products').where('active', isEqualTo: true).get();
  final suppliers = await db.collection('suppliers').get();
  if (!context.mounted) return;
  if (products.docs.isEmpty || suppliers.docs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف منتجًا وموردًا أولًا')));
    return;
  }

  final activeSuppliers=suppliers.docs.where((d)=>d.data()['active'] != false).toList();
  if(activeSuppliers.isEmpty) {ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أضف موردًا مفعلًا أولًا')));return;}
  String supplierId = '';
  final lines = <ScannedLine>[];
  final paid = TextEditingController(text: '0');
  final invoice = TextEditingController();
  final markup = TextEditingController();
  bool saving = false, credit = true, checkout = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(builder: (c, setLocal) {
      double previewTotal = 0;
      for (final row in lines) {
        final q = int.tryParse(row.quantity.text.trim()) ?? 0;
        final cost = double.tryParse(row.cost.text.trim().replaceAll(',', '.')) ?? 0;
        previewTotal += q * cost;
      }
      final selectedSupplier = supplierId.isEmpty ? null : activeSuppliers.firstWhere((d) => d.id == supplierId);
      final previousSupplierBalance = (selectedSupplier?.data()['balance'] as num?)?.toDouble() ?? 0;
      void addSelected(String id) {
        if(saving || lines.length >= 50 || lines.any((row)=>row.productId == id)) return;
        final product=products.docs.firstWhere((d)=>d.id == id);
        final row=ScannedLine(productId:id);
        row.cost.text=((product.data()['purchasePrice'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);
        setLocal(()=>lines.add(row));
      }
      return InvoiceEditorFrame(
        title:checkout ? 'حفظ فاتورة المشتريات' : 'فاتورة مشتريات',checkout:checkout,total:previewTotal,
        headerAction:IgnorePointer(ignoring:saving,child:const ChatShortcut(owner:true)),
        toolbar:InvoiceProductsBar(
          unitCosts:{for(final product in products.docs) product.id:product.data()['purchasePrice'] as num?},stockStreamFor:invoiceMainStock,
          products:[for(final product in products.docs) if(!lines.any((row)=>row.productId == product.id))
            (id:product.id,name:'${product.data()['name'] ?? ''}')],
          enabled:!saving && lines.length < 50,onSelect:addSelected,
          onSearch:() async {
            final id=await pickPurchaseProduct(c,products.docs,lines.map((row)=>row.productId).whereType<String>().toSet());
            if(id != null && c.mounted) addSelected(id);
          },
        ),
        body:checkout ? ListView(children:[
          DropdownButtonFormField<String>(initialValue:supplierId.isEmpty ? null : supplierId,isExpanded:true,
            decoration:_vibInvoiceInput('اسم المورد'),
            items:activeSuppliers.map((d)=>DropdownMenuItem(value:d.id,child:Text('${d.data()['name'] ?? ''}',maxLines:2,overflow:TextOverflow.ellipsis))).toList(),
            onChanged:saving ? null : (id) {if(id != null) setLocal(()=>supplierId=id);}),
          const SizedBox(height:10),
          PurchaseSettlementPanel(total:previewTotal,previousBalance:previousSupplierBalance,credit:credit,
            paid:paid,enabled:!saving,onModeChanged:(value)=>setLocal(()=>credit=value),onChanged:()=>setLocal(() {})),
          ExpansionTile(title:const Text('تفاصيل إضافية (اختياري)',style:TextStyle(fontSize:13)),children:[
            TextField(controller:invoice,enabled:!saving,decoration:_vibInvoiceInput('رقم فاتورة المورد')),
            const SizedBox(height:8),
            TextField(controller:markup,enabled:!saving,keyboardType:const TextInputType.numberWithOptions(decimal:true),
              decoration:_vibInvoiceInput('زيادة سعر البيع %')),
          ]),
        ]) : lines.isEmpty ? const Center(child:Text('اختر صنفًا من البحث أو القائمة')) : ListView(children:[
          for(var i=0;i<lines.length;i++) PurchaseInvoiceLine(
            key:ObjectKey(lines[i]),number:i+1,name:'${products.docs.firstWhere((d)=>d.id == lines[i].productId).data()['name'] ?? ''}',
            cost:lines[i].cost,quantity:lines[i].quantity,enabled:!saving,totalEditable:true,discountDraft:lines[i].discount,onChanged:()=>setLocal(() {}),
            onDelete:() {final row=lines.removeAt(i);row.dispose();setLocal(() {});},
            onChoose:() async {
              final row=lines[i];
              final id=await pickPurchaseProduct(c,products.docs,lines.where((other)=>other != row).map((other)=>other.productId).whereType<String>().toSet());
              if(id == null || !c.mounted) return;
              setLocal(() {row.productId=id;row.cost.text=((products.docs.firstWhere((d)=>d.id == id).data()['purchasePrice'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);});
            },
          ),
        ]),
        actions: [
          TextButton(onPressed:saving ? null : () {if(checkout) {setLocal(()=>checkout=false);} else {Navigator.pop(c);}},child:Text(checkout ? 'رجوع للبنود' : 'إلغاء')),
          FilledButton(onPressed: saving ? null : () async {
            FocusScope.of(c).unfocus();
            if (lines.isEmpty) {
              await showInvoiceSaveProblem(c, 'أضف منتجًا واحدًا على الأقل قبل حفظ الفاتورة');
              return;
            }
            if (!checkout) {setLocal(() => checkout=true);return;}
            if(supplierId.isEmpty) {await showInvoiceSaveProblem(c,'اختر المورد لحفظ الفاتورة في حسابه');return;}
            final entries = <({String id, int qty, double cost})>[];
            double total = 0;
            for (final row in lines) {
              final qty = int.tryParse(row.quantity.text.trim());
              final unitCost = double.tryParse(row.cost.text.trim().replaceAll(',', '.'));
              if (row.productId == null || qty == null || qty <= 0 || unitCost == null || !unitCost.isFinite || unitCost < 0 || entries.any((e) => e.id == row.productId)) {
                await showInvoiceSaveProblem(c, 'راجع كل بند: المنتج والكمية والسعر، ولا تكرر نفس المنتج');
                return;
              }
              entries.add((id: row.productId!, qty: qty, cost: unitCost));
              total += qty * unitCost;
            }
            final payment = purchaseInvoicePayment(total, credit, paid.text);
            final increase = markup.text.trim().isEmpty ? null : double.tryParse(markup.text.trim().replaceAll(',', '.'));
            if (!total.isFinite || !payment.isFinite || payment < 0 || payment > total) {
              await showInvoiceSaveProblem(c, 'قيمة المدفوع غير صحيحة');
              return;
            }
            if (markup.text.trim().isNotEmpty && (increase == null || !increase.isFinite || increase < 0 || increase > 1000)) {
              await showInvoiceSaveProblem(c, 'نسبة زيادة سعر البيع غير صحيحة');
              return;
            }

            setLocal(() => saving = true);
            await prepareInvoiceSerials('purchases');
        final purchaseRef = db.collection('purchases').doc();
            try {
              final supplier = suppliers.docs.firstWhere((d) => d.id == supplierId).data();
              final savedInvoice = await db.runTransaction<Map<String, dynamic>>((tx) async {
                final supplierRef = db.collection('suppliers').doc(supplierId);
                final supplierSnap = await tx.get(supplierRef);
                if (!supplierSnap.exists) throw Exception('المورد غير موجود');

                final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
                for (final e in entries) {
                  stockSnaps[e.id] = await tx.get(db.collection('stock').doc('main_${e.id}'));
                }

                final beforeBalance = (supplierSnap.data()?['balance'] as num?)?.toDouble() ?? 0;
                final cashRef = db.collection('settings').doc('cash');
          final cashSnapshot = await tx.get(cashRef);
          final invoiceSerial=await readInvoiceSerial(tx,'purchases',purchaseRef.id);
          final cashBefore = (cashSnapshot.data()?['balance'] as num?)?.toDouble() ?? 0;
          if (cashBefore < payment) throw Exception('رصيد الصندوق لا يكفي لسداد المشتريات');
          writeInvoiceSerial(tx,invoiceSerial);
          final due = total - payment;
                final actor = FirebaseAuth.instance.currentUser!.uid;
                final items = <Map<String, dynamic>>[];
          if (payment > 0) {
            tx.set(cashRef, {'balance': cashBefore - payment, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
            tx.set(db.collection('accountMovements').doc(), {'accountType': 'cash', 'kind': 'purchasePayment', 'amount': payment, 'delta': -payment, 'balanceBefore': cashBefore, 'balanceAfter': cashBefore - payment, 'accountId': supplierId, 'accountName': supplier['name'], 'referenceId': purchaseRef.id, 'reason': 'سداد فاتورة مشتريات', 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
          }

                tx.update(supplierRef, {'balance': beforeBalance + due, 'updatedAt': FieldValue.serverTimestamp()});

                for (final e in entries) {
                  final productDoc = products.docs.firstWhere((d) => d.id == e.id);
                  final product = productDoc.data();
                  final oldQty = (stockSnaps[e.id]?.data()?['quantity'] as num?)?.toInt() ?? 0;
                  final lineTotal = e.qty * e.cost;
                  items.add({
                    'productId': e.id,
                    'productName': product['name'],
                    'quantity': e.qty,
                    'unitCost': e.cost,
                    'lineTotal': lineTotal,
                  });

                  tx.set(db.collection('stock').doc('main_${e.id}'), {
                    'branchId': 'main',
                    'productId': e.id,
                    'quantity': oldQty + e.qty,
                  }, SetOptions(merge: true));

                  tx.update(db.collection('products').doc(e.id), {
                    'purchasePrice': e.cost,
                    if (increase != null) 'price': double.parse((e.cost * (1 + increase / 100)).toStringAsFixed(2)),
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  tx.set(db.collection('stockMovements').doc(), {
                    'productId': e.id,
                    'productName': product['name'],
                    'branchId': 'main',
                    'kind': 'purchase',
                    'quantity': e.qty,
                    'balanceAfter': oldQty + e.qty,
                    'referenceId': purchaseRef.id,
                    'actorId': actor,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }

                final invoiceData = <String, dynamic>{
                  'invoiceNumber': invoice.text.trim(),
                  'internalNumber': invoiceSerial.data['internalNumber'],
                  'invoiceBarcode': invoiceSerial.data['invoiceBarcode'],
                  'supplierId': supplierId,
                  'supplierName': supplier['name'],
                  'items': items,
                  'itemCount': items.length,
                  'total': total,
                  'paid': payment,
                  'cashPosted': true,
                  'paymentStatus': due > 0 ? 'credit' : 'cash',
                  'supplierPreviousBalance': beforeBalance,
                  'supplierBalanceAfter': beforeBalance + due,
                  'due': due,
                  'status': 'completed',
                  'source': 'manual',
                  'actorId': actor,
                  'createdAt': FieldValue.serverTimestamp(),
                  if (items.length == 1) 'productId': items.first['productId'],
                  if (items.length == 1) 'productName': items.first['productName'],
                  if (items.length == 1) 'quantity': items.first['quantity'],
                  if (items.length == 1) 'unitCost': items.first['unitCost'],
                };
                tx.set(purchaseRef, invoiceData);

                tx.set(db.collection('accountMovements').doc(), {
                  'accountType': 'suppliers',
                  'accountId': supplierId,
                  'accountName': supplier['name'],
                  'kind': 'purchase',
                  'amount': due,
                  'balanceBefore': beforeBalance,
                  'balanceAfter': beforeBalance + due,
                  'referenceId': purchaseRef.id,
                  'paid': payment,
                  'createdAt': FieldValue.serverTimestamp(),
                  'actorId': actor,
                });
                return {...invoiceData, 'createdAt': Timestamp.now()};
              });

              if (c.mounted) Navigator.pop(c);
              if (context.mounted) await showInvoiceSavedActions(context, 'purchases', purchaseRef.id, savedInvoice);
            } catch (e) {
              if (c.mounted) {
                setLocal(() => saving = false);
                await showInvoiceSaveProblem(c, invoiceSaveFailureMessage(e));
              }
            }
          }, child:saving ? const InvoiceSaveButtonLabel(saving:true) : Text(checkout ? 'تأكيد الحفظ' : 'إضافة')),
        ],
      );
    }),
  );

  for (final row in lines) { row.dispose(); }
  paid.dispose();
  invoice.dispose();
  markup.dispose();
}


class AccountMovements extends StatelessWidget {
  const AccountMovements({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: db.collection('accountMovements').orderBy('createdAt', descending: true).limit(500).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return const Center(child: Text('تعذر تحميل الحركات'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snap.data!.docs.where((d) => visibleAfterReset(d.data())).toList();
      if (rows.isEmpty) return const Center(child: Text('لا توجد حركات بعد'));
      return ListView(children: rows.map((d) { final m = d.data(); return ListTile(title: Text('${m['accountName'] ?? ''} • ${movementName('${m['kind']}')}'), subtitle: Text(formatDate(m['createdAt'])), trailing: Text('${m['amount'] ?? 0} ج.م')); }).toList());
    },
  );
}

String movementName(String kind) => switch (kind) { 'purchase' => 'مشتريات', 'payment' => 'سداد مورد', 'collection' => 'تحصيل عميل', 'sale' => 'مبيعات', 'sales_return' => 'مرتجع مبيعات', 'purchase_return' => 'مرتجع مشتريات', 'transfer_in' => 'تحويل وارد', 'transfer_out' => 'تحويل صادر', 'adjustment' => 'تسوية مخزون', 'saleCorrection' => 'تعديل فاتورة بيع', 'purchasePayment' => 'سداد فاتورة مشتريات', 'supplierPayment' => 'سداد مورد', 'customerCollection' => 'تحصيل عميل', 'deposit' => 'إيداع بالصندوق', 'withdrawal' => 'سحب من الصندوق', 'expense' => 'مصروف', 'opening' => 'رصيد افتتاحي', _ => kind };

Future<void> assignEmployee(BuildContext context, String uid, Map<String, dynamic> data) async {
  final name = TextEditingController(text: '${data['name'] ?? ''}');
  final branches = await db.collection('branches').get();
  if (!context.mounted) return;
  if (branches.docs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف فرعًا أولًا')));
    return;
  }
  String selected = branches.docs.any((d) => d.id == data['branchId'])
      ? data['branchId'] as String : branches.docs.first.id;
  bool enabled = data['active'] == true;
  bool canPrint = data['canPrint'] == true;
  await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
    builder: (c, setDialogState) => AlertDialog(
      title: const Text('صلاحيات الموظف'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الموظف')),
        DropdownButtonFormField<String>(initialValue: selected,
          decoration: const InputDecoration(labelText: 'الفرع'),
          items: branches.docs.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}'))).toList(),
          onChanged: (v) { if (v != null) setDialogState(() => selected = v); }),
        SwitchListTile(title: const Text('تفعيل الدخول'), value: enabled,
          onChanged: (v) => setDialogState(() => enabled = v)),
        SwitchListTile(title: const Text('السماح بطباعة الفواتير'), value: canPrint,
          onChanged: (v) => setDialogState(() => canPrint = v)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(onPressed: () async {
          if (name.text.trim().isEmpty) return;
          try {
            await db.collection('users').doc(uid).update({
              'name': name.text.trim(), 'role': 'employee', 'branchId': selected,
              'active': enabled, 'canPrint': canPrint,
            });
            if (c.mounted) Navigator.pop(c);
          } catch (_) {
            if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('تعذر حفظ صلاحيات الموظف')));
          }
        }, child: const Text('حفظ'))],
    ),
  ));
}

Future<void> mainStockDialog(BuildContext context, String productId, String name) async {
  final desired = TextEditingController();
  final reason = TextEditingController();
  final stockRef = db.collection('stock').doc('main_$productId');
  final current = await stockRef.get();
  if (!context.mounted) return;
  final original = (current.data()?['quantity'] as num?)?.toInt() ?? 0;
  desired.text = '$original';
  await showDialog<void>(context: context, builder: (c) => AlertDialog(
    title: Text('تسوية المخزون الرئيسي: $name'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('الرصيد الحالي: $original'),
      TextField(controller: desired, keyboardType: const TextInputType.numberWithOptions(signed: true),
        decoration: const InputDecoration(labelText: 'الرصيد الصحيح بعد التسوية')),
      TextField(controller: reason, maxLength: 160,
        decoration: const InputDecoration(labelText: 'سبب التسوية')),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(onPressed: () async {
      final target = int.tryParse(desired.text.trim());
      if (target == null || reason.text.trim().isEmpty) {
        ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('اكتب الرصيد الصحيح وسبب التسوية')));
        return;
      }
      try {
        await db.runTransaction((tx) async {
          final snapshot = await tx.get(stockRef);
          final before = (snapshot.data()?['quantity'] as num?)?.toInt() ?? 0;
          if (before != original) throw Exception('الرصيد اتغير؛ افتح التسوية مرة تانية');
          if (before == target) throw Exception('الرصيد الجديد مطابق للحالي');
          tx.set(stockRef, {'branchId': 'main', 'productId': productId, 'quantity': target});
          tx.set(db.collection('stockAdjustments').doc(), {
            'productId': productId, 'productName': name, 'branchId': 'main',
            'before': before, 'after': target, 'delta': target - before,
            'reason': reason.text.trim(), 'actorId': FirebaseAuth.instance.currentUser!.uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          tx.set(db.collection('stockMovements').doc(), {'productId': productId, 'productName': name, 'branchId': 'main', 'kind': 'adjustment', 'quantity': target - before, 'balanceAfter': target, 'reason': reason.text.trim(), 'actorId': FirebaseAuth.instance.currentUser!.uid, 'createdAt': FieldValue.serverTimestamp()});
        });
        if (c.mounted) Navigator.pop(c);
      } catch (e) { if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('تعذر التسوية: $e'))); }
    }, child: const Text('حفظ التسوية'))],
  ));
}

class ReceiptVouchers extends StatelessWidget {
  final bool owner;
  final String branchId;
  const ReceiptVouchers({super.key, required this.owner, required this.branchId});

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = db.collection('receipts');
    if (!owner) query = query.where('actorId', isEqualTo: FirebaseAuth.instance.currentUser!.uid);
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity,
        child: FilledButton.icon(onPressed: () => createReceiptVoucher(context, branchId),
          icon: const Icon(Icons.add), label: const Text('إنشاء سند قبض')))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SizedBox(width: double.infinity,
        child: OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
          Directionality(textDirection: TextDirection.rtl, child: CustomerPaymentReport(owner: owner)))),
          icon: const Icon(Icons.assessment_outlined), label: const Text('تقرير حركة سداد العملاء')))),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('تعذر تحميل سندات القبض؛ تحقق من الاتصال وصلاحيات الحساب'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!.docs.where((d) => visibleAfterReset(d.data())).toList()
            ..sort((a, b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
              .compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
          if (rows.isEmpty) return const Center(child: Text('لا توجد سندات قبض بعد'));
          return ListView.builder(itemCount: rows.length, itemBuilder: (context, index) {
            final row = rows[index], data = row.data();
            return Card(child: ListTile(
              leading: const Icon(Icons.payments_outlined, color: gold),
              title: Text('${data['customerName']} • ${data['amount']} ج.م'),
              subtitle: Text('سند: ${row.id}\n${formatDate(data['createdAt'])} • ${data['actorName'] ?? ''}\nالرصيد بعد القبض: ${data['balanceAfter']} ج.م'),
              isThreeLine: true,
              trailing: IconButton(tooltip: 'طباعة / حفظ PDF', icon: const Icon(Icons.picture_as_pdf),
                onPressed: () => printReceiptVoucher(context, row.id, data)),
            ));
          });
        },
      )),
    ]);
  }
}

class ReceiptCustomerTotal {
  final String id, name;
  final List<Map<String, dynamic>> receipts;
  final int amountCents;
  const ReceiptCustomerTotal(this.id, this.name, this.receipts, this.amountCents);
}

class ReceiptDayReport {
  final List<ReceiptCustomerTotal> customers;
  final int receiptCount, totalCents;
  const ReceiptDayReport(this.customers, this.receiptCount, this.totalCents);
}

// Use the same local calendar day as the date picker. Sum money in piastres.
ReceiptDayReport summarizeReceiptDay(List<Map<String, dynamic>> receipts, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  final end = DateTime(day.year, day.month, day.day + 1);
  final groups = <String, List<Map<String, dynamic>>>{};
  var totalCents = 0, count = 0;
  for (final receipt in receipts) {
    final stamp = receipt['createdAt'];
    if (stamp is! Timestamp) continue;
    final at = stamp.toDate().toLocal();
    if (at.isBefore(start) || !at.isBefore(end)) continue;
    final amount = receipt['amount'];
    if (amount is! num || !amount.toDouble().isFinite || amount <= 0) {
      throw StateError('يوجد سند قبض بمبلغ غير صحيح؛ راجع السند قبل اعتماد التقرير');
    }
    final cents = (amount * 100).round();
    final customerId = '${receipt['customerId'] ?? ''}';
    final key = customerId.isEmpty ? 'receipt:${receipt['id']}' : 'customer:$customerId';
    groups.putIfAbsent(key, () => []).add(receipt);
    totalCents += cents;
    count++;
  }
  final customers = groups.entries.map((entry) {
    final rows = entry.value..sort((a, b) {
      final order = (a['createdAt'] as Timestamp).compareTo(b['createdAt'] as Timestamp);
      return order != 0 ? order : '${a['id']}'.compareTo('${b['id']}');
    });
    return ReceiptCustomerTotal('${rows.last['customerId'] ?? ''}',
      '${rows.last['customerName'] ?? 'عميل غير مسمى'}', rows,
      rows.fold<int>(0, (sum, row) => sum + ((row['amount'] as num) * 100).round()));
  }).toList()..sort((a, b) {
    final order = a.name.compareTo(b.name);
    return order != 0 ? order : a.id.compareTo(b.id);
  });
  return ReceiptDayReport(customers, count, totalCents);
}

String receiptReportMoney(int cents) => '${(cents / 100).toStringAsFixed(2)} ج.م';

class CustomerPaymentReport extends StatefulWidget {
  final bool owner;
  const CustomerPaymentReport({super.key, required this.owner});
  @override
  State<CustomerPaymentReport> createState() => _CustomerPaymentReportState();
}

class _CustomerPaymentReportState extends State<CustomerPaymentReport> {
  DateTime day = DateTime.now();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> receipts;
  @override
  void initState() {
    super.initState();
    Query<Map<String, dynamic>> query = db.collection('receipts');
    if (!widget.owner) query = query.where('actorId', isEqualTo: FirebaseAuth.instance.currentUser!.uid);
    receipts = query.snapshots();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('حركة سداد العملاء')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: SizedBox(width: double.infinity,
        child: OutlinedButton.icon(icon: const Icon(Icons.calendar_month),
          label: Text('يوم السداد: ${DateFormat('yyyy/MM/dd').format(day)}'),
          onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: day,
              firstDate: DateTime(2000), lastDate: DateTime.now());
            if (picked != null && mounted) setState(() => day = picked);
          }))),
      Text(widget.owner ? 'سندات القبض من جميع الموظفين والمدير' : 'سندات القبض التي سجلتها فقط',
        textAlign: TextAlign.center),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: receipts,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('تعذر تحميل تقرير السداد؛ راجع الاتصال وصلاحيات سندات القبض'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!.docs.where((d) => visibleAfterReset(d.data()))
            .map((d) => <String, dynamic>{...d.data(), 'id': d.id}).toList();
          final ReceiptDayReport report;
          try { report = summarizeReceiptDay(rows, day); }
          on StateError catch (e) { return Center(child: Text('${e.message}', textAlign: TextAlign.center)); }
          final pending = snapshot.data!.metadata.hasPendingWrites;
          final cached = snapshot.data!.metadata.isFromCache;
          return Column(children: [
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
              Text('إجمالي سداد اليوم: ${receiptReportMoney(report.totalCents)}',
                textAlign: TextAlign.center, style: const TextStyle(color: gold, fontSize: 20, fontWeight: FontWeight.bold)),
              Text('عدد التجار: ${report.customers.length} • عدد سندات القبض: ${report.receiptCount}'),
              if (cached || pending) const Text('البيانات لم تُؤكد من الخادم بعد؛ انتظر اكتمال المزامنة', textAlign: TextAlign.center),
            ]))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
              Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.picture_as_pdf), label: const Text('طباعة A4'),
                onPressed: report.receiptCount == 0 || cached || pending ? null : () => printCustomerPaymentReport(context, day, report, owner: widget.owner))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.receipt_long), label: const Text('طباعة 80 مللي'),
                onPressed: report.receiptCount == 0 || cached || pending ? null : () => printCustomerPaymentReport(context, day, report, owner: widget.owner, thermal: true))),
            ])),
            Expanded(child: report.customers.isEmpty ? const Center(child: Text('لا توجد سدادات مسجلة بسندات قبض في هذا اليوم'))
              : ListView.builder(itemCount: report.customers.length, itemBuilder: (context, index) {
                final customer = report.customers[index];
                return Card(child: ExpansionTile(
                  leading: Text('${index + 1}', style: const TextStyle(color: gold)),
                  title: Text(customer.name),
                  subtitle: Text('إجمالي السداد: ${receiptReportMoney(customer.amountCents)} • ${customer.receipts.length} سند'),
                  children: customer.receipts.map((row) => ListTile(
                    title: Text('${DateFormat('HH:mm').format((row['createdAt'] as Timestamp).toDate().toLocal())} • ${receiptReportMoney(((row['amount'] as num) * 100).round())}'),
                    subtitle: Text('سند: ${row['id']}\nالمحصّل: ${row['actorName'] ?? ''}${'${row['note'] ?? ''}'.isEmpty ? '' : '\n${row['note']}'}'),
                  )).toList(),
                ));
              })),
          ]);
        })),
    ]),
  );
}

Future<Uint8List> createCustomerPaymentReportPdf(DateTime day, ReceiptDayReport report, pw.Font font, {required bool owner, bool thermal = false}) async {
  final pdf = pw.Document();
  if (thermal) {
    pw.Widget line(String value, {bool bold = false}) => pw.Text(value, textAlign: pw.TextAlign.right,
      style: pw.TextStyle(fontSize: bold ? 10 : 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));
    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.roll80, margin: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
      theme: pw.ThemeData.withFont(base: font, bold: font), textDirection: pw.TextDirection.rtl,
      build: (_) => pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        line('VIB للتجارة والتوزيع', bold: true), line('حركة سداد العملاء', bold: true),
        line('اليوم: ${DateFormat('yyyy/MM/dd').format(day)}'),
        line(owner ? 'تحصيلات المدير وجميع الموظفين' : 'تحصيلاتي فقط'),
        line('عدد التجار: ${report.customers.length} • السندات: ${report.receiptCount}'), pw.Divider(),
        for (var i = 0; i < report.customers.length; i++) ...[
          line('${i + 1}. ${report.customers[i].name}', bold: true),
          line('إجمالي السداد: ${receiptReportMoney(report.customers[i].amountCents)}', bold: true),
          for (final row in report.customers[i].receipts) ...[
            line('${DateFormat('HH:mm').format((row['createdAt'] as Timestamp).toDate().toLocal())} • ${receiptReportMoney(((row['amount'] as num) * 100).round())}'),
            line('سند: ${row['id']}'), line('المحصّل: ${row['actorName'] ?? ''}'),
          ], pw.Divider(),
        ],
        line('إجمالي تحصيل اليوم', bold: true), line(receiptReportMoney(report.totalCents), bold: true),
      ])));
    return pdf.save();
  }
  const navy = PdfColor.fromInt(0xFF14263D), accent = PdfColor.fromInt(0xFFB58A38);
  pw.Widget cell(String value, {bool header = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(6), child: pw.Text(value, textAlign: pw.TextAlign.right,
      style: pw.TextStyle(fontSize: 10, color: header ? PdfColors.white : PdfColors.black)));
  final movements = report.customers.expand((c) => c.receipts).toList();
  pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, maxPages: 1000,
    theme: pw.ThemeData.withFont(base: font, bold: font), textDirection: pw.TextDirection.rtl,
    footer: (context) => pw.Text('${context.pageNumber} / ${context.pagesCount}', textAlign: pw.TextAlign.center),
    build: (_) => [
      pw.Text('VIB للتجارة والتوزيع', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 22, color: navy)),
      pw.SizedBox(height: 12), pw.Text('تقرير حركة سداد العملاء', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 18)),
      pw.Text('يوم السداد: ${DateFormat('yyyy/MM/dd').format(day)}'),
      pw.Text(owner ? 'سندات القبض من جميع الموظفين والمدير' : 'سندات القبض التي سجلتها فقط'),
      pw.Text('عدد التجار: ${report.customers.length} • عدد السندات: ${report.receiptCount}'),
      pw.SizedBox(height: 12),
      pw.Table(border: pw.TableBorder.all(color: accent, width: .5), columnWidths: {
        0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(4), 3: const pw.FlexColumnWidth(.5)},
        children: [
          pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: navy),
            children: ['إجمالي السداد', 'عدد السندات', 'اسم التاجر / العميل', 'م'].map((v) => cell(v, header: true)).toList()),
          for (var i = 0; i < report.customers.length; i++) pw.TableRow(children: [
            cell(receiptReportMoney(report.customers[i].amountCents)), cell('${report.customers[i].receipts.length}'),
            cell(report.customers[i].name), cell('${i + 1}')]),
        ]),
      pw.SizedBox(height: 10), pw.Text('إجمالي المبالغ المحصّلة لليوم: ${receiptReportMoney(report.totalCents)}',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 16), pw.Text('تفاصيل حركة السداد'), pw.SizedBox(height: 6),
      pw.Table(border: pw.TableBorder.all(color: accent, width: .5), columnWidths: {
        0: const pw.FlexColumnWidth(1.5), 1: const pw.FlexColumnWidth(2), 2: const pw.FlexColumnWidth(2.5),
        3: const pw.FlexColumnWidth(3), 4: const pw.FlexColumnWidth(1)}, children: [
          pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: navy),
            children: ['المبلغ', 'المحصّل', 'رقم السند', 'العميل', 'الوقت'].map((v) => cell(v, header: true)).toList()),
          for (final row in movements) pw.TableRow(children: [
            cell(receiptReportMoney(((row['amount'] as num) * 100).round())), cell('${row['actorName'] ?? ''}'),
            cell('${row['id']}'), cell('${row['customerName'] ?? ''}'),
            cell(DateFormat('HH:mm').format((row['createdAt'] as Timestamp).toDate().toLocal()))]),
        ]),
    ]));
  return pdf.save();
}

Future<void> printCustomerPaymentReport(BuildContext context, DateTime day, ReceiptDayReport report, {required bool owner, bool thermal = false}) async {
  try {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final bytes = await createCustomerPaymentReportPdf(day, report, font, owner: owner, thermal: thermal);
    await Printing.layoutPdf(name: 'VIB-CUSTOMER-PAYMENTS-${DateFormat('yyyy-MM-dd').format(day)}-${thermal ? '80MM' : 'A4'}.pdf', onLayout: (_) async => bytes);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر طباعة تقرير السداد: $e')));
  }
}

Future<void> createReceiptVoucher(BuildContext context, String branchId, {String? initialCustomerId}) async {
  final amount = TextEditingController(), note = TextEditingController(), invoiceNumber = TextEditingController();
  // Reuse this ID on transaction retries and after an uncertain network response.
  final receiptRef = db.collection('receipts').doc();
  final customerMovement = db.collection('accountMovements').doc();
  final cashMovement = db.collection('accountMovements').doc();
  String? customerId = initialCustomerId;
  bool saving = false;
  await showDialog<void>(context: context, barrierDismissible: false, builder: (dialog) => StatefulBuilder(
    builder: (dialog, update) => AlertDialog(
      title: const Text('سند قبض من عميل'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        OutlinedButton.icon(icon: const Icon(Icons.person_search),
          label: const Text('اختيار عميل مسجل / تغيير العميل'),
          onPressed: saving ? null : () async {
            final id = await selectRegisteredCustomer(dialog);
            if (id != null && dialog.mounted) update(() => customerId = id);
          }),
        if (customerId != null) StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.collection('customers').doc(customerId).snapshots(),
          builder: (context, snap) => Text(snap.hasError ? 'تعذر تحميل رصيد العميل' : !snap.hasData ? 'جارٍ تحميل الرصيد' : '${snap.data?.data()?['name'] ?? ''} — الرصيد الحالي: ${snap.data?.data()?['balance'] ?? 0} ج.م'),
        ),
        TextField(controller: amount, enabled: !saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'المبلغ المقبوض')),
        TextField(controller: invoiceNumber, enabled: !saving, decoration: const InputDecoration(labelText: 'رقم فاتورة المبيعات المرتبطة بالسند (اختياري)')),
        const Text('تحديد الفاتورة يمنع تعديلها. السند العام يُحتسب على رصيد العميل، وتحتاج فواتيره السابقة مراجعة قبل التعديل.'),
        TextField(controller: note, enabled: !saving, decoration: const InputDecoration(labelText: 'البيان / ملاحظات')),
        const SizedBox(height: 12),
        const Text('يُخصم المبلغ من مديونية العميل ويُضاف للصندوق عند حفظ السند.'),
      ])),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(dialog), child: const Text('إلغاء')),
        FilledButton(onPressed: saving ? null : () async {
          final paid = double.tryParse(amount.text.trim());
          final id = customerId;
          if (invoiceNumber.text.trim().contains('/')) {
            ScaffoldMessenger.of(dialog).showSnackBar(const SnackBar(content: Text('رقم الفاتورة غير صحيح'))); return;
          }
          if (id == null || paid == null || !paid.isFinite || paid <= 0) {
            ScaffoldMessenger.of(dialog).showSnackBar(const SnackBar(content: Text('اختر العميل واكتب مبلغًا صحيحًا أكبر من صفر')));
            return;
          }
          update(() => saving = true);
          try {
            final actor = FirebaseAuth.instance.currentUser!.uid;
            final profile = (await db.collection('users').doc(actor).get()).data();
            final linkedInvoiceId=await resolveInvoiceNumber('sales',invoiceNumber.text.trim());
            await db.runTransaction((tx) async {
              final existing = await tx.get(receiptRef);
              if (existing.exists) return;
              final customerRef = db.collection('customers').doc(id);
              final customer = await tx.get(customerRef);
              final cashRef = db.collection('settings').doc('cash');
              final cash = await tx.get(cashRef);
              if (!customer.exists || customer.data()?['active'] == false) throw Exception('العميل غير متاح');
              final balance = (customer.data()?['balance'] as num?)?.toDouble() ?? 0;
              if (paid > balance) throw Exception('المبلغ أكبر من المديونية الحالية للعميل');
              final beforeCash = (cash.data()?['balance'] as num?)?.toDouble() ?? 0;
              final invoiceId = linkedInvoiceId;
              final invoiceRef = invoiceId.isEmpty ? null : db.collection('sales').doc(invoiceId);
              final invoice = invoiceRef == null ? null : (await tx.get(invoiceRef)).data();
              if (invoiceRef != null && (invoice == null || invoice['customerId'] != id || invoice['status'] != 'completed')) {
                throw Exception('الفاتورة غير موجودة أو لا تخص العميل المختار');
              }
              if (invoice != null && paid > ((invoice['due'] as num?)?.toDouble() ?? 0) - ((invoice['receiptPaid'] as num?)?.toDouble() ?? 0) + 0.000001) {
                throw Exception('المبلغ أكبر من المتبقي غير المحصّل في الفاتورة');
              }
              final now = FieldValue.serverTimestamp();
              if (invoiceRef != null) tx.update(invoiceRef, {'receiptId': receiptRef.id,
                'receiptPaid': ((invoice!['receiptPaid'] as num?)?.toDouble() ?? 0) + paid});
              final customerName = '${customer.data()?['name'] ?? ''}';
              tx.update(customerRef, {'balance': balance - paid, 'lastReceiptId': receiptRef.id, 'updatedAt': now});
              tx.set(cashRef, {'balance': beforeCash + paid, 'lastReceiptId': receiptRef.id, 'updatedAt': now}, SetOptions(merge: true));
              tx.set(receiptRef, {
                'customerId': id, 'customerName': customerName, 'customerPhone': '${customer.data()?['phone'] ?? ''}',
                if (invoiceNumber.text.trim().isNotEmpty) 'invoiceId': linkedInvoiceId,
                'amount': paid, 'balanceBefore': balance, 'balanceAfter': balance - paid,
                'cashBefore': beforeCash, 'cashAfter': beforeCash + paid,
                'actorId': actor, 'actorName': '${profile?['name'] ?? ''}', 'branchId': branchId,
                'note': note.text.trim(), 'createdAt': now,
                'customerMovementId': customerMovement.id, 'cashMovementId': cashMovement.id,
              });
              tx.set(customerMovement, {
                'accountType': 'customers', 'accountId': id, 'accountName': customerName, 'kind': 'collection',
                'amount': paid, 'balanceBefore': balance, 'balanceAfter': balance - paid,
                'referenceId': receiptRef.id, 'actorId': actor, 'branchId': branchId, 'createdAt': now,
              });
              tx.set(cashMovement, {
                'accountType': 'cash', 'accountId': id, 'accountName': customerName, 'kind': 'customerCollection',
                'amount': paid, 'delta': paid, 'balanceBefore': beforeCash, 'balanceAfter': beforeCash + paid,
                'referenceId': receiptRef.id, 'reason': 'سند قبض من عميل', 'actorId': actor, 'branchId': branchId, 'createdAt': now,
              });
            });
            if (dialog.mounted) Navigator.pop(dialog);
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ سند القبض وتحديث رصيد العميل والصندوق')));
          } catch (e) {
            if (dialog.mounted) {
              update(() => saving = false);
              ScaffoldMessenger.of(dialog).showSnackBar(SnackBar(content: Text('تعذر حفظ سند القبض: $e')));
            }
          }
        }, child: Text(saving ? 'جاري الحفظ…' : 'حفظ سند القبض')),
      ],
    ),
  ));
  amount.dispose();
  note.dispose();
  invoiceNumber.dispose();
}

Future<void> printReceiptVoucher(BuildContext context, String id, Map<String, dynamic> data) async {
  try {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final pdf = pw.Document();
    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, theme: pw.ThemeData.withFont(base: font, bold: font),
      build: (_) => pw.Directionality(textDirection: pw.TextDirection.rtl,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          pw.Text('VIB للتجارة والتوزيع', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 22)),
          pw.SizedBox(height: 16), pw.Text('سند قبض', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 20)),
          pw.SizedBox(height: 20),
          for (final line in [
            'رقم السند: $id', 'التاريخ: ${formatDate(data['createdAt'])}',
            'استلمنا من: ${data['customerName']}', 'الهاتف: ${data['customerPhone'] ?? ''}',
            'المبلغ: ${data['amount']} ج.م', 'رصيد العميل قبل القبض: ${data['balanceBefore']} ج.م',
            'رصيد العميل بعد القبض: ${data['balanceAfter']} ج.م',
            'الموظف: ${data['actorName'] ?? ''}', 'البيان: ${data['note'] ?? ''}',
          ]) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 7), child: pw.Text(line)),
          pw.SizedBox(height: 30), pw.Text('توقيع المستلم: __________________'),
        ]))));
    await Printing.layoutPdf(name: 'VIB-RECEIPT-$id.pdf', onLayout: (_) => pdf.save());
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر طباعة سند القبض: $e')));
  }
}

class Accounts extends StatefulWidget {
  final bool startWithSuppliers;
  const Accounts({super.key, this.startWithSuppliers = false});
  @override
  State<Accounts> createState() => _AccountsState();
}
class _AccountsState extends State<Accounts> {
  late bool suppliers;
  @override
  void initState() {
    super.initState();
    suppliers = widget.startWithSuppliers;
  }
  @override
  Widget build(BuildContext context) {
    final collection = suppliers ? 'suppliers' : 'customers';
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(children: [SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('العملاء')), ButtonSegment(value: true, label: Text('الموردون'))],
        selected: {suppliers}, onSelectionChanged: (values) => setState(() => suppliers = values.first)),
        if (suppliers) Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: const Text('سندات صرف الموردين')), body: const SafeArea(child: SupplierPaymentVouchers()))))), icon: const Icon(Icons.receipt_long), label: const Text('سندات صرف الموردين'))),
        const SizedBox(height: 8), FilledButton.icon(onPressed: () => createAccountDialog(context, collection, suppliers), icon: const Icon(Icons.person_add), label: Text(suppliers ? 'إضافة مورد' : 'إضافة عميل')),
      ])),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection(collection).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('تعذر تحميل الذمم'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs
              .where((d) => d.data()['active'] != false)
              .toList()
            ..sort((a,b) => '${a.data()['name'] ?? ''}'.compareTo('${b.data()['name'] ?? ''}'));
          if (docs.isEmpty) return const Center(child: Text('لا توجد حسابات بعد'));
          return ListView.builder(itemCount: docs.length, itemBuilder: (context, index) {
            final d = docs[index], account = d.data();
            return ListTile(
              title: Text('${account['name'] ?? ''}'),
              subtitle: Text('هاتف: ${account['phone'] ?? 'غير مسجل'}'),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                Text('${account['balance'] ?? 0} ج.م', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
                Text(accountBalanceLabel((account['balance'] as num?) ?? 0, supplier: suppliers)),
              ]),
              onTap: () => accountDialog(context, collection, d.id, account),
            );
          });
        },
      )),
    ]);
  }
}

Future<void> createAccountDialog(BuildContext context, String collection, bool supplier) async {
  final name = TextEditingController(), phone = TextEditingController(), opening = TextEditingController(text: '0');
  await showDialog<void>(context: context, builder: (c) => AlertDialog(
    title: Text(supplier ? 'إضافة مورد' : 'إضافة عميل'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
      TextField(controller: opening, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي')),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')), FilledButton(onPressed: () async {
      final balance = double.tryParse(opening.text.trim());
      if (name.text.trim().isEmpty || balance == null || !balance.isFinite) return;
      try {
        final ref = db.collection(collection).doc();
        await db.runTransaction((tx) async {
          tx.set(ref, {'name': name.text.trim(), 'phone': phone.text.trim(), 'openingBalance': balance, 'balance': balance, 'active': true, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
          if (balance != 0) tx.set(db.collection('accountMovements').doc(), {'accountType': collection, 'accountId': ref.id, 'accountName': name.text.trim(), 'kind': 'opening', 'amount': balance.abs(), 'balanceBefore': 0, 'balanceAfter': balance, 'createdAt': FieldValue.serverTimestamp(), 'actorId': FirebaseAuth.instance.currentUser!.uid});
        });
        if (c.mounted) Navigator.pop(c);
      } catch (e) { if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'))); }
    }, child: const Text('حفظ'))],
  ));
}

Future<void> accountDialog(BuildContext context, String collection, String id, Map<String, dynamic> account) async {
  if (collection == 'customers') {
    await createReceiptVoucher(context, 'main', initialCustomerId: id);
    return;
  }
  await createSupplierPaymentVoucher(context, initialSupplierId: id);
}

({double supplierAfter, double cashAfter}) supplierPaymentBalances(double balance, double cash, double amount) {
  if (!balance.isFinite || !cash.isFinite || !amount.isFinite || amount <= 0) throw StateError('اكتب مبلغًا صحيحًا أكبر من صفر');
  final paid = (amount * 100).round(), debt = (balance * 100).round(), available = (cash * 100).round();
  if (paid <= 0) throw StateError('المبلغ أقل من قرش');
  if (paid > debt) throw StateError('المبلغ أكبر من مديونية المورد');
  if (paid > available) throw StateError('رصيد الصندوق لا يكفي');
  return (supplierAfter: (debt - paid) / 100, cashAfter: (available - paid) / 100);
}

class SupplierPaymentVouchers extends StatelessWidget {
  const SupplierPaymentVouchers({super.key});
  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: () => createSupplierPaymentVoucher(context), icon: const Icon(Icons.add), label: const Text('إنشاء سند صرف لمورد'))),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('accountMovements').where('accountType', isEqualTo: 'suppliers').snapshots(includeMetadataChanges: true), builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('تعذر تحميل سندات الصرف: ${snapshot.error}'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data!.docs.where((d) => d.data()['kind'] == 'payment' && visibleAfterReset(d.data())).toList()
        ..sort((a,b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
      if (rows.isEmpty) return const Center(child: Text('لا توجد سندات صرف للموردين بعد'));
      return ListView.builder(itemCount: rows.length, itemBuilder: (context, i) {
        final row = rows[i], data = row.data();
        final confirmed = !row.metadata.hasPendingWrites && !snapshot.data!.metadata.isFromCache;
        return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${data['accountName'] ?? ''} • ${data['amount']} ج.م', style: const TextStyle(color: gold, fontWeight: FontWeight.bold)),
          Text('رقم السند: ${row.id}\n${formatDate(data['createdAt'])}\nالباقي للمورد: ${data['balanceAfter']} ج.م'),
          if (!confirmed) const Text('بانتظار تأكيد البيانات من الخادم'),
          Wrap(spacing: 8, children: [for (final thermal in [false,true]) OutlinedButton.icon(onPressed: confirmed ? () => printSupplierPaymentVoucher(context, row.id, data, thermal: thermal) : null, icon: const Icon(Icons.print), label: Text(thermal ? 'طباعة 80 مللي' : 'طباعة A4'))]),
        ])));
      });
    })),
  ]);
}

Future<void> createSupplierPaymentVoucher(BuildContext context, {String? initialSupplierId}) async {
  final amount = TextEditingController(), note = TextEditingController();
  final voucherRef = db.collection('accountMovements').doc(), cashMovement = db.collection('accountMovements').doc();
  String? supplierId = initialSupplierId;
  bool saving = false;
  await showDialog<void>(context: context, barrierDismissible: false, builder: (dialog) => StatefulBuilder(builder: (dialog, update) => AlertDialog(
    title: const Text('سند صرف لمورد'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream: db.collection('suppliers').snapshots(), builder: (context,snap) {
        if (snap.hasError) return const Text('تعذر تحميل الموردين');
        if (!snap.hasData) return const CircularProgressIndicator();
        final rows = snap.data!.docs.where((d) => d.data()['active'] != false).toList()..sort((a,b) => '${a.data()['name']}'.compareTo('${b.data()['name']}'));
        return DropdownButtonFormField<String>(initialValue: rows.any((d) => d.id == supplierId) ? supplierId : null, isExpanded: true, decoration: const InputDecoration(labelText: 'اختيار المورد'), items: rows.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}'))).toList(), onChanged: saving ? null : (id) => update(() => supplierId = id));
      }),
      if (supplierId != null) StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(stream: db.collection('suppliers').doc(supplierId).snapshots(), builder: (_,snap) => Text('مديونية المورد الحالية: ${snap.data?.data()?['balance'] ?? '…'} ج.م')),
      TextField(controller: amount, enabled: !saving, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ المصروف للمورد')),
      TextField(controller: note, enabled: !saving, maxLength: 2000, decoration: const InputDecoration(labelText: 'البيان / ملاحظات')),
      const Text('حفظ السند يخصم المبلغ من الصندوق ومن مديونية المورد معًا.'),
    ])),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(dialog), child: const Text('إلغاء')), FilledButton(onPressed: saving ? null : () async {
      final raw = double.tryParse(amount.text.trim().replaceAll(',', '.')), id = supplierId;
      if (id == null || raw == null || !raw.isFinite || raw <= 0) { await showInvoiceSaveProblem(dialog,'اختر المورد واكتب مبلغًا صحيحًا',title:'سند صرف المورد',button:'رجوع للسند'); return; }
      final paid = (raw * 100).round() / 100;
      update(() => saving = true);
      try {
        final actor = FirebaseAuth.instance.currentUser!.uid;
        await db.runTransaction((tx) async {
          final existing = await tx.get(voucherRef);
          if (existing.exists) {
            if(existing.data()?['accountId'] != id || existing.data()?['amount'] != paid) throw StateError('تم حفظ السند السابق بالفعل؛ افتح سندًا جديدًا للمبلغ الجديد');
            return;
          }
          final user = (await tx.get(db.collection('users').doc(actor))).data();
          if (user?['role'] != 'owner' || user?['active'] != true) throw StateError('سند الصرف متاح للمدير فقط');
          final supplierRef = db.collection('suppliers').doc(id), cashRef = db.collection('settings').doc('cash');
          final supplier = (await tx.get(supplierRef)).data(), cash = (await tx.get(cashRef)).data();
          if (supplier == null || supplier['active'] == false) throw StateError('المورد غير متاح');
          final balance = (supplier['balance'] as num).toDouble(), beforeCash = ((cash?['balance'] as num?) ?? 0).toDouble();
          final after = supplierPaymentBalances(balance,beforeCash,paid), now = FieldValue.serverTimestamp();
          tx.update(supplierRef, {'balance': after.supplierAfter,'updatedAt': now});
          tx.set(cashRef, {'balance': after.cashAfter,'updatedAt': now},SetOptions(merge: true));
          tx.set(voucherRef, {'accountType':'suppliers','accountId':id,'accountName':supplier['name'],'supplierPhone':supplier['phone'] ?? '', 'kind':'payment','amount':paid,'balanceBefore':balance,'balanceAfter':after.supplierAfter,'cashBefore':beforeCash,'cashAfter':after.cashAfter,'referenceId':voucherRef.id,'cashMovementId':cashMovement.id,'note':note.text.trim(),'actorId':actor,'actorName':user?['name'] ?? '', 'createdAt':now});
          tx.set(cashMovement, {'accountType':'cash','accountId':id,'accountName':supplier['name'],'kind':'supplierPayment','amount':paid,'delta':-paid,'balanceBefore':beforeCash,'balanceAfter':after.cashAfter,'referenceId':voucherRef.id,'reason':'سند صرف لمورد','actorId':actor,'createdAt':now});
        });
        if (dialog.mounted) Navigator.pop(dialog);
        if (context.mounted) await showInvoiceSaveProblem(context,'تم حفظ سند الصرف وتحديث حساب المورد والصندوق. السند متاح للطباعة في سندات صرف الموردين.', title:'تم حفظ سند الصرف', button:'تمام', success:true);
      } catch(e) { if (dialog.mounted) { update(() => saving = false); await showInvoiceSaveProblem(dialog,'تعذر حفظ سند الصرف: $e',title:'سند صرف المورد',button:'رجوع للسند'); } }
    }, child: Text(saving ? 'جارٍ الحفظ…' : 'حفظ سند الصرف'))],
  )));
  amount.dispose(); note.dispose();
}

Future<Uint8List> createSupplierPaymentVoucherPdf(String id, Map<String,dynamic> data, pw.Font font, {bool thermal = false}) async {
  final pdf = pw.Document();
  final lines = ['رقم السند: $id', 'التاريخ: ${formatDate(data['createdAt'])}', 'صرفنا إلى المورد: ${data['accountName'] ?? ''}', 'الهاتف: ${data['supplierPhone'] ?? ''}', 'المبلغ المصروف: ${data['amount']} ج.م', 'رصيد المورد قبل السداد: ${data['balanceBefore']} ج.م', 'الباقي عليك للمورد بعد السداد: ${data['balanceAfter']} ج.م', 'الصندوق قبل الصرف: ${data['cashBefore'] ?? 'غير مسجل'} ج.م', 'الصندوق بعد الصرف: ${data['cashAfter'] ?? 'غير مسجل'} ج.م', 'المسؤول: ${data['actorName'] ?? data['actorId'] ?? ''}', 'البيان: ${data['note'] ?? ''}'];
  final widgets = <pw.Widget>[
    pw.Text('VIB للتجارة والتوزيع',textAlign:pw.TextAlign.center,style:pw.TextStyle(fontSize:thermal ? 14 : 22)),
    pw.SizedBox(height:12),pw.Text('سند صرف لمورد',textAlign:pw.TextAlign.center,style:pw.TextStyle(fontSize:thermal ? 16 : 20,fontWeight:pw.FontWeight.bold)),
    for (final line in lines) pw.Padding(padding:const pw.EdgeInsets.symmetric(vertical:6),child:pw.Text(line,style:pw.TextStyle(fontSize:thermal ? 10 : 13))),
    pw.SizedBox(height:20),pw.Text('توقيع المستلم: __________________'),
  ];
  final theme = pw.ThemeData.withFont(base:font,bold:font);
  if(thermal) {
    pdf.addPage(pw.Page(pageFormat:PdfPageFormat.roll80,margin:const pw.EdgeInsets.all(4 * PdfPageFormat.mm),theme:theme,build:(_) => pw.Directionality(textDirection:pw.TextDirection.rtl,child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:widgets))));
  } else {
    pdf.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(30),theme:theme,textDirection:pw.TextDirection.rtl,build:(_) => widgets));
  }
  return pdf.save();
}

Future<void> printSupplierPaymentVoucher(BuildContext context,String id,Map<String,dynamic> data,{bool thermal=false}) async {
  try {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final bytes = await createSupplierPaymentVoucherPdf(id,data,font,thermal:thermal);
    await Printing.layoutPdf(name:'VIB-SUPPLIER-PAYMENT-$id-${thermal ? '80MM' : 'A4'}.pdf',onLayout:(_) async => bytes);
  } catch(e) { if(context.mounted) await showInvoiceSaveProblem(context,'تعذر طباعة سند الصرف: $e',title:'طباعة سند الصرف',button:'تمام'); }
}


class CashBox extends StatelessWidget {
  const CashBox({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [
    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('settings').doc('cash').snapshots(),
      builder: (context, snap) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('رصيد الصندوق: ${snap.data?.data()?['balance'] ?? 0} ج.م',
          style: const TextStyle(fontSize: 22, color: gold)),
      ),
    ),
    Wrap(spacing: 12, children: [
      FilledButton.icon(onPressed: () => cashDialog(context, true),
        icon: const Icon(Icons.add), label: const Text('إضافة للصندوق')),
      OutlinedButton.icon(onPressed: () => cashDialog(context, false),
        icon: const Icon(Icons.remove), label: const Text('خصم من الصندوق')),
    ]),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('accountMovements').where('accountType', isEqualTo: 'cash').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('تعذر عرض حركة الصندوق'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!.docs.where((d) => visibleAfterReset(d.data())).toList()..sort((a, b) =>
          ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
          .compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
        if (rows.isEmpty) return const Center(child: Text('لا توجد حركات للصندوق'));
        return ListView.builder(itemCount: rows.length, itemBuilder: (context, i) {
          final m = rows[i].data();
          final date = m['createdAt'] is Timestamp
            ? DateFormat('dd/MM/yyyy HH:mm').format((m['createdAt'] as Timestamp).toDate())
            : 'جارٍ الحفظ';
          return ListTile(title: Text('${m['reason'] ?? ''}'),
            subtitle: Text('$date • بواسطة ${m['actorId'] ?? ''}'),
            trailing: Text('${(m['delta'] as num?)?.toDouble() ?? 0} ج.م',
              style: const TextStyle(color: gold)));
        });
      },
    )),
  ]);
}

Future<void> cashDialog(BuildContext context, bool deposit) async {
  final amount = TextEditingController(), reason = TextEditingController();
  await showDialog<void>(context: context, builder: (c) => AlertDialog(
    title: Text(deposit ? 'إضافة للصندوق' : 'خصم من الصندوق'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'المبلغ')),
      TextField(controller: reason, maxLength: 160,
        decoration: const InputDecoration(labelText: 'سبب الحركة')),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
      FilledButton(onPressed: () async {
        final value = double.tryParse(amount.text.trim());
        if (value == null || !value.isFinite || value <= 0 || reason.text.trim().isEmpty) {
          ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('اكتب مبلغ صحيح وسبب الحركة')));
          return;
        }
        try {
          await db.runTransaction((tx) async {
            final ref = db.collection('settings').doc('cash');
            final snapshot = await tx.get(ref);
            final before = (snapshot.data()?['balance'] as num?)?.toDouble() ?? 0;
            final delta = deposit ? value : -value;
            if (before + delta < 0) throw Exception('رصيد الصندوق لا يكفي');
            tx.set(ref, {'balance': before + delta, 'updatedAt': FieldValue.serverTimestamp()});
            tx.set(db.collection('accountMovements').doc(), {
              'accountType': 'cash',
              'kind': deposit ? 'deposit' : 'withdrawal', 'amount': value,
              'delta': delta, 'balanceBefore': before, 'balanceAfter': before + delta,
              'reason': reason.text.trim(),
              'actorId': FirebaseAuth.instance.currentUser!.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
          });
          if (c.mounted) Navigator.pop(c);
        } catch (e) {
          if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('تعذر حفظ الحركة: $e')));
        }
      }, child: const Text('حفظ الحركة'))],
  ));
}

class AppSettings extends StatefulWidget {
  const AppSettings({super.key});
  @override State<AppSettings> createState() => _AppSettingsState();
}

class _AppSettingsState extends State<AppSettings> {
  final company = TextEditingController(text: 'VIB للتجارة والتوزيع');
  final phone = TextEditingController(), phone2 = TextEditingController(), whatsapp = TextEditingController(), address = TextEditingController();
  final taxNumber = TextEditingController(), commercialRegister = TextEditingController();
  final footer = TextEditingController(text: 'خالص مع الشكر');
  String logoBase64 = '';
  String paper = 'a4';
  bool loading = true, saving = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final d = (await db.collection('settings').doc('main').get()).data();
    if (d != null) {
      company.text = '${d['companyName'] ?? company.text}'; phone.text = '${d['phone'] ?? ''}';
      whatsapp.text = '${d['whatsapp'] ?? ''}'; address.text = '${d['address'] ?? ''}';
      phone2.text = '${d['phone2'] ?? ''}'; footer.text = '${d['invoiceFooter'] ?? 'شكراً لتعاملكم معنا'}';
      taxNumber.text = '${d['taxNumber'] ?? ''}'; commercialRegister.text = '${d['commercialRegister'] ?? ''}';
      logoBase64 = '${d['logoBase64'] ?? ''}';
      paper = ['a4', '58', '80'].contains(d['paperSize']) ? '${d['paperSize']}' : 'a4';
    }
    if (mounted) setState(() => loading = false);
  }
  Future<void> save() async {
    if (company.text.trim().isEmpty) return;
    setState(() => saving = true);
    try {
      final branding = {'companyName': company.text.trim(), 'phone': phone.text.trim(), 'phone2': phone2.text.trim(),
        'whatsapp': whatsapp.text.trim(), 'address': address.text.trim(), 'paperSize': paper,
        'taxNumber': taxNumber.text.trim(), 'commercialRegister': commercialRegister.text.trim(),
        'invoiceFooter': footer.text.trim(), 'logoBase64': logoBase64};
      final batch = db.batch();
      batch.set(db.collection('settings').doc('main'), {...branding, 'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser!.uid}, SetOptions(merge: true));
      batch.set(db.collection('settings').doc('invoiceBranding'), branding);
      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'))); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override Widget build(BuildContext context) => loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
    TextField(controller: company, decoration: const InputDecoration(labelText: 'اسم الشركة على الفاتورة')),
    TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
    TextField(controller: phone2, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم تليفون إضافي')),
    TextField(controller: whatsapp, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم واتساب')),
    TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
    TextField(controller: taxNumber, decoration: const InputDecoration(labelText: 'رقم البطاقة الضريبية')),
    TextField(controller: commercialRegister, decoration: const InputDecoration(labelText: 'رقم السجل التجاري')),
    TextField(controller: footer, maxLines: 3, maxLength: 300, decoration: const InputDecoration(labelText: 'النص أسفل الفاتورة')),
    const SizedBox(height: 10),
    OutlinedButton.icon(icon: const Icon(Icons.image_outlined), label: const Text('اختيار لوجو الشركة'), onPressed: saving ? null : () async {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 80);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 220000) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر لوجو أصغر من 220 كيلوبايت'))); return;
      }
      setState(() => logoBase64 = base64Encode(bytes));
    }),
    if (logoBase64.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Image.memory(base64Decode(logoBase64), height: 70)),
    if (logoBase64.isNotEmpty) TextButton(onPressed: saving ? null : () => setState(() => logoBase64 = ''), child: const Text('استخدام لوجو VIB الافتراضي')),
    const SizedBox(height: 12), const Text('إعدادات الطباعة', style: TextStyle(color: gold, fontSize: 20)),
    DropdownButtonFormField<String>(value: paper, decoration: const InputDecoration(labelText: 'مقاس ورق الفاتورة'), items: const [DropdownMenuItem(value: 'a4', child: Text('A4 عادي')), DropdownMenuItem(value: '58', child: Text('إيصال حراري 58 مم')), DropdownMenuItem(value: '80', child: Text('إيصال حراري 80 مم'))], onChanged: (v) => setState(() => paper = v ?? 'a4')),
    const SizedBox(height: 12), const Text('احفظ بيانات الشركة ليظهر اللوجو والتليفونات والنص في طباعة المدير والموظف.'),
    const SizedBox(height: 20), FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save), label: const Text('حفظ الإعدادات')),
    const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => printTestPage(context, paper), icon: const Icon(Icons.print), label: const Text('اختيار الطابعة وطباعة صفحة تجربة')),
    const Text('طابعة البلوتوث تظهر في شاشة الطباعة إذا كانت متصلة بالموبايل ولها خدمة طباعة متوافقة.'),
    const SizedBox(height: 14),
    Card(child: ListTile(
      leading: const Icon(Icons.fingerprint, color: gold),
      title: const Text('استرجاع كلمة السر بالبصمة'),
      subtitle: const Text('يعمل تلقائيًا ومجانًا على نفس الموبايل بعد أول تسجيل دخول ناجح، بدون SMS أو فوترة.'),
      onTap: () => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('الاسترجاع بالبصمة جاهز'),
          content: const Text('من شاشة الدخول اضغط «نسيت كلمة السر؟ استرجاع بالبصمة». يلزم أن يكون الحساب سبق تسجيل دخوله بنجاح على نفس الموبايل.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('تمام'),
            ),
          ],
        ),
      ),
    )),
    const SizedBox(height: 8),
    const Card(child: ListTile(leading: Icon(Icons.cloud_done, color: gold), title: Text('حفظ البيانات طويل المدة'), subtitle: Text('الفواتير والحركات لا تُحذف وتظل محفوظة في قاعدة البيانات.'))),
    const SizedBox(height: 10),
    Card(child: ListTile(
      leading: const Icon(Icons.cloud_upload, color: gold),
      title: const Text('إضافة نسخة احتياطية على Google Drive'),
      subtitle: const Text('يتم إنشاء ملف نسخة احتياطية ثم اختيار Google Drive من شاشة المشاركة.'),
      onTap: () => backupToDrive(context),
    )),
    Card(child: ListTile(leading: const Icon(Icons.upload_file, color: gold), title: const Text('إضافة الأصناف من ملف'), subtitle: const Text('إضافة أسماء الأصناف وأسعار الشراء والبيع والكميات من ملف الأصناف المجهّز.'), onTap: () => openProductImport(context))),
    Card(child: ListTile(
      leading: const Icon(Icons.cloud_download, color: gold),
      title: const Text('سحب نسخة احتياطية من Google Drive'),
      subtitle: const Text('اختر ملف VIB Backup من Google Drive أو ملفات الهاتف لاسترجاع البيانات.'),
      onTap: () => restoreFromDrive(context),
    )),
    const SizedBox(height: 10),
    Card(
      child: ListTile(
        leading: const Icon(Icons.restart_alt, color: Colors.redAccent),
        title: const Text('تصفير البرنامج'),
        subtitle: const Text('يمسح بيانات التشغيل والحسابات والمخزون والفواتير مع الاحتفاظ بتسجيل الدخول وإعدادات الشركة والفروع والموظفين.'),
        onTap: () => resetProgram(context),
      ),
    ),
  ]);
}

const _backupCollections = <String>[
  'products',
  'stock',
  'stockMovements',
  'stockAdjustments',
  'sales',
  'purchases',
  'salesReturns',
  'purchaseReturns',
  'customers',
  'suppliers',
  'accountMovements',
  'receipts',
  'branches',
  'settings',
];

dynamic _encodeBackupValue(dynamic value) {
  if (value is Timestamp) {
    return {'__vibType': 'timestamp', 'milliseconds': value.millisecondsSinceEpoch};
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', _encodeBackupValue(item)));
  }
  if (value is Iterable) {
    return value.map(_encodeBackupValue).toList();
  }
  return value;
}

dynamic _decodeBackupValue(dynamic value) {
  if (value is Map) {
    if (value['__vibType'] == 'timestamp' && value['milliseconds'] is num) {
      return Timestamp.fromMillisecondsSinceEpoch((value['milliseconds'] as num).toInt());
    }
    return value.map((key, item) => MapEntry('$key', _decodeBackupValue(item)));
  }
  if (value is List) return value.map(_decodeBackupValue).toList();
  return value;
}

Future<void> backupToDrive(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final notice = messenger.showSnackBar(const SnackBar(content: Text('جاري تجهيز النسخة الاحتياطية...'), duration: Duration(minutes: 2)));
  try {
    final collections = <String, dynamic>{};
    for (final name in _backupCollections) {
      final snap = await db.collection(name).get();
      collections[name] = {
        for (final doc in snap.docs) doc.id: _encodeBackupValue(doc.data()),
      };
    }

    final payload = {
      'app': 'VIB Sales',
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'projectId': _vibProjectId,
      'collections': collections,
    };

    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
    final file = File('${dir.path}/VIB-BACKUP-$stamp.json');
    await file.writeAsString(jsonEncode(payload), flush: true);

    notice.close();
    await Share.shareXFiles([XFile(file.path)], text: 'نسخة احتياطية VIB Sales - اختر Google Drive للحفظ');
  } catch (e) {
    notice.close();
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text('تعذر إنشاء النسخة الاحتياطية: $e')));
  }
}

Future<void> _clearCollectionForRestore(String name) async {
  while (true) {
    final snap = await db.collection(name).limit(400).get();
    if (snap.docs.isEmpty) break;
    final batch = db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    if (snap.docs.length < 400) break;
  }
}

Future<void> restoreFromDrive(BuildContext context) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty || !context.mounted) return;

  Uint8List? bytes = picked.files.single.bytes;
  final path = picked.files.single.path;
  if (bytes == null && path != null) bytes = await File(path).readAsBytes();
  if (bytes == null) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر قراءة ملف النسخة الاحتياطية')));
    return;
  }

  Map<String, dynamic> payload;
  try {
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map) throw const FormatException('صيغة غير صحيحة');
    payload = Map<String, dynamic>.from(raw);
    if (payload['app'] != 'VIB Sales' || payload['collections'] is! Map) throw const FormatException('الملف ليس نسخة VIB Sales');
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ملف النسخة الاحتياطية غير صالح: $e')));
    return;
  }

  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('استرجاع النسخة الاحتياطية'),
      content: const Text('سيتم استبدال بيانات التشغيل الحالية بالبيانات الموجودة داخل ملف النسخة الاحتياطية. تسجيل الدخول لن يتم حذفه.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('استرجاع')),
      ],
    ),
  ) ?? false;
  if (!yes || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final notice = messenger.showSnackBar(const SnackBar(content: Text('جاري استرجاع النسخة الاحتياطية...'), duration: Duration(minutes: 3)));

  try {
    final collections = Map<String, dynamic>.from(payload['collections'] as Map);
    for (final name in _backupCollections) {
      await _clearCollectionForRestore(name);
      final rawDocs = collections[name];
      if (rawDocs is! Map || rawDocs.isEmpty) continue;

      var batch = db.batch();
      var count = 0;
      for (final entry in rawDocs.entries) {
        final data = entry.value;
        if (data is! Map) continue;
        batch.set(db.collection(name).doc('${entry.key}'), Map<String, dynamic>.from(_decodeBackupValue(data) as Map));
        count++;
        if (count == 400) {
          await batch.commit();
          batch = db.batch();
          count = 0;
        }
      }
      if (count > 0) await batch.commit();
    }

    notice.close();
    if (context.mounted) messenger.showSnackBar(const SnackBar(content: Text('تم استرجاع النسخة الاحتياطية بنجاح')));
  } catch (e) {
    notice.close();
    if (context.mounted) messenger.showSnackBar(SnackBar(content: Text('تعذر استرجاع النسخة الاحتياطية: $e')));
  }
}

Future<void> resetProgram(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
        SizedBox(width: 8),
        Expanded(child: Text('تصفير البرنامج')),
      ]),
      content: const Text(
        'سيبدأ البرنامج دورة جديدة من الصفر: سيتم تصفير المخزون والصندوق وأرصدة العملاء والموردين وإخفاء المنتجات والفواتير والحركات القديمة من البرنامج.\n\n'
        'تسجيل الدخول والفروع والموظفون وإعدادات الشركة ستظل محفوظة.\n\n'
        'هل تريد تنفيذ التصفير الآن؟',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(c, true),
          icon: const Icon(Icons.restart_alt),
          label: const Text('نعم، صفّر البرنامج'),
        ),
      ],
    ),
  ) ?? false;
  if (!accepted || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final progress = messenger.showSnackBar(
    const SnackBar(content: Text('جاري تصفير البرنامج...'), duration: Duration(minutes: 3)),
  );

  try {
    final resetAt = Timestamp.now();

    // Hide all current products without deleting them.
    final products = await db.collection('products').get();
    for (var i = 0; i < products.docs.length; i += 400) {
      final batch = db.batch();
      for (final doc in products.docs.skip(i).take(400)) {
        batch.update(doc.reference, {
          'active': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    // Zero all stock balances using update (allowed by the current production rules).
    final stock = await db.collection('stock').get();
    for (var i = 0; i < stock.docs.length; i += 400) {
      final batch = db.batch();
      for (final doc in stock.docs.skip(i).take(400)) {
        batch.update(doc.reference, {'quantity': 0});
      }
      await batch.commit();
    }

    // Zero and hide customers and suppliers.
    for (final collection in ['customers', 'suppliers']) {
      final snap = await db.collection(collection).get();
      for (var i = 0; i < snap.docs.length; i += 400) {
        final batch = db.batch();
        for (final doc in snap.docs.skip(i).take(400)) {
          batch.update(doc.reference, {
            'openingBalance': 0,
            'balance': 0,
            'active': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    }

    // Store the reset boundary on every user so manager and employees start from the same clean cycle.
    final users = await db.collection('users').get();
    for (var i = 0; i < users.docs.length; i += 400) {
      final batch = db.batch();
      for (final doc in users.docs.skip(i).take(400)) {
        batch.update(doc.reference, {'resetAt': resetAt});
      }
      await batch.commit();
    }

    await db.collection('settings').doc('main').set({
      'resetAt': resetAt,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await db.collection('settings').doc('cash').set({
      'balance': 0,
      'updatedAt': FieldValue.serverTimestamp(),
      'resetBy': FirebaseAuth.instance.currentUser?.uid,
    }, SetOptions(merge: true));

    activeResetAt = resetAt;

    final stockCheck = await db.collection('stock').get();
    final hasStock = stockCheck.docs.any((d) => ((d.data()['quantity'] as num?)?.toInt() ?? 0) != 0);
    final activeProducts = await db.collection('products').where('active', isEqualTo: true).limit(1).get();
    final activeCustomers = await db.collection('customers').where('active', isEqualTo: true).limit(1).get();
    final activeSuppliers = await db.collection('suppliers').where('active', isEqualTo: true).limit(1).get();
    final cashCheck = await db.collection('settings').doc('cash').get();
    final cashBalance = (cashCheck.data()?['balance'] as num?)?.toDouble() ?? 0;

    if (hasStock || activeProducts.docs.isNotEmpty || activeCustomers.docs.isNotEmpty ||
        activeSuppliers.docs.isNotEmpty || cashBalance != 0) {
      throw Exception('بعض الأرصدة لم يتم تصفيرها بالكامل');
    }

    progress.close();
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تم التصفير'),
          content: const Text('تم بدء دورة جديدة من الصفر. الفواتير والحركات القديمة محفوظة في قاعدة البيانات للأرشيف لكنها لن تظهر أو تدخل في التقارير الجديدة.'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('تم')),
          ],
        ),
      );
    }
  } catch (e) {
    progress.close();
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('التصفير لم يكتمل'),
          content: SelectableText('السبب: $e'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق')),
          ],
        ),
      );
    }
  }
}

PdfPageFormat invoicePageFormat(String paper) => switch (paper) {
  '58' => PdfPageFormat(58 * PdfPageFormat.mm, 180 * PdfPageFormat.mm, marginAll: 3 * PdfPageFormat.mm),
  '80' => PdfPageFormat(80 * PdfPageFormat.mm, 180 * PdfPageFormat.mm, marginAll: 4 * PdfPageFormat.mm),
  _ => PdfPageFormat.a4,
};

Future<void> printTestPage(BuildContext context, String paper) async {
  try {
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    final pdf = pw.Document();
    pdf.addPage(pw.Page(pageFormat: invoicePageFormat(paper), build: (_) => pw.Center(child: pw.Text('VIB للتجارة والتوزيع\nتجربة الطباعة\n${paper == 'a4' ? 'A4' : '$paper مم'}', textAlign: pw.TextAlign.center,
      style: pw.TextStyle(font: font, fontSize: paper == 'a4' ? 22 : 11)))));
    await Printing.layoutPdf(name: 'VIB-PRINT-TEST.pdf', onLayout: (_) => pdf.save());
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر فتح الطباعة: $e')));
  }
}

Future<void> invoiceActions(BuildContext context, String type, String id, Map<String, dynamic> data, {bool canReturn = true}) async {
  try{data=await numberedInvoiceData(type,id,data);}catch(e){if(context.mounted)await showInvoiceSaveProblem(context,'تعذر تخصيص رقم الفاتورة: $e');return;}
  final returned = data['status'] == 'returned';
  final profile = (await db.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get()).data();
  if (!context.mounted) return;
  final canPrint = profile?['role'] == 'owner' || profile?['canPrint'] == true;
  await showModalBottomSheet<void>(context: context, builder: (c) => SafeArea(child: Wrap(children: [
    ListTile(leading: const Icon(Icons.picture_as_pdf, color: gold), title: const Text('حفظ أو مشاركة الفاتورة PDF'), onTap: () { Navigator.pop(c); exportInvoicePdf(context, type, id, data); }),
    if (type == 'sales' && !returned && profile?['role'] == 'owner') ListTile(leading: const Icon(Icons.credit_card, color: gold), title: const Text('رابط دفع بالكارت — جيديا'), onTap: () { Navigator.pop(c); openGeideaPayments(context, invoiceId:id); }),
    if (type != 'sales' && !returned && profile?['role'] == 'owner') ListTile(leading: const Icon(Icons.playlist_add, color: gold), title: const Text('إضافة بند جديد لنفس الفاتورة'), onTap: () { Navigator.pop(c); appendInvoiceDialog(context, type, id); }),
    if(canPrint && data['internalNumber'] is int)ListTile(leading:const Icon(Icons.qr_code,color:gold),title:const Text('طباعة باركود الفاتورة'),onTap:(){Navigator.pop(c);printInvoiceBarcode(context,type,id,data);}),
    if (canPrint) ListTile(leading: const Icon(Icons.print, color: gold), title: Text(data['printedAt'] == null ? 'طباعة الفاتورة' : 'إعادة طباعة الفاتورة'), onTap: () { Navigator.pop(c); selectInvoicePaper(context, type, id, data); }),
    if (type == 'sales' && '${data['customerPhone'] ?? ''}'.trim().isNotEmpty) ListTile(leading: const Icon(Icons.chat, color: Colors.greenAccent), title: const Text('إرسال للزبون على واتساب'), onTap: () { Navigator.pop(c); sendInvoiceWhatsApp(context, id, data); }),
    if (canReturn) ListTile(leading: Icon(Icons.undo, color: returned ? Colors.grey : Colors.redAccent), title: Text(returned ? 'تم إرجاع الفاتورة' : type == 'sales' ? 'إرجاع فاتورة المبيعات' : 'إرجاع فاتورة المشتريات'), enabled: !returned, onTap: returned ? null : () { Navigator.pop(c); confirmReturn(context, type, id, data); }),
  ])));
}

Future<void> appendInvoiceLocally(String type, String id, int revision,
    String requestId, List<Map<String, dynamic>> additions, double extraPaid) async {
  int cents(num value) => (value * 100).round();
  final actor = FirebaseAuth.instance.currentUser!.uid;
  final invoiceRef = db.collection(type).doc(id);
  final editRef = db.collection('invoiceEdits').doc(requestId);
  final requestKey = jsonEncode({'type': type, 'id': id, 'revision': revision,
    'items': additions, 'paid': extraPaid});
  await db.runTransaction((tx) async {
    final profile = (await tx.get(db.collection('users').doc(actor))).data();
    if (profile?['active'] != true || profile?['role'] != 'owner') {
      throw Exception('تعديل الفاتورة متاح للمدير فقط');
    }
    final previousEdit = (await tx.get(editRef)).data();
    if (previousEdit != null) {
      if (previousEdit['actorId'] != actor || previousEdit['requestKey'] != requestKey) {
        throw Exception('طلب التعديل محفوظ ببيانات مختلفة');
      }
      return;
    }
    final old = (await tx.get(invoiceRef)).data();
    if (old == null || old['status'] != 'completed') throw Exception('الفاتورة غير متاحة للتعديل');
    if(type=='sales' && old['onlinePaymentEver']==true)throw StateError('الفاتورة لها سداد بالكارت؛ أنشئ فاتورة جديدة');
    if ((old['revision'] ?? 0) != revision) throw Exception('الفاتورة اتعدلت؛ افتحها من جديد');
    if (old['total'] is! num || old['paid'] is! num || old['due'] is! num ||
        cents(old['total'] as num) - cents(old['paid'] as num) != cents(old['due'] as num)) {
      throw Exception('هذه فاتورة قديمة تحتاج مراجعة أرصدتها قبل إضافة بنود');
    }
    final purchase = type == 'purchases';
    final stockBranch = purchase ? 'main' : '${old['stockBranchId'] ?? old['branchId'] ?? ''}';
    if (stockBranch.isEmpty) throw Exception('مخزون الفاتورة غير صحيح');
    final productSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];
    final stockSnaps = <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final row in additions) {
      productSnaps.add(await tx.get(db.collection('products').doc('${row['productId']}')));
      stockSnaps.add(await tx.get(db.collection('stock').doc('${stockBranch}_${row['productId']}')));
    }
    final accountId = '${old[purchase ? 'supplierId' : 'customerId'] ?? ''}';
    final accountRef = accountId.isEmpty ? null : db.collection(purchase ? 'suppliers' : 'customers').doc(accountId);
    final account = accountRef == null ? null : (await tx.get(accountRef)).data();
    final cashRef = db.collection('settings').doc('cash');
    final cash = (await tx.get(cashRef)).data();
    final items = (old['items'] is List && (old['items'] as List).isNotEmpty)
      ? (old['items'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList()
      : <Map<String, dynamic>>[{'productId': old['productId'], 'productName': old['productName'],
          'quantity': old['quantity'], purchase ? 'unitCost' : 'unitPrice': old[purchase ? 'unitCost' : 'unitPrice'],
          'lineTotal': old['total'], if (old['purchasePriceAtSale'] != null) 'purchasePriceAtSale': old['purchasePriceAtSale']}];
    var addedTotal = 0;
    final added = <Map<String, dynamic>>[];
    for (var i = 0; i < additions.length; i++) {
      final row = additions[i], product = productSnaps[i].data();
      final quantity = row['quantity'] as int;
      final rawPrice = (row['unitPrice'] as num).toDouble();
      if (!rawPrice.isFinite || rawPrice < 0) throw Exception('راجع سعر البند');
      final price = cents(rawPrice);
      final lineCents = purchase ? cents(rawPrice * quantity) : price * quantity;
      if (product == null || product['active'] != true || quantity <= 0 || quantity > 1000000 || price < 0) {
        throw Exception('راجع الصنف والسعر والكمية');
      }
      if (!purchase && product['purchasePrice'] is num && price < cents(product['purchasePrice'] as num)) {
        throw Exception('سعر البيع أقل من التكلفة');
      }
      final available = (stockSnaps[i].data()?['quantity'] as num?)?.toInt() ?? 0;
      if (!purchase && available < quantity) throw Exception('الكمية غير متاحة للصنف ${product['name']}');
      final key = purchase ? 'unitCost' : 'unitPrice';
      final matching = items.where((x) => x['productId'] == row['productId']);
      final existing = matching.isEmpty ? null : matching.first;
      if (existing != null && (purchase
          ? ((existing[key] as num).toDouble() - rawPrice).abs() > 0.000000001
          : cents(existing[key] as num) != price)) throw Exception('الصنف موجود بسعر مختلف');
      final addition = <String, dynamic>{'productId': row['productId'], 'productName': product['name'],
        'quantity': quantity, key: purchase ? rawPrice : price / 100, 'lineTotal': lineCents / 100,
        if (!purchase) 'purchasePriceAtSale': (product['purchasePrice'] as num?)?.toDouble() ?? 0};
      addedTotal += lineCents;
      if (existing == null) {
        items.add(Map<String, dynamic>.from(addition));
      } else {
        final oldQty = existing['quantity'] as int;
        if (!purchase && existing['purchasePriceAtSale'] is num) {
          existing['purchasePriceAtSale'] = ((existing['purchasePriceAtSale'] as num) * oldQty +
            (addition['purchasePriceAtSale'] as num) * quantity) / (oldQty + quantity);
        }
        existing['quantity'] = oldQty + quantity;
        existing['lineTotal'] = (cents(existing['lineTotal'] as num) + lineCents) / 100;
      }
      added.add(addition);
    }
    final payment = cents(extraPaid), addedDue = addedTotal - payment;
    if (purchase && cents((cash?['balance'] as num?) ?? 0) < payment) throw Exception('رصيد الصندوق لا يكفي لسداد المشتريات');
    if (additions.isEmpty || items.length > 50 || addedTotal > 1000000000000 || payment < 0 || addedDue < 0) {
      throw Exception('راجع البنود وقيمة المدفوع');
    }
    if ((purchase || addedDue > 0) && (account == null || account['active'] == false)) {
      throw Exception('الفاتورة غير مرتبطة بحساب نشط');
    }
    for (var i = 0; i < added.length; i++) {
      final row = added[i];
      final after = ((stockSnaps[i].data()?['quantity'] as num?)?.toInt() ?? 0) +
        (purchase ? row['quantity'] as int : -(row['quantity'] as int));
      tx.set(stockSnaps[i].reference, {'branchId': stockBranch, 'productId': row['productId'],
        'quantity': after, if (!purchase) 'lastSaleId': id}, SetOptions(merge: true));
      tx.set(db.collection('stockMovements').doc('${requestId}_item_$i'), {
        'productId': row['productId'], 'productName': row['productName'], 'branchId': stockBranch,
        'kind': purchase ? 'purchase' : 'sale', 'quantity': purchase ? row['quantity'] : -(row['quantity'] as int),
        'balanceAfter': after, 'referenceId': id, 'editId': requestId, 'actorId': actor,
        'createdAt': FieldValue.serverTimestamp()});
      if (purchase) tx.update(productSnaps[i].reference, {'purchasePrice': row['unitCost'], 'updatedAt': FieldValue.serverTimestamp()});
    }
    if (addedDue > 0) {
      final before = cents((account!['balance'] as num?) ?? 0);
      tx.update(accountRef!, {'balance': (before + addedDue) / 100, 'updatedAt': FieldValue.serverTimestamp()});
      tx.set(db.collection('accountMovements').doc('${requestId}_account'), {
        'accountType': purchase ? 'suppliers' : 'customers', 'accountId': accountId, 'accountName': account['name'],
        'kind': purchase ? 'purchase' : 'sale', 'amount': addedDue / 100, 'balanceBefore': before / 100,
        'balanceAfter': (before + addedDue) / 100, 'referenceId': id, 'editId': requestId,
        'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
    }
    if (payment > 0) {
      final before = cents((cash?['balance'] as num?) ?? 0), delta = purchase ? -payment : payment;
      tx.set(cashRef, {'balance': (before + delta) / 100, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      tx.set(db.collection('accountMovements').doc('${requestId}_cash'), {
        'accountType': 'cash', 'accountId': accountId, 'accountName': account?['name'] ?? '',
        'kind': purchase ? 'purchase' : 'sale', 'amount': payment / 100, 'delta': delta / 100,
        'balanceBefore': before / 100, 'balanceAfter': (before + delta) / 100,
        'referenceId': id, 'editId': requestId, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
    }
    final total = cents(old['total'] as num) + addedTotal, paid = cents(old['paid'] as num) + payment;
    tx.update(invoiceRef, {'items': items, 'itemCount': items.length, 'total': total / 100, 'paid': paid / 100,
      'due': (total - paid) / 100, 'paymentStatus': total > paid ? 'credit' : 'cash',
      'revision': revision + 1, 'updatedAt': FieldValue.serverTimestamp(), 'lastEditedBy': actor,
      if (purchase) 'cashPaidPosted': (cents((old['cashPaidPosted'] as num?) ?? 0) + payment) / 100,
      if (!purchase) 'customerBalanceAfter': account == null ? 0 :
        (cents((account['balance'] as num?) ?? 0) + addedDue) / 100,
      if (items.length == 1) ...{'productId': items.first['productId'], 'productName': items.first['productName'],
        'quantity': items.first['quantity'], purchase ? 'unitCost' : 'unitPrice': items.first[purchase ? 'unitCost' : 'unitPrice']}});
    tx.set(editRef, {'invoiceId': id, 'invoiceType': type, 'addedItems': added, 'totalAdded': addedTotal / 100,
      'paidAdded': payment / 100, 'revision': revision + 1, 'requestKey': requestKey,
      'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
  });
}

Future<void> appendInvoiceDialog(BuildContext context, String type, String id, {bool replaceSale = false}) async {
  final List<SaleLine> lines = [];
  final paid = TextEditingController(text: '0');
  final search = TextEditingController();
  try {
    final invoice = await db.collection(type).doc(id).get();
    final data = invoice.data();
    final products = (await db.collection('products').get()).docs;
    if (!context.mounted) return;
    if (data == null || data['status'] != 'completed' || products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الفاتورة أو الأصناف غير متاحة للتعديل')));
      return;
    }
    if (replaceSale) await assertSaleEditable({...data, 'id': id});
    if (!context.mounted) return;
    final purchase = type == 'purchases';
    final revision = (data['revision'] as num?)?.toInt() ?? 0;
    final requestId = db.collection('invoiceEdits').doc().id;
    final originalItems = replaceSale ? saleItems(data) : (data['items'] as List?) ?? const [];
    double priceFor(QueryDocumentSnapshot<Map<String, dynamic>> product) {
      for (final item in originalItems) {
        if (item is Map && item['productId'] == product.id) {
          return ((item[purchase ? 'unitCost' : 'unitPrice'] as num?)?.toDouble() ?? 0);
        }
      }
      return (product.data()[purchase ? 'purchasePrice' : 'price'] as num?)?.toDouble() ?? 0;
    }
    if (replaceSale) {
      for (final item in originalItems) {
        if (!products.any((p) => p.id == item['productId'])) throw Exception('صنف الفاتورة غير موجود');
        lines.add(SaleLine(productId: '${item['productId']}', unitPrice: (item['unitPrice'] as num).toDouble())..quantity.text = '${item['quantity']}');
      }
      paid.text = '${data['paid']}';
    } else if (!purchase) {
      lines.add(SaleLine(productId: products.first.id, unitPrice: priceFor(products.first)));
    }
    bool saving = false, cash = replaceSale ? data['paymentStatus'] == 'cash' :
      purchase ? ((data['due'] as num?)?.toDouble() ?? 0) == 0 : true;
    await showDialog<void>(context: context, barrierDismissible: false, builder: (dialog) => StatefulBuilder(
      builder: (c, update) {
        final addedTotal = lines.fold<double>(0, (sum, line) => sum +
          (int.tryParse(line.quantity.text) ?? 0) * (double.tryParse(line.price.text.replaceAll(',', '.')) ?? 0));
        final extraPaid = cash ? addedTotal : (double.tryParse(paid.text.replaceAll(',', '.')) ?? 0);
        return AlertDialog(
          title: Text(replaceSale ? 'تعديل فاتورة المبيعات' : 'إضافة بنود لنفس فاتورة ${purchase ? 'المشتريات' : 'المبيعات'}'),
          content: SizedBox(width: 620, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('رقم الفاتورة: ${invoiceDisplayNumber(type,id,data)}'),
            Text('الإجمالي السابق: ${data['total'] ?? 0} • المدفوع: ${data['paid'] ?? 0} • الباقي: ${data['due'] ?? 0}'),
            const SizedBox(height: 10),
            Text(replaceSale ? 'عدّل الأصناف والكميات والأسعار والمدفوع. يحفظ سجل التعديل وتُحدّث فروق المخزون والحسابات.' : 'البنود السابقة محفوظة؛ أضف البنود أو الكميات الإضافية هنا.'),
            TextField(controller: search, decoration: const InputDecoration(labelText: 'بحث عن صنف', prefixIcon: Icon(Icons.search)), onChanged: (_) => update(() {})),
            for (var i = 0; i < lines.length; i++)
              if (purchase) PurchaseInvoiceLine(
                key: ObjectKey(lines[i]), number: i + 1, name: '${products.firstWhere((p) => p.id == lines[i].productId).data()['name']}',
                cost: lines[i].price, quantity: lines[i].quantity, enabled: !saving, totalEditable: true, discountDraft: lines[i].discount,
                onChanged: () => update(() {}),
                onDelete: () => update(() { lines.removeAt(i).dispose(); }),
                onChoose: () async {
                  final selected = await pickPurchaseProduct(c, products.where((p) => p.data()['active'] == true).toList(),
                    lines.where((line) => line != lines[i]).map((line) => line.productId!).toSet());
                  if (selected == null || !c.mounted) return;
                  update(() {
                    lines[i].productId = selected;
                    lines[i].price.text = priceFor(products.firstWhere((p) => p.id == selected)).toStringAsFixed(2);
                  });
                },
              ) else Row(children: [
              Text('${i + 1}'),
              const SizedBox(width: 5),
              Expanded(flex: 4, child: DropdownButtonFormField<String>(
                initialValue: lines[i].productId, isExpanded: true,
                items: products.where((p) => p.id == lines[i].productId || '${p.data()['name']}'.toLowerCase().contains(search.text.trim().toLowerCase()))
                  .map((p) => DropdownMenuItem(value: p.id, child: Text('${p.data()['name']}', overflow: TextOverflow.ellipsis))).toList(),
                onChanged: saving ? null : (value) {
                  if (value == null) return;
                  update(() {
                    lines[i].productId = value;
                    lines[i].price.text = priceFor(products.firstWhere((p) => p.id == value)).toStringAsFixed(2);
                  });
                },
              )),
              const SizedBox(width: 5),
              Expanded(flex: 2, child: TextField(controller: lines[i].price, enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: purchase ? 'الشراء' : 'البيع'), onChanged: (_) => update(() {}))),
              const SizedBox(width: 5),
              Expanded(child: TextField(controller: lines[i].quantity, enabled: !saving,
                keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'العدد'), onChanged: (_) => update(() {}))),
              IconButton(onPressed: saving ? null : () => update(() { lines.removeAt(i).dispose(); }),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
            ]),
            TextButton.icon(onPressed: saving || lines.length >= 50 ? null : () async {
              if (!purchase) {
                update(() => lines.add(SaleLine(productId: products.first.id, unitPrice: priceFor(products.first))));
                return;
              }
              final selected = await pickPurchaseProduct(c, products.where((p) => p.data()['active'] == true).toList(),
                lines.where((line) => line.productId != null).map((line) => line.productId!).toSet());
              if (selected == null || !c.mounted) return;
              update(() => lines.add(SaleLine(productId: selected,
                unitPrice: priceFor(products.firstWhere((p) => p.id == selected)))));
            }, icon: const Icon(Icons.add), label: Text(purchase ? 'إضافة بند جديد' : 'إضافة بند')),
            SwitchListTile(title: Text(replaceSale ? 'مدفوع بالكامل' : 'دفع قيمة البنود المضافة بالكامل'), value: cash,
              onChanged: saving ? null : (value) => update(() => cash = value)),
            if (!cash) TextField(controller: paid, enabled: !saving, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: replaceSale ? 'إجمالي المدفوع في الفاتورة' : 'المدفوع عن البنود المضافة'), onChanged: (_) => update(() {})),
            Text('الإجمالي الجديد: ${((replaceSale ? 0 : (data['total'] as num?)?.toDouble() ?? 0) + addedTotal).toStringAsFixed(2)} ج.م'),
            Text('المدفوع الجديد: ${((replaceSale ? 0 : (data['paid'] as num?)?.toDouble() ?? 0) + extraPaid).toStringAsFixed(2)} ج.م'),
            Text('الباقي الجديد: ${((replaceSale ? 0 : (data['due'] as num?)?.toDouble() ?? 0) + addedTotal - extraPaid).toStringAsFixed(2)} ج.م'),
          ]))),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(c), child: const Text('إلغاء')),
            FilledButton(onPressed: saving ? null : () async {
              final items = <Map<String, dynamic>>[];
              final used = <String>{};
              for (final line in lines) {
                final quantity = int.tryParse(line.quantity.text);
                final price = double.tryParse(line.price.text.replaceAll(',', '.'));
                if (line.productId == null || quantity == null || quantity <= 0 || price == null ||
                    !price.isFinite || price < 0 || !used.add(line.productId!)) {
                  ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('راجع الأصناف والأسعار والكميات ولا تكرر الصنف')));
                  return;
                }
                items.add({'productId': line.productId, 'quantity': quantity, 'unitPrice': price});
              }
              if (items.isEmpty || !extraPaid.isFinite || extraPaid < 0 || extraPaid > addedTotal) {
                ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('راجع البنود وقيمة المدفوع')));
                return;
              }
              update(() => saving = true);
              try {
                if (replaceSale) {
                  await replaceSaleLocally(id, revision, requestId, items, extraPaid);
                } else {
                  await appendInvoiceLocally(type, id, revision, requestId, items, extraPaid);
                }
                if (c.mounted) Navigator.pop(c);
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تمت إضافة البنود وتحديث نفس الفاتورة والمخزون والحسابات')));
              } catch (e) {
                if (c.mounted) {
                  update(() => saving = false);
                  final message = 'تعذر حفظ التعديل: $e';
                  await showInvoiceSaveProblem(c, message);
                }
              }
            }, child: saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('حفظ على نفس الفاتورة')),
          ],
        );
      },
    ));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر فتح الفاتورة: $e')));
  } finally {
    for (final line in lines) { line.dispose(); }
    paid.dispose(); search.dispose();
  }
}

Future<void> sendInvoiceWhatsApp(BuildContext context, String id, Map<String, dynamic> data) async {
  var phone = '${data['customerPhone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
  if (phone.startsWith('0')) phone = '20${phone.substring(1)}';
  if (phone.startsWith('00')) phone = phone.substring(2);

  final lines = <String>[];
  final rawItems = (data['items'] as List?) ?? const [];
  if (rawItems.isNotEmpty) {
    for (var i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      if (item is Map) {
        lines.add('${i + 1}- ${item['productName'] ?? ''} × ${item['quantity'] ?? 0} = ${item['lineTotal'] ?? 0} ج.م');
      }
    }
  } else {
    lines.add('1- ${data['productName'] ?? ''} × ${data['quantity'] ?? 0} = ${data['total'] ?? 0} ج.م');
  }

  final message = 'فاتورة مبيعات VIB رقم $id\n${lines.join('\n')}\nالإجمالي: ${data['total'] ?? 0} ج.م\nالمدفوع: ${data['paid'] ?? data['total'] ?? 0} ج.م\nالباقي: ${data['due'] ?? 0} ج.م\nشكراً لتعاملكم معنا';
  final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح واتساب')));
  }
}




class InvoiceSaveButtonLabel extends StatelessWidget {
  final bool saving;
  const InvoiceSaveButtonLabel({super.key, required this.saving});
  @override Widget build(BuildContext context) => saving
    ? const Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8), Text('جاري حفظ الفاتورة…'),
      ])
    : const Text('حفظ الفاتورة');
}

String invoiceSaveFailureMessage(Object error) {
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') {
      return 'تعذر حفظ الفاتورة: الخادم رفض صلاحيات العملية. راجع تفعيل الحساب وقواعد حفظ الفواتير.\nرمز الخطأ: permission-denied';
    }
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
      return 'تعذر تأكيد حفظ الفاتورة بسبب الاتصال بالخادم. راجع الاتصال ثم حاول مرة أخرى من نفس الفاتورة.\nرمز الخطأ: ${error.code}';
    }
    if (error.code == 'unauthenticated') return 'انتهت جلسة الدخول. سجّل الدخول مرة أخرى ثم أعد المحاولة.';
  }
  return 'تعذر حفظ الفاتورة: $error';
}

Future<void> showInvoiceSaveProblem(BuildContext context, String message, {String title = 'تنبيه حفظ الفاتورة', String button = 'رجوع لتعديل الفاتورة', bool success = false}) async {
  if (!context.mounted) return;
  FocusScope.of(context).unfocus();
  await showDialog<void>(
    context: context, useRootNavigator: true, barrierDismissible: false,
    builder: (dialog) => Directionality(textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(children: [
          Icon(success ? Icons.check_circle_outline : Icons.error_outline, color: success ? Colors.green : Colors.orangeAccent), const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ]),
        content: SingleChildScrollView(child: SelectableText(message)),
        actions: [FilledButton(onPressed: () => Navigator.pop(dialog), child: Text(button))],
      )),
  );
}

class InvoiceSavedDialog extends StatelessWidget {
  final String invoiceId;
  const InvoiceSavedDialog({super.key, required this.invoiceId});
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, color: Colors.greenAccent, size: 52),
        SizedBox(height: 12),
        Text('تم حفظ الفاتورة بنجاح', textAlign: TextAlign.center),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('رقم الفاتورة: $invoiceId', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: () => Navigator.pop(context, 'print'),
          icon: const Icon(Icons.print), label: const Text('طباعة الفاتورة — A4 أو 80 مللي')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => Navigator.pop(context, 'share'),
          icon: const Icon(Icons.share), label: const Text('مشاركة PDF / إرسال على واتساب')),
        const SizedBox(height: 8),
        const Text('لإرسال الملف اختَر واتساب ثم العميل من قائمة المشاركة.', textAlign: TextAlign.center),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, 'close'), child: const Text('إغلاق'))],
    ),
  );
}

Future<void> showInvoiceSavedActions(BuildContext context, String type, String id, Map<String, dynamic> data) async {
  // Persistence already succeeded; output errors must never suggest saving again.
  if (!context.mounted) return;
  try {
    final action = await showDialog<String>(context: context, barrierDismissible: false,
      builder: (_) => Directionality(textDirection: TextDirection.rtl, child: InvoiceSavedDialog(invoiceId: invoiceDisplayNumber(type,id,data))));
    if (!context.mounted) return;
    if (action == 'print') await selectInvoicePaper(context, type, id, data);
    if (action == 'share') await exportInvoicePdf(context, type, id, data);
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('الفاتورة محفوظة بالفعل. يمكنك طباعتها أو مشاركة PDF من قائمة الفواتير.')));
  }
}

Future<void> selectInvoicePaper(BuildContext context, String type, String id, Map<String, dynamic> data) async {
  final selected = await showModalBottomSheet<String>(context: context, builder: (sheet) => SafeArea(child: Wrap(children: [
    const ListTile(title: Text('مقاس ورق الفاتورة')),
    for (final choice in [('a4', 'ورق A4'), ('58', 'إيصال 58 مم'), ('80', 'إيصال 80 مم')]) ListTile(title: Text(choice.$2), onTap: () => Navigator.pop(sheet, choice.$1)),
  ])));
  if (selected != null && context.mounted) await printInvoice(context, type, id, data, paperChoice: selected);
}

Future<Uint8List> createInvoicePdf(String type, String id, Map<String, dynamic> data,
    {String? paperChoice, Map<String, dynamic>? settingsOverride}) async {
  if(settingsOverride==null)data=await numberedInvoiceData(type,id,data);
  Map<String, dynamic> settings = settingsOverride ?? {};
  if (settingsOverride == null) {
    try {
      settings = (await db.collection('settings').doc('invoiceBranding').get()).data() ?? {};
      if (settings.isEmpty) settings = (await db.collection('settings').doc('main').get()).data() ?? {};
    } catch (_) { /* Authorized staff can print with the bundled VIB brand if settings are unavailable. */ }
  }
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  Uint8List logoBytes;
  try {
    logoBytes = base64Decode('${settings['logoBase64'] ?? ''}');
    if (logoBytes.isEmpty) throw const FormatException('No custom logo');
  } catch (_) {
    logoBytes = (await rootBundle.load('assets/icons/manager/mipmap-xxxhdpi/ic_launcher.png')).buffer.asUint8List();
  }
  final logo = pw.MemoryImage(logoBytes), pdf = pw.Document();
  final isSale = type == 'sales';
  final paper = paperChoice ?? (['a4', '58', '80'].contains(settings['paperSize']) ? '${settings['paperSize']}' : 'a4');
  final thermal = paper != 'a4', narrow = paper == '58';
  final size = thermal ? (narrow ? 8.0 : 9.0) : 10.0;
  final navy = thermal ? PdfColors.black : const PdfColor.fromInt(0xFF14263D);
  final accent = thermal ? PdfColors.black : const PdfColor.fromInt(0xFFB58A38);
  final pale = thermal ? PdfColors.white : const PdfColor.fromInt(0xFFF3F5F8);
  String money(dynamic value) => ((value as num?)?.toDouble() ?? 0).toStringAsFixed(2);
  String configured(String key, String fallback) {
    final value = '${settings[key] ?? ''}'.trim(); return value.isEmpty ? fallback : value;
  }
  final company = configured('companyName', 'VIB للتجارة والتوزيع');
  final address = configured('address', '');
  final taxNumber = configured('taxNumber', ''), commercialRegister = configured('commercialRegister', '');
  final phones = ['phone', 'phone2', 'whatsapp'].map((key) => configured(key, '')).where((x) => x.isNotEmpty).toSet().toList();
  final footer = configured('invoiceFooter', 'شكراً لتعاملكم معنا');
  final number=invoiceDisplayNumber(type,id,data);
  final barcode='${data['invoiceBarcode']??''}';
  final items = <Map<String, dynamic>>[];
  if (data['items'] is List) {
    for (final raw in data['items'] as List) { if (raw is Map) items.add(Map<String, dynamic>.from(raw)); }
  }
  if (items.isEmpty) items.add({'productName': data['productName'] ?? '', 'quantity': data['quantity'] ?? 0,
    isSale ? 'unitPrice' : 'unitCost': data[isSale ? 'unitPrice' : 'unitCost'] ?? 0, 'lineTotal': data['total'] ?? 0});
  double unit(Map<String, dynamic> item) => (item[isSale ? 'unitPrice' : 'unitCost'] as num?)?.toDouble() ?? 0;
  double lineTotal(Map<String, dynamic> item) => (item['lineTotal'] as num?)?.toDouble() ?? ((item['quantity'] as num?)?.toDouble() ?? 0) * unit(item);
  final total = (data['total'] as num?)?.toDouble() ?? 0;
  final paid = (data['paid'] as num?)?.toDouble() ?? (isSale ? total : 0);
  final due = (data['due'] as num?)?.toDouble() ?? total - paid;
  final receiptPaid = (data['receiptPaid'] as num?)?.toDouble() ?? 0;
  num? supplierBalance = ((data['revision'] as num?)?.toInt() ?? 0) == 0 ? data['supplierBalanceAfter'] as num? : null;
  bool liveSupplierBalance = false;
  if (!isSale && supplierBalance == null && settingsOverride == null && '${data['supplierId'] ?? ''}'.isNotEmpty) {
    try {
      supplierBalance = (await db.collection('suppliers').doc('${data['supplierId']}').get()).data()?['balance'] as num?;
      liveSupplierBalance = true;
    } catch (_) { /* Keep missing historical balances explicit instead of printing zero. */ }
  }
  final format = thermal ? (narrow ? PdfPageFormat(58 * PdfPageFormat.mm, double.infinity) : PdfPageFormat.roll80) : PdfPageFormat.a4;
  pw.Text text(String value, {double? fontSize, bool bold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.right}) =>
    pw.Text(value, textAlign: align, style: pw.TextStyle(fontSize: fontSize ?? size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? PdfColors.black));
  pw.Widget identifier(String label, String value) => pw.Row(children: [
    text('$label: '),
    pw.Directionality(textDirection: pw.TextDirection.ltr,
      child: text(value, align: pw.TextAlign.left)),
  ]);
  pw.Widget brand() => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    pw.Center(child: pw.Image(logo, width: thermal ? 38 : 62, height: thermal ? 38 : 62)),
    pw.SizedBox(height: 6), text(company, fontSize: thermal ? 12 : 22, bold: true, color: navy, align: pw.TextAlign.center),
    pw.SizedBox(height: 3), text('ALAA ELGNDY', fontSize: thermal ? 8 : 11, color: accent, align: pw.TextAlign.center),
    if (address.isNotEmpty) ...[pw.SizedBox(height: 4), text('العنوان: $address', fontSize: size, align: pw.TextAlign.center)],
    if (!thermal && (taxNumber.isNotEmpty || commercialRegister.isNotEmpty)) ...[
      pw.SizedBox(height: 6), pw.Row(children: [
        if (taxNumber.isNotEmpty) pw.Expanded(child: identifier('رقم البطاقة الضريبية', taxNumber)),
        if (commercialRegister.isNotEmpty) pw.Expanded(child: identifier('رقم السجل التجاري', commercialRegister)),
      ]),
    ],
    if (phones.isNotEmpty) ...[pw.SizedBox(height: 4), pw.Wrap(alignment: pw.WrapAlignment.center, spacing: 10, runSpacing: 3,
      children: phones.map((phone) => pw.Directionality(textDirection: pw.TextDirection.ltr, child: text(phone, fontSize: size, align: pw.TextAlign.center))).toList())],
    pw.SizedBox(height: thermal ? 7 : 12), pw.Divider(color: accent, thickness: thermal ? .7 : 1.5),
  ]);
  pw.Widget detail(String label, String value) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4),
    child: text('$label: $value', fontSize: size));
  pw.Widget summaryRow(String label, dynamic value, {bool strong = false}) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 6),
    decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: accent, width: .4))), child: pw.Row(children: [
      pw.Expanded(child: text(label, bold: strong)),
      text('${money(value)} ج.م', bold: strong, fontSize: strong ? size + 2 : size),
    ]));
  final table = pw.Table(columnWidths: {0: const pw.FlexColumnWidth(1.5), 1: const pw.FlexColumnWidth(1.4),
      2: const pw.FlexColumnWidth(.8), 3: const pw.FlexColumnWidth(4), 4: const pw.FlexColumnWidth(.5)},
    border: pw.TableBorder.all(color: accent, width: .6),
    children: [
      pw.TableRow(repeat: true, decoration: pw.BoxDecoration(color: navy), children: ['الإجمالي', 'العدد', 'السعر', 'المنتج', 'م']
        .map((v) => pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 9),
          child: text(v, bold: true, color: PdfColors.white, align: pw.TextAlign.center))).toList()),
      for (var i = 0; i < items.length; i++) pw.TableRow(decoration: pw.BoxDecoration(color: i.isEven ? pale : PdfColors.white),
        children: [money(lineTotal(items[i])), '${items[i]['quantity'] ?? 0}', money(unit(items[i])), '${items[i]['productName'] ?? ''}', '${i + 1}']
          .map((v) => pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 9),
            child: text(v, align: pw.TextAlign.center))).toList()),
    ]);
  final content = <pw.Widget>[
      brand(),
      pw.Container(padding: pw.EdgeInsets.all(thermal ? 6 : 12), decoration: pw.BoxDecoration(color: pale,
        border: pw.Border.all(color: thermal ? PdfColors.grey500 : accent, width: .7), borderRadius: pw.BorderRadius.circular(thermal ? 3 : 8)),
        child: text(isSale ? 'فاتورة مبيعات' : 'فاتورة مشتريات', fontSize: thermal ? 13 : 20, bold: true, color: navy, align: pw.TextAlign.center)),
      pw.SizedBox(height: 10), detail('رقم الفاتورة', number),
      if(!isSale && '${data['invoiceNumber']??''}'.trim().isNotEmpty)detail('رقم فاتورة المورد','${data['invoiceNumber']}'),
      if(barcode.isNotEmpty)pw.Padding(padding:const pw.EdgeInsets.symmetric(vertical:8),child:pw.BarcodeWidget(barcode:pw.Barcode.code128(),data:barcode,width:thermal?130:220,height:thermal?38:50,drawText:true,textStyle:const pw.TextStyle(fontSize:8))),
      detail('التاريخ', formatDate(data['createdAt'])),
      if (isSale) detail('العميل', '${data['customerName'] ?? ''}'.trim().isEmpty ? 'بيع نقدي' : '${data['customerName']}'),
      if (isSale && '${data['customerPhone'] ?? ''}'.trim().isNotEmpty) detail('هاتف العميل', '${data['customerPhone']}'),
      if (!isSale) detail('المورد', '${data['supplierName'] ?? ''}'),
      if (!isSale && '${data['supplierPhone'] ?? ''}'.trim().isNotEmpty) detail('هاتف المورد', '${data['supplierPhone']}'),
      pw.SizedBox(height: 8),
      if (thermal) ...[
        for (var i = 0; i < items.length; i++) pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 6),
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: .5))),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
            text('${i + 1}. ${items[i]['productName'] ?? ''}', bold: true), pw.SizedBox(height: 4),
            pw.Row(children: [pw.Expanded(child: text('${items[i]['quantity'] ?? 0} × ${money(unit(items[i]))}')),
              text('${money(lineTotal(items[i]))} ج.م', bold: true)]),
          ])),
      ] else table,
      pw.SizedBox(height: 12),
      pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: pw.BoxDecoration(color: pale,
        border: pw.Border.all(color: PdfColors.grey400, width: .6), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(children: [
          summaryRow('إجمالي الفاتورة', total, strong: true),
          if (isSale && data.containsKey('customerPreviousBalance'))
            summaryRow('الرصيد السابق', data['customerPreviousBalance']),
          if (isSale && data.containsKey('customerPreviousBalance'))
            summaryRow('الإجمالي المستحق', (data['customerPreviousBalance'] as num).toDouble() + total),
          if (!isSale && data.containsKey('supplierPreviousBalance'))
            summaryRow('الرصيد السابق للمورد', data['supplierPreviousBalance']),
          if (!isSale && data.containsKey('supplierPreviousBalance'))
            summaryRow('الإجمالي المستحق', (data['supplierPreviousBalance'] as num).toDouble() + total),
          summaryRow('المدفوع نقدًا', paid),
          if (receiptPaid > 0) summaryRow(data['onlinePaymentEver'] == true ? 'محصّل بعد الفاتورة' : 'محصّل بسندات قبض', receiptPaid),
          summaryRow('باقي هذه الفاتورة', due - receiptPaid, strong: true),
          if (isSale && data.containsKey('customerBalanceAfter'))
            summaryRow('رصيد العميل بعد الفاتورة', data['customerBalanceAfter'], strong: true),
          if (!isSale && supplierBalance != null)
            summaryRow(liveSupplierBalance ? 'إجمالي الباقي عليك للمورد حاليًا' : 'إجمالي الباقي عليك للمورد بعد السداد', supplierBalance, strong: true),
          if (!isSale && supplierBalance == null)
            text('إجمالي الباقي للمورد: الرصيد غير متاح', bold: true),
        ])),
      if (data['status'] == 'returned') ...[pw.SizedBox(height: 10), text('فاتورة مرتجعة', bold: true, color: PdfColors.red)],
      pw.SizedBox(height: 14),
    ];
  pw.Widget thanks() => pw.Column(children: [pw.Divider(color: PdfColors.grey400, thickness: .6),
    text(footer, align: pw.TextAlign.center, fontSize: thermal ? 8 : 10),
    if (!thermal) ...[pw.SizedBox(height: 12), pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [text('المستلم: ....................', fontSize: 9), text('الموظف: ....................', fontSize: 9)])],
  ]);
  if (thermal) {
    pdf.addPage(pw.Page(pageFormat: format, margin: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
      theme: pw.ThemeData.withFont(base: font, bold: font), textDirection: pw.TextDirection.rtl,
      build: (_) => pw.Column(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [...content, thanks()])));
  } else {
    pdf.addPage(pw.MultiPage(pageFormat: format, margin: const pw.EdgeInsets.all(18 * PdfPageFormat.mm),
      maxPages: 100, theme: pw.ThemeData.withFont(base: font, bold: font), textDirection: pw.TextDirection.rtl,
      footer: (context) => pw.Column(children: [thanks(),
        pw.Padding(padding: const pw.EdgeInsets.only(top: 5), child: text('صفحة ${context.pageNumber} / ${context.pagesCount}', fontSize: 8, align: pw.TextAlign.center))]),
      build: (_) => content));
  }
  return pdf.save();
}

Future<void> exportInvoicePdf(BuildContext context, String type, String id, Map<String, dynamic> data) async {
  try {
    final bytes = await createInvoicePdf(type, id, data, paperChoice: 'a4');
    await Printing.sharePdf(bytes: bytes, filename: '${type == 'sales' ? 'VIB-SALE' : 'VIB-PURCHASE'}-$id.pdf');
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء PDF: $e')));
  }
}

Future<void> printInvoice(BuildContext context, String type, String id, Map<String, dynamic> data, {String? paperChoice}) async {
  try {
    final bytes = await createInvoicePdf(type, id, data, paperChoice: paperChoice);
    await Printing.layoutPdf(name: '${type == 'sales' ? 'VIB-SALE' : 'VIB-PURCHASE'}-$id.pdf', onLayout: (_) async => bytes);
    await db.collection(type).doc(id).set({'printedAt': FieldValue.serverTimestamp(), 'printedBy': FirebaseAuth.instance.currentUser!.uid}, SetOptions(merge: true));
  } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الطباعة: $e'))); }
}

Future<void> confirmReturn(BuildContext context, String type, String id, Map<String, dynamic> data) async {
  try {
    final current = (await db.collection(type).doc(id).get(const GetOptions(source: Source.server))).data();
    if (current == null || current['status'] == 'returned' || !visibleAfterReset(current)) throw StateError('الفاتورة غير متاحة للمرتجع');
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
  ['status','revision','items','productId','quantity','branchId','stockBranchId','customerId','supplierId','total','due','paid','receiptPaid','onlinePaid','onlinePaymentEver','cashPosted','cashPaidPosted']) key:data[key]});

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
  String? productId, branchId;
  DateTimeRange? range;

  Future<Map<String, String>> _movementCounterparties(List<QueryDocumentSnapshot<Map<String, dynamic>>> rows) async {
    final result = <String, String>{};
    for (final row in rows) {
      final data = row.data();
      final kind = '${data['kind'] ?? ''}';
      final refId = '${data['referenceId'] ?? ''}';
      if (refId.isEmpty) {
        result[row.id] = _movementFallbackParty(data);
        continue;
      }

      try {
        String collection = '';
        if (kind == 'sale' || kind == 'correction_sale' || kind == 'correction_return') {
          collection = 'sales';
        } else if (kind == 'purchase') {
          collection = 'purchases';
        } else if (kind == 'sales_return') {
          collection = 'salesReturns';
        } else if (kind == 'purchase_return') {
          collection = 'purchaseReturns';
        }

        if (collection.isEmpty) {
          result[row.id] = _movementFallbackParty(data);
          continue;
        }

        final doc = await db.collection(collection).doc(refId).get();
        final invoice = doc.data();
        if (invoice == null) {
          result[row.id] = _movementFallbackParty(data);
          continue;
        }

        if (kind == 'purchase' || kind == 'purchase_return') {
          final supplier = '${invoice['supplierName'] ?? ''}'.trim();
          result[row.id] = supplier.isEmpty ? 'مورد غير مسجل' : 'المورد: $supplier';
        } else {
          final customer = '${invoice['customerName'] ?? ''}'.trim();
          final phone = '${invoice['customerPhone'] ?? ''}'.trim();
          result[row.id] = customer.isNotEmpty
              ? 'العميل: $customer${phone.isNotEmpty ? ' • $phone' : ''}'
              : (phone.isNotEmpty ? 'عميل هاتف: $phone' : 'بيع نقدي بدون عميل مسجل');
        }
      } catch (_) {
        result[row.id] = _movementFallbackParty(data);
      }
    }
    return result;
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

  Future<void> _printMovementReport(
    BuildContext context,
    String productName,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> rows,
    Map<String, String> parties,
    int currentQty,
  ) async {
    try {
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final pdf = pw.Document();
      final incoming = rows.fold<num>(0, (sum, d) => sum + (((d.data()['quantity'] as num?) ?? 0).clamp(0, 999999999)));
      final outgoing = rows.fold<num>(0, (sum, d) => sum + ((-((d.data()['quantity'] as num?) ?? 0)).clamp(0, 999999999)));

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (_) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.Text('VIB للتجارة والتوزيع', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text('تقرير حركة منتج: $productName', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text('الرصيد الحالي: $currentQty'),
              pw.Text('إجمالي الداخل: $incoming   •   إجمالي الخارج: $outgoing   •   عدد الحركات: ${rows.length}'),
              pw.SizedBox(height: 8),
            ]),
          ),
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Table(
              border: pw.TableBorder.all(width: .4),
              children: [
                pw.TableRow(children: ['الرصيد بعد الحركة', 'الكمية', 'الطرف/البيان', 'التاريخ', 'الحركة', 'م'].map((v) => pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Text(v, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                )).toList()),
                for (var i = 0; i < rows.length; i++)
                  pw.TableRow(children: [
                    '${rows[i].data()['balanceAfter'] ?? '-'}',
                    '${(rows[i].data()['quantity'] as num?) ?? 0}',
                    parties[rows[i].id] ?? '',
                    formatDate(rows[i].data()['createdAt']),
                    movementName('${rows[i].data()['kind']}'),
                    '${i + 1}',
                  ].map((v) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, textAlign: pw.TextAlign.center))).toList()),
              ],
            ),
          ),
        ],
      ));

      await Printing.layoutPdf(
        name: 'VIB-MOVEMENT-$productName-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.pdf',
        onLayout: (_) => pdf.save(),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء تقرير حركة المنتج: $e')));
      }
    }
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
            DropdownButtonFormField<String>(
              initialValue: productId,
              isExpanded: true,
              decoration: _vibInvoiceInput('اختر المنتج', icon: Icons.inventory_2_outlined),
              items: products.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => productId = v),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: branchId,
                isExpanded: true,
                decoration: _vibInvoiceInput('الفرع'),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('كل الفروع')),
                  const DropdownMenuItem(value: 'main', child: Text('المخزون الرئيسي')),
                  ...branches.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.data()['name']}', overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => branchId = v),
              )),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (r != null) setState(() => range = r);
                },
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(range == null ? 'كل الفترات' : '${DateFormat('dd/MM').format(range!.start)} - ${DateFormat('dd/MM').format(range!.end)}'),
              ),
            ]),
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
              stream: db.collection('stockMovements').where('productId', isEqualTo: productId).snapshots(),
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
                      (range == null || (date != null && !date.isBefore(range!.start) && date.isBefore(range!.end.add(const Duration(days: 1)))));
                }).toList()
                  ..sort((a, b) => ((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
                      .compareTo((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));

                final incoming = rows.fold<num>(0, (sum, d) => sum + (((d.data()['quantity'] as num?) ?? 0).clamp(0, 999999999)));
                final outgoing = rows.fold<num>(0, (sum, d) => sum + ((-((d.data()['quantity'] as num?) ?? 0)).clamp(0, 999999999)));

                return FutureBuilder<List<dynamic>>(
                  future: Future.wait([
                    _movementCounterparties(rows),
                    branchId == null
                        ? db.collection('stock').where('productId', isEqualTo: productId).get()
                        : db.collection('stock').doc('${branchId}_$productId').get(),
                    db.collection('products').doc(productId).get(),
                  ]),
                  builder: (context, details) {
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
                                onPressed: rows.isEmpty ? null : () => _printMovementReport(context, productName, rows, parties, currentQty),
                                icon: const Icon(Icons.picture_as_pdf, size: 18),
                                label: const Text('تقرير PDF'),
                              ),
                            ),
                          ]),
                        ),
                      ),
                      Expanded(
                        child: rows.isEmpty
                            ? const Center(child: Text('لا توجد حركات لهذا المنتج في الفترة المختارة'))
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: rows.length,
                                itemBuilder: (context, index) {
                                  final row = rows[index];
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
                                        'التاريخ: ${formatDate(x['createdAt'])}',
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


Future<String?> selectRegisteredCustomer(BuildContext context) async {
  String query = '';
  return showDialog<String>(context: context, builder: (dialog) => StatefulBuilder(
    builder: (dialog, update) => AlertDialog(
      title: const Text('اختيار عميل مسجل'),
      content: SizedBox(width: 500, height: 360, child: Column(children: [
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
              return ListTile(title: Text('${row.data()['name'] ?? ''}'),
                subtitle: Text('${row.data()['phone'] ?? ''} • الرصيد: ${row.data()['balance'] ?? 0} ج.م'),
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
  showInvoiceProductChoices(context,
    products:[for(final p in products) (id:p.id,name:'${p.data()['name'] ?? ''}')],
    excluded:added,unitCosts:{for(final p in products) p.id:p.data()['purchasePrice'] as num?},
    stockStreamFor:invoiceMainStock,
  );

class StaffCustomers extends StatefulWidget {
  const StaffCustomers({super.key});
  @override
  State<StaffCustomers> createState() => _StaffCustomersState();
}
class _StaffCustomersState extends State<StaffCustomers> {
  String query = '';
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(12), child: TextField(decoration: const InputDecoration(labelText: 'بحث عن عميل بالاسم أو الهاتف', prefixIcon: Icon(Icons.search)),
      onChanged: (value) => setState(() => query = value.trim().toLowerCase()))),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: db.collection('customers').snapshots(), builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('تعذر تحميل العملاء'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data!.docs.where((d) => d.data()['active'] != false && '${d.data()['name'] ?? ''} ${d.data()['phone'] ?? ''}'.toLowerCase().contains(query)).toList();
      if (rows.isEmpty) return const Center(child: Text('لا يوجد عملاء مطابقون'));
      return ListView.builder(itemCount: rows.length, itemBuilder: (context, index) {
        final data = rows[index].data();
        return ListTile(title: Text('${data['name'] ?? ''}'), subtitle: Text('${data['phone'] ?? ''}'),
          trailing: Text('الرصيد: ${data['balance'] ?? 0} ج.م', style: const TextStyle(color: gold)));
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
      final icon = Badge(isLabelVisible: unread, backgroundColor:Colors.greenAccent,smallSize:10,child: const Icon(Icons.chat_bubble_outline, color: gold));
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
              leading: Badge(isLabelVisible: unread, backgroundColor:Colors.greenAccent,smallSize:10,child: const Icon(Icons.person_outline, color: gold)),
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

Future<void> editSaleByNumber(BuildContext context) async {
  final number = TextEditingController();
  final id = await showDialog<String>(context: context, builder: (c) => AlertDialog(
    title: const Text('تعديل فاتورة'),
    content: TextField(controller: number, autofocus: true, decoration: const InputDecoration(labelText: 'رقم فاتورة المبيعات'),
      onSubmitted: (value) { if (value.trim().isNotEmpty) Navigator.pop(c, value.trim()); }),
    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
      FilledButton(onPressed: () { if (number.text.trim().isNotEmpty) Navigator.pop(c, number.text.trim()); }, child: const Text('فتح الفاتورة'))]));
  number.dispose();
  if (id == null || !context.mounted) return;
  if (id.contains('/')) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رقم الفاتورة غير صحيح'))); return;
  }
  try{final resolved=await resolveInvoiceNumber('sales',id);if(context.mounted)await appendInvoiceDialog(context,'sales',resolved,replaceSale:true);}catch(e){if(context.mounted)await showInvoiceSaveProblem(context,'تعذر فتح الفاتورة: $e');}
}

Future<void> assertSaleEditable(Map<String, dynamic> data) async {
  if(data['onlinePaymentEver']==true)throw StateError('الفاتورة لها سداد بالكارت؛ أنشئ فاتورة جديدة');
  if ('${data['receiptId'] ?? ''}'.isNotEmpty) throw Exception('الفاتورة مرتبطة بسند قبض ولا يمكن تعديلها');
  final customerId = '${data['customerId'] ?? ''}';
  if (customerId.isEmpty) return;
  final receipts = await db.collection('receipts').where('customerId', isEqualTo: customerId).get();
  final date = data['createdAt'] as Timestamp?;
  for (final receipt in receipts.docs) {
    final r = receipt.data(), receiptDate = receipt.data()['createdAt'] as Timestamp?;
    if (r['invoiceId'] == data['id'] ||
        ('${r['invoiceId'] ?? ''}'.isEmpty && (date == null || receiptDate == null || receiptDate.compareTo(date) >= 0))) {
      throw Exception('الفاتورة مرتبطة بسند قبض؛ السندات القديمة غير المحددة لفاتورة تحتاج مراجعة المدير');
    }
  }
}

Future<void> replaceSaleLocally(String id, int revision, String requestId,
    List<Map<String, dynamic>> replacements, double payment) async {
  int cents(num value) => (value * 100).round();
  final actor = FirebaseAuth.instance.currentUser!.uid;
  final ref = db.collection('sales').doc(id), edit = db.collection('invoiceEdits').doc(requestId);
  final key = jsonEncode({'id': id, 'revision': revision, 'items': replacements, 'paid': payment});
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
    if ('${old['receiptId'] ?? ''}'.isNotEmpty) throw Exception('الفاتورة مرتبطة بسند قبض');
    if (old['paid'] is! num || old['due'] is! num || cents(old['total']) - cents(old['paid']) != cents(old['due'])) throw Exception('الفاتورة القديمة تحتاج مراجعة المدفوع والباقي');
    final customerId = '${old['customerId'] ?? ''}';
    final customerRef = customerId.isEmpty ? null : db.collection('customers').doc(customerId);
    final customer = customerRef == null ? null : (await tx.get(customerRef)).data();
    final latestReceiptId = '${customer?['lastReceiptId'] ?? ''}';
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
      if (price < cents((product['purchasePrice'] as num?) ?? 0)) throw Exception('سعر البيع أقل من التكلفة');
      newQuantities[p] = q; total += q * price;
      final prior = original.where((x) => x['productId'] == p).toList();
      items.add({'productId': p, 'productName': product['name'], 'quantity': q, 'unitPrice': price / 100,
        'lineTotal': q * price / 100, 'purchasePriceAtSale': prior.isEmpty ? product['purchasePrice'] ?? 0 : prior.first['purchasePriceAtSale'] ?? 0});
    }
    final paid = cents(payment), due = total - paid;
    if (items.isEmpty || items.length > 50 || total > 1000000000000 || !payment.isFinite || paid < 0 || due < 0) throw Exception('راجع المدفوع وبنود الفاتورة');
    if (due > 0 && (customer == null || customer['active'] == false)) throw Exception('الفاتورة الآجلة تحتاج عميلًا نشطًا');
    final debtDelta = due - cents(old['due']), cashDelta = paid - cents(old['paid']);
    final cashBefore = cents((cash?['balance'] as num?) ?? 0), balanceBefore = cents((customer?['balance'] as num?) ?? 0);
    if (customer != null && balanceBefore + debtDelta < 0) throw Exception('التعديل يتعارض مع تحصيلات العميل');
    for (final p in ids) {
      final before = (stocks[p]!.data()?['quantity'] as num?)?.toInt() ?? 0;
      final delta = (oldQuantities[p] ?? 0) - (newQuantities[p] ?? 0), after = before + delta;
      if (after < 0) throw Exception('المخزون غير كافٍ للصنف ${products[p]!.data()?['name']}');
      if (delta == 0) continue;
      tx.set(stocks[p]!.reference, {'branchId': stockBranch, 'productId': p, 'quantity': after, 'lastSaleId': id}, SetOptions(merge: true));
      tx.set(db.collection('stockMovements').doc('${requestId}_$p'), {'productId': p, 'productName': products[p]!.data()?['name'],
        'branchId': stockBranch, 'kind': 'saleCorrection', 'quantity': delta, 'balanceAfter': after,
        'referenceId': id, 'editId': requestId, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
    }
    if (customerRef != null && debtDelta != 0) {
      tx.update(customerRef, {'balance': (balanceBefore + debtDelta) / 100, 'updatedAt': FieldValue.serverTimestamp()});
      tx.set(db.collection('accountMovements').doc('${requestId}_customer'), {'accountType': 'customers', 'accountId': customerId,
        'accountName': customer?['name'] ?? '', 'kind': 'saleCorrection', 'amount': debtDelta / 100,
        'balanceBefore': balanceBefore / 100, 'balanceAfter': (balanceBefore + debtDelta) / 100,
        'referenceId': id, 'editId': requestId, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
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
      'customerBalanceAfter': customer == null ? 0 : (balanceBefore + debtDelta) / 100,
      'productId': items.length == 1 ? items.first['productId'] : '', 'productName': items.length == 1 ? items.first['productName'] : '',
      'quantity': items.length == 1 ? items.first['quantity'] : 0, 'unitPrice': items.length == 1 ? items.first['unitPrice'] : 0});
    tx.set(edit, {'invoiceId': id, 'invoiceType': 'sales', 'beforeItems': original, 'afterItems': items,
      'totalBefore': old['total'], 'totalAfter': total / 100, 'paidBefore': old['paid'], 'paidAfter': paid / 100,
      'revision': revision + 1, 'requestKey': key, 'actorId': actor, 'createdAt': FieldValue.serverTimestamp()});
  });
}

({double debt, double cash}) returnSettlement(Map<String, dynamic> invoice, {required bool sales}) {
  int cents(String key) {
    final value = (invoice[key] as num?)?.toDouble() ?? 0;
    if (!value.isFinite || value < 0) throw StateError('قيمة مالية غير صحيحة');
    return (value * 100).round();
  }
  final due = cents('due'), paid = cents('paid'), receipts = sales ? cents('receiptPaid') : 0;
  if (receipts > due) throw StateError('سندات القبض تتجاوز باقي الفاتورة؛ راجع الحساب');
  if (invoice['total'] is num && cents('total') != due + paid) throw StateError('إجمالي الفاتورة لا يطابق المدفوع والآجل؛ راجع الحساب');
  if (!sales && cents('cashPaidPosted') > paid) throw StateError('المبلغ المصروف يتجاوز المدفوع بالفاتورة؛ راجع الحساب');
  return (debt: (due - receipts) / 100, cash: sales ? (paid + receipts) / 100 : (invoice['cashPosted'] == true ? paid / 100 : cents('cashPaidPosted') / 100));
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

