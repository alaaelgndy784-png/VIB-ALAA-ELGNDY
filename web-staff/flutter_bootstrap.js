{{flutter_js}}
{{flutter_build_config}}

window.vibReport?.('ملف بدء التشغيل وصل');
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
    canvasKitVariant: 'full',
    canvasKitForceCpuOnly: true
  },
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      window.vibReport?.('كود البرنامج وصل — جاري تجهيز الرسم');
      const appRunner = await engineInitializer.initializeEngine();
      window.vibReport?.('محرك الرسم جاهز — جاري فتح البرنامج');
      await appRunner.runApp();
      window.vibReport?.('تم بدء البرنامج');
    } catch (error) {
      window.vibReport?.('توقف التشغيل: ' + String(error).slice(0, 400));
      window.vibStartupFailed?.();
    }
  }
}).catch(function (error) {
  window.vibReport?.('توقف التحميل: ' + String(error).slice(0, 400));
  window.vibStartupFailed?.();
});
