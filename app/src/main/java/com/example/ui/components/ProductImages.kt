package com.example.ui.components

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.model.Product
import com.example.ui.theme.*

const val MAX_PRODUCT_IMAGES = 8

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ProductImageGallery(product: Product, modifier: Modifier = Modifier) {
  val images = product.galleryImages()
  val pager = rememberPagerState(pageCount = { images.size.coerceAtLeast(1) })
  Box(modifier.testTag("gallery_${product.id}")) {
    HorizontalPager(state = pager, modifier = Modifier.fillMaxSize(), key = { "$it:${images.getOrNull(it)?.hashCode()}" }) { page ->
      ProductImageDisplay(product.copy(imageUrl = images.getOrNull(page).orEmpty()), Modifier.fillMaxSize(), ContentScale.Fit)
    }
    if (images.size > 1) {
      Surface(color = Color.Black.copy(alpha = 0.75f), shape = androidx.compose.foundation.shape.RoundedCornerShape(12.dp), modifier = Modifier.align(Alignment.BottomCenter).padding(6.dp)) {
        Text("${pager.currentPage + 1} / ${images.size} • اسحب للصور", color = WhitePrimary, fontSize = 10.sp, modifier = Modifier.padding(horizontal = 10.dp, vertical = 3.dp).testTag("gallery_count_${product.id}"))
      }
    }
  }
}

@Composable
fun ProductImagesEditor(images: List<String>, onImagesChange: (List<String>) -> Unit, enabled: Boolean = true) {
  var url by remember { mutableStateOf("") }
  var showLink by remember { mutableStateOf(false) }
  var error by remember { mutableStateOf<String?>(null) }
  val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(MAX_PRODUCT_IMAGES)) { uris ->
    val added = (images + uris.map { it.toString() }).distinct()
    if (added.size > MAX_PRODUCT_IMAGES) error = "الحد الأقصى ٨ صور. احذف صورة لإضافة غيرها."
    else { onImagesChange(added); error = null }
  }
  Column {
    Text("صور المنتج (${images.size}/$MAX_PRODUCT_IMAGES)", color = GoldLight, fontSize = 13.sp)
    Text("أول صورة هي الرئيسية. اضغط «رئيسية» لتغييرها، واسحب لمشاهدة الباقي.", color = WhiteMuted, fontSize = 11.sp)
    Spacer(Modifier.height(8.dp))
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth().testTag("product_images_editor")) {
      itemsIndexed(images, key = { index, value -> "$index:${value.hashCode()}" }) { index, value ->
        Column(Modifier.width(112.dp)) {
          Box(Modifier.size(112.dp)) {
            ProductImageDisplay(Product(imageUrl = value, name = "صورة ${index + 1}"), Modifier.fillMaxSize(), ContentScale.Fit)
            IconButton(onClick = { onImagesChange(images.filterIndexed { i, _ -> i != index }) }, enabled = enabled, modifier = Modifier.align(Alignment.TopEnd).size(32.dp).testTag("remove_image_$index")) {
              Icon(Icons.Default.Close, contentDescription = "حذف الصورة ${index + 1}", tint = Color.Red)
            }
          }
          TextButton(onClick = { onImagesChange(listOf(value) + images.filter { it != value }) }, enabled = enabled && index != 0, modifier = Modifier.testTag("cover_image_$index")) {
            Text(if (index == 0) "الصورة الرئيسية" else "رئيسية", fontSize = 10.sp, color = GoldLight)
          }
        }
      }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      Button(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = enabled && images.size < MAX_PRODUCT_IMAGES, colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary), modifier = Modifier.testTag("admin_pick_image_button")) {
        Text("إضافة صور", color = Color.Black, fontSize = 12.sp)
      }
      TextButton(onClick = { showLink = !showLink }, enabled = enabled) { Text("إضافة رابط", color = GoldLight, fontSize = 12.sp) }
    }
    if (showLink) {
      OutlinedTextField(value = url, onValueChange = { url = it }, enabled = enabled, label = { Text("رابط الصورة https://", color = WhiteMuted) }, singleLine = true, modifier = Modifier.fillMaxWidth(), colors = OutlinedTextFieldDefaults.colors(focusedTextColor = WhitePrimary, unfocusedTextColor = WhitePrimary))
      TextButton(onClick = {
        val value = url.trim()
        if (!value.startsWith("https://") || value.length < 10) error = "اكتب رابط صورة صحيح يبدأ بـ https://"
        else if (images.size >= MAX_PRODUCT_IMAGES) error = "الحد الأقصى ٨ صور"
        else { onImagesChange((images + value).distinct()); url = ""; showLink = false; error = null }
      }, enabled = enabled) { Text("إضافة الرابط للصور", color = GoldLight) }
    }
    error?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
  }
}
