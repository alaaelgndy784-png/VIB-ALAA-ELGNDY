package com.example.notifications

import android.Manifest
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.example.BuildConfig
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class NewProductAndroidNotificationTest {
  @Test fun ringsOnceAndTapTargetsTheAnnouncedProduct() {
    assumeFalse(BuildConfig.ADMIN_FEATURES_ENABLED)
    val context = ApplicationProvider.getApplicationContext<Application>()
    shadowOf(context).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
    context.getSharedPreferences("catalog_notifications", Context.MODE_PRIVATE).edit().clear().putLong("registered_at", 100).commit()
    val announcement = NewProductAnnouncement("new-product", "خلاط جديد", 200)
    CatalogNotifications.show(context, announcement)
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val notifications = shadowOf(manager).allNotifications
    assertEquals(1, notifications.size)
    assertEquals("خلاط جديد", notifications[0].extras.getCharSequence("android.text"))
    assertEquals("new-product", shadowOf(notifications[0].contentIntent).savedIntent.getStringExtra("product_id"))
    assertEquals(NotificationManager.IMPORTANCE_HIGH, manager.getNotificationChannel("vib_new_products").importance)
    CatalogNotifications.show(context, announcement)
    assertEquals(1, shadowOf(manager).allNotifications.size)
  }
  @Test fun deniedPermissionDoesNotCrashOrConsumeTheAnnouncement() {
    assumeFalse(BuildConfig.ADMIN_FEATURES_ENABLED)
    val context = ApplicationProvider.getApplicationContext<Application>()
    shadowOf(context).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
    val preferences = context.getSharedPreferences("catalog_notifications", Context.MODE_PRIVATE)
    preferences.edit().clear().putLong("registered_at", 100).commit()
    CatalogNotifications.show(context, NewProductAnnouncement("new", "منتج", 200))
    assertEquals(0, preferences.getLong("last_at", 0))
  }
}
