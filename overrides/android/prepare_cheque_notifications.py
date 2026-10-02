from pathlib import Path
import shutil

manifest=Path('android/app/src/main/AndroidManifest.xml')
text=manifest.read_text()
permissions='''    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
'''
text=text.replace('<application',permissions+'    <application',1)
receivers='''        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
'''
text=text.replace('</application>',receivers+'    </application>',1)
manifest.write_text(text)
gradle=Path('android/app/build.gradle.kts');text=gradle.read_text()
text=text.replace('compileOptions {','compileOptions {\n        isCoreLibraryDesugaringEnabled = true',1)
text+='\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
gradle.write_text(text)
drawable=Path('android/app/src/main/res/drawable');drawable.mkdir(parents=True,exist_ok=True)
(drawable/'vib_notification.xml').write_text('''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF" android:pathData="M19,3h-1V1h-2v2H8V1H6v2H5c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2V5c0,-1.1 -0.9,-2 -2,-2zM19,19H5V8h14v11zM7,10h5v5H7z" />
</vector>''')
raw=Path('android/app/src/main/res/raw');raw.mkdir(parents=True,exist_ok=True)
(raw/'keep.xml').write_text('<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/vib_notification,@mipmap/ic_launcher" />')

