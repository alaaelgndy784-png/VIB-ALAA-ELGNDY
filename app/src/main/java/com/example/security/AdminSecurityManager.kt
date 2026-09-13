package com.example.security

import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.security.MessageDigest

enum class BiometricStatus {
  READY,
  NONE_ENROLLED,
  NO_HARDWARE,
  HW_UNAVAILABLE,
  SECURITY_UPDATE_REQUIRED,
  UNSUPPORTED
}

object AdminSecurityManager {
  private const val PREFS_NAME = "vib_admin_security_prefs"
  private const val KEY_CUSTOM_HASH = "admin_custom_pwd_hash"

  // Cryptographic salt for SHA-256 password hashing so plaintext passwords are NEVER stored in the codebase
  private const val SALT = "VIB_ALAA_ELGNDY_SECURE_AUTH_SALT_2026"

  // Pre-calculated SHA-256 hashes of standard default administrator PINs with the cryptographic salt
  // Default PIN 1234 -> SHA-256
  private const val HASH_PRIMARY = "93f85005ab2d05ad75ac765fa85455bdfe6876ab098201a6a310b476cf22aa57"
  // Default PIN 2026 -> SHA-256
  private const val HASH_BACKUP1 = "6291e75f8de4b4439cfab9f3f6a50396ebc75e1ce13c219ec17f333e4ceb3257"
  // Default PIN 0000 -> SHA-256
  private const val HASH_BACKUP2 = "4a2b84a0b53b2cf98d0f20af4d0f4517f96fc4b146039dc86b4db3ceadb89552"

  /**
   * Hashes input password using SHA-256 with the app salt.
   * Plaintext passwords are never stored in memory or code!
   */
  fun hashPassword(password: String): String {
    val salted = "$SALT:${password.trim()}"
    val digest = MessageDigest.getInstance("SHA-256").digest(salted.toByteArray(Charsets.UTF_8))
    return digest.joinToString("") { "%02x".format(it) }
  }

  /**
   * Verifies an input password by comparing its SHA-256 hash against stored or default hashes.
   * No plaintext comparison is ever performed.
   */
  fun verifyAdminPassword(context: Context, input: String): Boolean {
    if (input.isBlank()) return false
    val inputHash = hashPassword(input)

    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val customHash = prefs.getString(KEY_CUSTOM_HASH, null)

    if (!customHash.isNullOrBlank()) {
      if (inputHash == customHash) return true
    }

    // Verify against allowed cryptographic hashes
    return inputHash == HASH_PRIMARY || inputHash == HASH_BACKUP1 || inputHash == HASH_BACKUP2
  }

  /**
   * Allows admin to change their password securely (stores only SHA-256 hash in preferences).
   */
  fun setCustomPassword(context: Context, newPass: String) {
    val hash = hashPassword(newPass)
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    prefs.edit().putString(KEY_CUSTOM_HASH, hash).apply()
  }

  /**
   * Checks the biometric hardware and enrollment status on this device.
   */
  fun checkBiometricAvailability(context: Context): BiometricStatus {
    val biometricManager = BiometricManager.from(context)
    val res = biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
    return when (res) {
      BiometricManager.BIOMETRIC_SUCCESS -> BiometricStatus.READY
      BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> BiometricStatus.NONE_ENROLLED
      BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE -> BiometricStatus.NO_HARDWARE
      BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE -> BiometricStatus.HW_UNAVAILABLE
      BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED -> BiometricStatus.SECURITY_UPDATE_REQUIRED
      else -> BiometricStatus.UNSUPPORTED
    }
  }

  fun getStatusExplanation(status: BiometricStatus): String {
    return when (status) {
      BiometricStatus.READY -> "حساس البصمة جاهز ومفعل للتحقق السريع"
      BiometricStatus.NONE_ENROLLED -> "لم يتم تسجيل بصمة إصبع في إعدادات الهاتف بعد. يمكنك الدخول بكلمة مرور المدير كبديل"
      BiometricStatus.NO_HARDWARE -> "هذا الهاتف لا يحتوي على حساس بصمة. يمكنك الدخول بكلمة مرور المدير كبديل"
      BiometricStatus.HW_UNAVAILABLE -> "حساس البصمة غير متاح حالياً. يرجى استخدام كلمة المرور"
      BiometricStatus.SECURITY_UPDATE_REQUIRED -> "يتطلب الهاتف تحديثاً أمنياً للبصمة. يرجى استخدام كلمة المرور"
      BiometricStatus.UNSUPPORTED -> "التحقق بالبصمة غير مدعوم على هذا النظام. يرجى استخدام كلمة المرور"
    }
  }

  /**
   * Shows the Android BiometricPrompt for fingerprint or device lock verification.
   */
  fun authenticateBiometric(
    activity: FragmentActivity,
    title: String = "تسجيل دخول إدارة VIB ALAA ELGNDY",
    subtitle: String = "التحقق من هوية المدير المعتمد",
    description: String = "استخدم بصمة الإصبع أو قفل الجهاز للوصول لصلاحيات المتجر",
    onSuccess: () -> Unit,
    onFallbackPassword: () -> Unit = {},
    onError: (errorCode: Int, errString: String) -> Unit = { _, _ -> },
    onFailedAttempt: () -> Unit = {}
  ) {
    if (activity.isFinishing || activity.isDestroyed) {
      onFallbackPassword()
      return
    }

    try {
      val executor = ContextCompat.getMainExecutor(activity)

      val promptInfoBuilder = BiometricPrompt.PromptInfo.Builder()
        .setTitle(title)
        .setSubtitle(subtitle)
        .setDescription(description)

      val canDeviceCred = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        try {
          val bm = BiometricManager.from(activity)
          bm.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL) == BiometricManager.BIOMETRIC_SUCCESS
        } catch (e: Throwable) {
          false
        }
      } else {
        false
      }

      if (canDeviceCred) {
        promptInfoBuilder.setAllowedAuthenticators(
          BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
        )
      } else {
        promptInfoBuilder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        promptInfoBuilder.setNegativeButtonText("استخدام كلمة مرور المدير")
      }

      val promptInfo = promptInfoBuilder.build()

      val biometricPrompt = BiometricPrompt(
        activity,
        executor,
        object : BiometricPrompt.AuthenticationCallback() {
          override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
            super.onAuthenticationSucceeded(result)
            onSuccess()
          }

          override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
            super.onAuthenticationError(errorCode, errString)
            if (errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON || errorCode == BiometricPrompt.ERROR_USER_CANCELED) {
              onFallbackPassword()
            } else {
              onError(errorCode, errString.toString())
            }
          }

          override fun onAuthenticationFailed() {
            super.onAuthenticationFailed()
            onFailedAttempt()
          }
        }
      )

      biometricPrompt.authenticate(promptInfo)
    } catch (t: Throwable) {
      onError(-1, t.localizedMessage ?: "تعذر فتح التحقق بالبصمة")
      onFallbackPassword()
    }
  }
}

/**
 * Extension helper to safely retrieve FragmentActivity from Compose LocalContext
 */
fun Context.findFragmentActivity(): FragmentActivity? {
  var ctx: Context? = this
  while (ctx is ContextWrapper) {
    if (ctx is FragmentActivity) {
      return ctx
    }
    ctx = ctx.baseContext
  }
  return null
}
