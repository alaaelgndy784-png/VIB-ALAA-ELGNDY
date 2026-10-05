package com.example.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.example.ui.theme.*
import com.example.update.CatalogUpdate
import com.example.update.CatalogUpdateService
import kotlinx.coroutines.launch
import java.io.File

@Composable
fun CatalogUpdateDialog(update: CatalogUpdate, onDismiss: () -> Unit) {
  val context = LocalContext.current
  val service = remember { CatalogUpdateService(context.applicationContext) }
  val scope = rememberCoroutineScope()
  var busy by remember { mutableStateOf(false) }
  var progress by remember { mutableIntStateOf(0) }
  var downloaded by remember(update) { mutableStateOf<File?>(null) }
  var error by remember { mutableStateOf<String?>(null) }
  var needsPermission by remember { mutableStateOf(false) }
  AlertDialog(
    onDismissRequest = { if (!busy) onDismiss() },
    containerColor = BlackSurfaceCard,
    title = { Text("تحديث جديد لتطبيق VIB", color = GoldPrimary) },
    text = { Column {
      Text("الإصدار ${update.versionName} جاهز. حدّث التطبيق لمشاهدة التحسينات الجديدة.", color = WhitePrimary)
      if (busy) {
        Spacer(Modifier.height(12.dp))
        LinearProgressIndicator(progress = { progress / 100f }, modifier = Modifier.fillMaxWidth(), color = GoldPrimary)
        Text("جاري التنزيل $progress٪", color = WhiteMuted)
      }
      if (needsPermission) Text("فعّل «السماح من هذا المصدر»، ثم ارجع واضغط «تثبيت التحديث».", color = GoldLight)
      error?.let { Text(it, color = Color(0xFFFF7777)) }
    } },
    confirmButton = {
      Button(enabled = !busy, modifier = Modifier.testTag("install_catalog_update"), colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary), onClick = {
        scope.launch {
          busy = true; error = null
          try {
            val file = downloaded ?: service.download(update) { value -> progress = value }.also { downloaded = it }
            needsPermission = !service.install(file)
          } catch (e: Exception) { error = e.message ?: "تعذر تنزيل التحديث. حاول مرة أخرى." }
          finally { busy = false }
        }
      }) { Text(if (downloaded == null) "تحديث الآن" else "تثبيت التحديث", color = Color.Black) }
    },
    dismissButton = { TextButton(onClick = onDismiss, enabled = !busy) { Text("لاحقًا", color = WhiteMuted) } }
  )
}
