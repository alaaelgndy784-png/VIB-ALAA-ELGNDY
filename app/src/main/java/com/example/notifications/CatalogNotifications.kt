package com.example.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.*
import com.example.BuildConfig
import com.example.MainActivity
import com.example.R
import com.example.data.FirebaseRepository
import java.util.concurrent.TimeUnit

data class NewProductAnnouncement(val id: String, val name: String, val createdAt: Long) {
  companion object {
    fun fromMap(map: Map<String, Any?>): NewProductAnnouncement? {
      val id = map["id"] as? String ?: return null
      val name = map["name"] as? String ?: return null
      val date = (map["createdAt"] as? Number)?.toLong() ?: return null
      if (id.isBlank() || name.isBlank() || date <= 0) return null
      return NewProductAnnouncement(id, name.take(120), date)
    }
  }
}

object CatalogNotifications {
  private const val CHANNEL = "vib_new_products"
  private fun prefs(context: Context) = context.getSharedPreferences("catalog_notifications", Context.MODE_PRIVATE)
  fun prepare(context: Context) {
    if (BuildConfig.ADMIN_FEATURES_ENABLED) return
    val preferences = prefs(context)
    if (!preferences.contains("registered_at")) preferences.edit().putLong("registered_at", System.currentTimeMillis()).apply()
    if (Build.VERSION.SDK_INT >= 26) {
      val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      manager.createNotificationChannel(NotificationChannel(CHANNEL, "منتجات VIB الجديدة", NotificationManager.IMPORTANCE_HIGH).apply {
        description = "تنبيه عند إضافة منتجات جديدة للكتالوج"
        enableVibration(true)
      })
    }
  }
  fun schedule(context: Context) {
    prepare(context)
    if (BuildConfig.ADMIN_FEATURES_ENABLED) return
    val request = PeriodicWorkRequestBuilder<NewProductsWorker>(15, TimeUnit.MINUTES)
      .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build()
    WorkManager.getInstance(context).enqueueUniquePeriodicWork("vib_new_products", ExistingPeriodicWorkPolicy.KEEP, request)
  }
  internal fun shouldNotify(announcement: NewProductAnnouncement, registeredAt: Long, lastAt: Long): Boolean = announcement.createdAt > maxOf(registeredAt, lastAt)
  @Synchronized
  fun show(context: Context, announcement: NewProductAnnouncement) {
    if (BuildConfig.ADMIN_FEATURES_ENABLED) return
    prepare(context)
    val preferences = prefs(context)
    if (!shouldNotify(announcement, preferences.getLong("registered_at", Long.MAX_VALUE), preferences.getLong("last_at", 0))) return
    if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
    val manager = NotificationManagerCompat.from(context)
    if (!manager.areNotificationsEnabled()) return
    val intent = Intent(context, MainActivity::class.java).putExtra("product_id", announcement.id)
      .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    val pending = PendingIntent.getActivity(context, announcement.id.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    val notification = NotificationCompat.Builder(context, CHANNEL)
      .setSmallIcon(R.drawable.ic_new_product)
      .setContentTitle("منتج جديد عند VIB")
      .setContentText(announcement.name)
      .setStyle(NotificationCompat.BigTextStyle().bigText(announcement.name))
      .setContentIntent(pending).setAutoCancel(true)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setDefaults(NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_VIBRATE)
      .build()
    manager.notify(announcement.id.hashCode(), notification)
    preferences.edit().putLong("last_at", announcement.createdAt).apply()
  }
}

class NewProductsWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
  override suspend fun doWork(): Result {
    if (BuildConfig.ADMIN_FEATURES_ENABLED) return Result.success()
    return try {
      val announcement = FirebaseRepository(applicationContext, startListeners = false).fetchNewProductAnnouncement()
      if (announcement != null) CatalogNotifications.show(applicationContext, announcement)
      Result.success()
    } catch (_: Exception) { Result.retry() }
  }
}
