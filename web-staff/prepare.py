from pathlib import Path
import json, shutil, sys
root=Path(sys.argv[1])
p=root/'lib/main.dart'
s=p.read_text()
s=s.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:flutter/foundation.dart' show kIsWeb;")
s=s.replace('show AudioPlayer, DeviceFileSource;', 'show AudioPlayer, DeviceFileSource, UrlSource;')
s=s.replace("  final packageName = (await PackageInfo.fromPlatform()).packageName;", """  if (kIsWeb) {
    staffApp = true;
    return const FirebaseOptions(
      apiKey: _vibApiKey,
      appId: String.fromEnvironment('FIREBASE_WEB_APP_ID', defaultValue: _staffFirebaseAppId),
      messagingSenderId: _vibSenderId, projectId: _vibProjectId,
      authDomain: 'vib-sales.firebaseapp.com',
    );
  }
  final packageName = (await PackageInfo.fromPlatform()).packageName;""")
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
p.write_text(s)
# Mobile OS notification plugin is native; live text chat remains available.
p=root/'lib/chat_alerts.dart';s=p.read_text().replace('    final token=++generation;','    if (kIsWeb) return;\n    final token=++generation;',1)
s=s.replace('  @override Widget build(BuildContext context) => IconButton(', '  @override Widget build(BuildContext context) => kIsWeb ? const SizedBox.shrink() : IconButton(')
p.write_text(s)
web=root/'web'
shutil.copyfile('web-staff/index.html',web/'index.html')
shutil.copyfile('web-staff/manifest.json',web/'manifest.json')
(web/'icons').mkdir(exist_ok=True)
for size in (192,512):
    shutil.copyfile('overrides/assets/staff-icon.png',web/f'icons/Icon-{size}.png')
shutil.copyfile('overrides/assets/staff-icon.png',web/'favicon.png')
