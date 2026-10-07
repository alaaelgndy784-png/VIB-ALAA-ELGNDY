from pathlib import Path
import shutil, sys
root=Path(sys.argv[1])
mode=sys.argv[2] if len(sys.argv)>2 else 'staff'
is_staff=mode != 'manager'
if mode not in ('staff','manager'):
    raise SystemExit('mode must be staff or manager')
p=root/'lib/main.dart'
s=p.read_text()
s=s.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:flutter/foundation.dart' show kIsWeb;")
s=s.replace('show AudioPlayer, DeviceFileSource;', 'show AudioPlayer, DeviceFileSource, UrlSource;')
s=s.replace("  final packageName = (await PackageInfo.fromPlatform()).packageName;", """  if (kIsWeb) {
    staffApp = " + ("true" if is_staff else "false") + ";
    return const FirebaseOptions(
      apiKey: String.fromEnvironment('FIREBASE_WEB_API_KEY', defaultValue: 'AIzaSyAhQPcgPFJHeVO3WfHFbXl5C8LjPw8MlpM'),
      appId: String.fromEnvironment('FIREBASE_WEB_APP_ID', defaultValue: '1:200962643703:web:f11fbe2ff566c7352c65f2'),
      messagingSenderId: _vibSenderId, projectId: _vibProjectId,
      authDomain: 'vib-sales.firebaseapp.com',
    );
  }
  final packageName = (await PackageInfo.fromPlatform()).packageName;""")
if is_staff:
    s=s.replace("          activeResetAt = data['resetAt'] as Timestamp?;", """          if (kIsWeb && data['role'] != 'employee') {
            return Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('الرابط ده لحسابات الموظفين فقط. افتح برنامج المدير لإدارة الحساب.'),
              TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('خروج')),
            ])));
          }
          activeResetAt = data['resetAt'] as Timestamp?;""")

# Firebase persists the browser session. Never store the PIN in browser storage.
s=s.replace("      await _secure.write(key: 'vib_saved_phone', value: number);\n      await _secure.write(key: 'vib_saved_pin', value: password);", "      if (!kIsWeb) {\n        await _secure.write(key: 'vib_saved_phone', value: number);\n        await _secure.write(key: 'vib_saved_pin', value: password);\n      }")
s=s.replace('          final dir = await getTemporaryDirectory();\n          audioFile', '          if (!kIsWeb) {\n          final dir = await getTemporaryDirectory();\n          audioFile',1)
s=s.replace('          await audioFile!.writeAsBytes(base64Decode(widget.encoded));', '          await audioFile!.writeAsBytes(base64Decode(widget.encoded));\n          }',1)
s=s.replace('await player!.play(DeviceFileSource(audioFile!.path));', "await player!.play(kIsWeb ? UrlSource('data:audio/mp4;base64,${widget.encoded}') : DeviceFileSource(audioFile!.path));")
s=s.replace("const SizedBox(width: 4), IconButton(tooltip: recording", "const SizedBox(width: 4), if (!kIsWeb) IconButton(tooltip: recording")
s=s.replace('Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420)', 'Widget build(BuildContext context) => Scaffold(body: Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420)')
s=s.replace('  ))));\n}\n\nconst managerNavy', '  )))));\n}\n\nconst managerNavy')
s=s.replace('      TextButton.icon(onPressed: busy ? null : recoverPasswordByBiometric', '      if (!kIsWeb) TextButton.icon(onPressed: busy ? null : recoverPasswordByBiometric')
s=s.replace("      const Text('استرجاع كلمة السر بالبصمة يعمل مجانًا على نفس الموبايل بعد أول تسجيل دخول ناجح. المدير يفعّل حساب الموظف ويحدد فرعه.'),", "      Text(kIsWeb ? 'ادخل بنفس رقمك ورقمك السري في برنامج الموظف. المدير يفعّل حسابك ويحدد فرعك.' : 'استرجاع كلمة السر بالبصمة يعمل مجانًا على نفس الموبايل بعد أول تسجيل دخول ناجح. المدير يفعّل حساب الموظف ويحدد فرعه.'),")
if not is_staff:
    s=s.replace("  Future<void> biometric() async {\n    setState", "  Future<void> biometric() async {\n    if (kIsWeb) { if (mounted) setState(() { checking = false; message = 'اكتب الرقم السري لفتح حساب المدير'; }); return; }\n    setState")
    s=s.replace("if (checking) const CircularProgressIndicator() else FilledButton.icon(onPressed: biometric", "if (checking) const CircularProgressIndicator() else if (!kIsWeb) FilledButton.icon(onPressed: biometric")
s=s.replace('ThemeData.dark(useMaterial3: true).copyWith(', "ThemeData(brightness: Brightness.dark, useMaterial3: true, fontFamily: 'VIBArabic').copyWith(")
s=s.replace('ThemeData.dark().textTheme.apply(bodyColor:', "ThemeData(brightness: Brightness.dark, fontFamily: 'VIBArabic').textTheme.apply(fontFamily: 'VIBArabic', bodyColor:")
p.write_text(s)
# Bundle Arabic glyphs instead of depending on a runtime font CDN.
p=root/'pubspec.yaml'
s=p.read_text().replace('flutter:\n  uses-material-design: true', 'flutter:\n  fonts:\n    - family: VIBArabic\n      fonts:\n        - asset: assets/fonts/DejaVuSans.ttf\n  uses-material-design: true')
p.write_text(s)
# Mobile OS notification plugin is native; live text chat remains available.
p=root/'lib/chat_alerts.dart';s=p.read_text().replace('    final token=++generation;','    if (kIsWeb) return;\n    final token=++generation;',1)
s=s.replace('  @override Widget build(BuildContext context) => IconButton(', '  @override Widget build(BuildContext context) => kIsWeb ? const SizedBox.shrink() : IconButton(')
p.write_text(s)
web=root/'web'
shutil.copyfile('web-staff/index.html',web/'index.html')
shutil.copyfile('web-staff/flutter_bootstrap.js',web/'flutter_bootstrap.js')
shutil.copyfile('web-staff/_headers',web/'_headers')
shutil.copyfile('web-staff/manifest.json',web/'manifest.json')
(web/'icons').mkdir(exist_ok=True)
icon = 'overrides/assets/staff-icon.png' if is_staff else 'overrides/assets/manager-icon.png'
for size in (512,):
    shutil.copyfile(icon,web/f'icons/Icon-{size}.png')
shutil.copyfile(icon,web/'favicon.png')
if not is_staff:
    p=web/'index.html'
    html=p.read_text().replace('VIB Staff','VIB Manager').replace('VIB — الموظف','VIB — المدير').replace('برنامج الموظف','برنامج المدير').replace('بوابة الموظف','برنامج المدير')
    p.write_text(html)
    p=web/'manifest.json'
    manifest=p.read_text().replace('VIB Staff','VIB Manager').replace('الموظف','المدير').replace('موظفي','مدير')
    p.write_text(manifest)
