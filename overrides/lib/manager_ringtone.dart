part of 'main.dart';

const _vibRingtoneChannel = MethodChannel('vib.manager/ringtone');

Future<void> vibPlayManagerRingtone(AudioPlayer fallback) async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('vib_login_chime') ?? true)) return;
  try {
    final played = await _vibRingtoneChannel.invokeMethod<bool>('play');
    if (played == true) return;
  } catch (error) {
    debugPrint('Unable to play phone ringtone: ' + error.toString());
  }
  await fallback.play(AssetSource('login-chime.wav'), volume: .85);
}

Future<void> vibChooseManagerRingtone(BuildContext context) async {
  try {
    final selected = await _vibRingtoneChannel.invokeMethod<bool>('choose');
    if (context.mounted && selected == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('تم حفظ رنة الدخول من رنات الموبايل')));
    }
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text('تعذر اختيار الرنة: ' + error.toString())));
  }
}

Future<void> vibPreviewManagerRingtone(BuildContext context) async {
  final player = AudioPlayer();
  try {
    await vibPlayManagerRingtone(player);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تشغيل الرنة: $error')));
    }
  } finally {
    // Keep the fallback audio player alive long enough to hear the chime.
    await Future<void>.delayed(const Duration(seconds: 3));
    await player.dispose();
  }
}
