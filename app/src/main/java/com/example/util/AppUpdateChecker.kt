package com.example.util

import com.example.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

data class AppUpdateInfo(
  val versionCode: Int,
  val downloadUrl: String
)

object AppUpdateChecker {
  private const val RELEASES_API =
    "https://api.github.com/repos/alaaelgndy784-png/VIB-ALAA-ELGNDY/releases/tags/"

  suspend fun check(isAdmin: Boolean): AppUpdateInfo? = withContext(Dispatchers.IO) {
    var connection: HttpURLConnection? = null
    try {
      val releaseTag = if (isAdmin) "admin-latest" else "customer-latest"
      connection = (URL(RELEASES_API + releaseTag).openConnection() as HttpURLConnection).apply {
        connectTimeout = 5000
        readTimeout = 5000
        setRequestProperty("Accept", "application/vnd.github+json")
        setRequestProperty("User-Agent", "VIB-Android")
      }
      if (connection.responseCode !in 200..299) return@withContext null
      val release = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
      val notes = release.optString("body")
      val latestCode = Regex("versionCode=(\\d+)")
        .find(notes)?.groupValues?.getOrNull(1)?.toIntOrNull() ?: return@withContext null
      if (latestCode <= BuildConfig.VERSION_CODE) return@withContext null

      val wantedAsset = if (isAdmin) "VIB-ADMIN.apk" else "VIB-CUSTOMER.apk"
      val assets = release.optJSONArray("assets") ?: return@withContext null
      val downloadUrl = (0 until assets.length())
        .map { assets.getJSONObject(it) }
        .firstOrNull { it.optString("name") == wantedAsset }
        ?.optString("browser_download_url")
        ?.takeIf { it.startsWith("https://") }
        ?: return@withContext null
      AppUpdateInfo(latestCode, downloadUrl)
    } catch (_: Exception) {
      null
    } finally {
      connection?.disconnect()
    }
  }
}
