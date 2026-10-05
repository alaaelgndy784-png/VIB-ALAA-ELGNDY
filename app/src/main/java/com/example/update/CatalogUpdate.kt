package com.example.update

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.example.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

const val UPDATE_MANIFEST_URL = "https://github.com/alaaelgndy784-png/VIB-ALAA-ELGNDY/releases/download/customer-latest/VIB-CATALOG-UPDATE.json"
private const val RELEASE_PREFIX = "https://github.com/alaaelgndy784-png/VIB-ALAA-ELGNDY/releases/download/catalog-"

data class CatalogUpdate(val versionCode: Int, val versionName: String, val apkUrl: String, val sha256: String, val packageName: String) {
  fun toMap(): Map<String, Any> = mapOf("versionCode" to versionCode, "versionName" to versionName, "apkUrl" to apkUrl, "sha256" to sha256, "packageName" to packageName)
  fun isNewerThan(installedVersion: Int): Boolean = versionCode > installedVersion
  companion object {
    fun fromMap(map: Map<String, Any?>): CatalogUpdate? {
      val code = (map["versionCode"] as? Number)?.toInt() ?: return null
      val name = map["versionName"] as? String ?: return null
      val url = map["apkUrl"] as? String ?: return null
      val hash = map["sha256"] as? String ?: return null
      val pkg = map["packageName"] as? String ?: return null
      if (code <= 0 || name.isBlank() || name.length > 40 || pkg != BuildConfig.APPLICATION_ID) return null
      // Only the immutable customer APK in this project's official releases.
      if (!url.startsWith(RELEASE_PREFIX) || !url.endsWith("/VIB-CUSTOMER.apk") || url.contains("..") || url.contains('?') || url.contains('#')) return null
      if (!hash.matches(Regex("[a-f0-9]{64}"))) return null
      return CatalogUpdate(code, name, url, hash, pkg)
    }
  }
}

class CatalogUpdateService(private val context: Context) {
  private val client = OkHttpClient.Builder().connectTimeout(20, TimeUnit.SECONDS).readTimeout(45, TimeUnit.SECONDS).build()
  suspend fun latest(): CatalogUpdate = withContext(Dispatchers.IO) {
    client.newCall(Request.Builder().url(UPDATE_MANIFEST_URL).header("Cache-Control", "no-cache").build()).execute().use { response ->
      check(response.isSuccessful) { "تعذر الحصول على التحديث. حاول مرة أخرى." }
      val body = response.body ?: error("ملف التحديث غير متاح")
      val bytes = body.byteStream().use { input ->
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(4096)
        while (output.size() <= 16_384) {
          val count = input.read(buffer)
          if (count < 0) break
          output.write(buffer, 0, count)
        }
        output.toByteArray()
      }
      check(bytes.size <= 16_384) { "ملف التحديث غير صالح" }
      val json = JSONObject(String(bytes, Charsets.UTF_8))
      CatalogUpdate.fromMap(json.keys().asSequence().associateWith { json.get(it) }) ?: error("بيانات التحديث غير صالحة")
    }
  }
  suspend fun download(update: CatalogUpdate, progress: (Int) -> Unit): File = withContext(Dispatchers.IO) {
    check(update.isNewerThan(BuildConfig.VERSION_CODE)) { "التطبيق محدث بالفعل" }
    val directory = File(context.cacheDir, "updates").apply { mkdirs() }
    val partial = File(directory, "customer-update.part")
    val destination = File(directory, "customer-update.apk")
    try {
      client.newCall(Request.Builder().url(update.apkUrl).build()).execute().use { response ->
        check(response.isSuccessful) { "تعذر تنزيل التحديث. تأكد من الإنترنت." }
        val body = response.body ?: error("التحديث غير متاح")
        val length = body.contentLength()
        check(length <= 100L * 1024 * 1024) { "حجم ملف التحديث غير صالح" }
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        body.byteStream().use { input -> partial.outputStream().use { output ->
          val buffer = ByteArray(32 * 1024)
          while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            check(total <= 100L * 1024 * 1024) { "حجم ملف التحديث غير صالح" }
            digest.update(buffer, 0, count); output.write(buffer, 0, count)
            progress(if (length > 0) (total * 100 / length).toInt().coerceAtMost(99) else 0)
          }
        } }
        check(digest.digest().joinToString("") { "%02x".format(it) } == update.sha256) { "ملف التحديث غير مكتمل. أعد التنزيل." }
      }
      validateArchive(partial, update)
      destination.delete()
      check(partial.renameTo(destination)) { "تعذر حفظ التحديث" }
      progress(100)
      destination
    } catch (error: Exception) { partial.delete(); throw error }
  }
  @Suppress("DEPRECATION")
  internal fun validateArchive(file: File, update: CatalogUpdate) {
    val manager = context.packageManager
    val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    val archive = manager.getPackageArchiveInfo(file.absolutePath, flags) ?: error("ملف التحديث غير صالح")
    val code = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
    check(archive.packageName == context.packageName && code == update.versionCode.toLong()) { "الملف ليس تحديث تطبيق VIB" }
    val installed = manager.getPackageInfo(context.packageName, flags)
    fun signatures(info: android.content.pm.PackageInfo): Set<String> {
      val values = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
      return values?.map { signature -> MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) } }?.toSet() ?: emptySet()
    }
    val old = signatures(installed)
    check(old.isNotEmpty() && old == signatures(archive)) { "توقيع التحديث مختلف. تواصل مع المدير، ولا تحذف التطبيق الحالي." }
  }
  fun install(file: File): Boolean {
    if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls()) {
      context.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
      return false
    }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.updates", file)
    context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    return true
  }
}
