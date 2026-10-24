#!/usr/bin/env python3
"""Add Android's native ringtone picker for the manager only."""
from pathlib import Path
import sys
if len(sys.argv) != 2 or sys.argv[1] != "manager":
    raise SystemExit("Manager only: other APKs must remain unchanged")
target = Path("android/app/src/main/kotlin/com/alaa/vibsales/manager/MainActivity.kt")
if not target.exists():
    raise SystemExit("Manager MainActivity not found")
target.write_text(r'''package com.alaa.vibsales.manager

import android.app.Activity
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val requestCodeRingtone = 8041
    private var pendingRingtoneChoice: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "vib.manager/ringtone").setMethodCallHandler { call, result ->
            when (call.method) {
                "choose" -> {
                    if (pendingRingtoneChoice != null) {
                        result.error("BUSY", "A ringtone selection is already open", null)
                    } else {
                        try {
                            val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER)
                            intent.putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE,
                                RingtoneManager.TYPE_RINGTONE)
                            intent.putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            intent.putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                            val saved = getPreferences(MODE_PRIVATE).getString("vib_login_uri", null)
                            val active = if (saved.isNullOrBlank())
                                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                                else Uri.parse(saved)
                            intent.putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, active)
                            pendingRingtoneChoice = result
                            startActivityForResult(intent, requestCodeRingtone)
                        } catch (error: Exception) {
                            pendingRingtoneChoice = null
                            result.error("PICK_FAILED", error.message, null)
                        }
                    }
                }
                "play" -> {
                    try {
                        val saved = getPreferences(MODE_PRIVATE)
                            .getString("vib_login_uri", null)
                        val uri = if (saved.isNullOrBlank())
                            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                            else Uri.parse(saved)
                        val tone = RingtoneManager.getRingtone(this, uri)
                        if (tone == null) result.success(false)
                        else {
                            tone.play()
                            result.success(true)
                        }
                    } catch (error: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestCodeRingtone) return
        val pending = pendingRingtoneChoice
        pendingRingtoneChoice = null
        if (resultCode != Activity.RESULT_OK) {
            pending?.success(false)
            return
        }
        @Suppress("DEPRECATION")
        val selected = data?.getParcelableExtra<Uri>(
            RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (selected != null) {
            getPreferences(MODE_PRIVATE).edit()
                .putString("vib_login_uri", selected.toString()).apply()
            pending?.success(true)
        } else pending?.success(false)
    }
}
''')
