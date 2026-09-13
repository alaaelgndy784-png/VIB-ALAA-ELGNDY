package com.example.ui.components

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PriceChange
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.example.model.Product
import com.example.ui.theme.BlackBackground
import com.example.ui.theme.BlackSurfaceCard
import com.example.ui.theme.BlackSurfaceElevated
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary

/**
 * Quick Dialog to edit product price directly
 */
@Composable
fun QuickPriceDialog(
  product: Product,
  onDismiss: () -> Unit,
  onConfirmPrice: (Double) -> Unit
) {
  var priceStr by remember { mutableStateOf("%.0f".format(product.price)) }
  var error by remember { mutableStateOf<String?>(null) }

  Dialog(
    onDismissRequest = onDismiss,
    properties = DialogProperties(usePlatformDefaultWidth = false)
  ) {
    Surface(
      modifier = Modifier
        .fillMaxWidth(0.9f)
        .clip(RoundedCornerShape(18.dp)),
      shape = RoundedCornerShape(18.dp),
      color = BlackBackground,
      border = BorderStroke(1.2.dp, GoldBorder)
    ) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .padding(20.dp)
      ) {
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
              imageVector = Icons.Default.PriceChange,
              contentDescription = null,
              tint = GoldPrimary,
              modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
              text = "تعديل سعر المنتج",
              color = GoldLight,
              fontSize = 17.sp,
              fontWeight = FontWeight.Bold
            )
          }
          IconButton(onClick = onDismiss) {
            Icon(Icons.Default.Close, contentDescription = "إلغاء", tint = WhiteMuted)
          }
        }

        Spacer(modifier = Modifier.height(10.dp))

        Text(
          text = product.name,
          color = WhitePrimary,
          fontSize = 14.sp,
          fontWeight = FontWeight.Medium
        )

        Spacer(modifier = Modifier.height(14.dp))

        OutlinedTextField(
          value = priceStr,
          onValueChange = { priceStr = it; error = null },
          label = { Text("السعر الجديد (ج.م)", color = WhiteMuted) },
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
          singleLine = true,
          modifier = Modifier
            .fillMaxWidth()
            .testTag("quick_price_input"),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        if (error != null) {
          Spacer(modifier = Modifier.height(6.dp))
          Text(text = error ?: "", color = Color.Red, fontSize = 12.sp)
        }

        Spacer(modifier = Modifier.height(20.dp))

        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
          OutlinedButton(
            onClick = onDismiss,
            modifier = Modifier.weight(1f),
            shape = RoundedCornerShape(10.dp),
            border = BorderStroke(1.dp, GoldBorder)
          ) {
            Text("إلغاء", color = WhitePrimary)
          }

          Button(
            onClick = {
              val newPrice = priceStr.toDoubleOrNull()
              if (newPrice == null || newPrice <= 0) {
                error = "يرجى كتابة سعر صحيح"
              } else {
                onConfirmPrice(newPrice)
              }
            },
            modifier = Modifier.weight(1f).testTag("save_quick_price_button"),
            shape = RoundedCornerShape(10.dp),
            colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
          ) {
            Text("حفظ في Firestore", color = Color.Black, fontWeight = FontWeight.Bold)
          }
        }
      }
    }
  }
}

/**
 * Quick Dialog to change product image directly (PhotoPicker or URL)
 */
@Composable
fun QuickImageDialog(
  product: Product,
  onDismiss: () -> Unit,
  onConfirmImage: (newImageUri: Uri?, customImageUrl: String?) -> Unit
) {
  var selectedUri by remember { mutableStateOf<Uri?>(null) }
  var imageUrlStr by remember { mutableStateOf(product.imageUrl) }
  var showUrlMode by remember { mutableStateOf(false) }

  val photoPicker = rememberLauncherForActivityResult(
    contract = ActivityResultContracts.PickVisualMedia()
  ) { uri: Uri? ->
    if (uri != null) {
      selectedUri = uri
    }
  }

  Dialog(
    onDismissRequest = onDismiss,
    properties = DialogProperties(usePlatformDefaultWidth = false)
  ) {
    Surface(
      modifier = Modifier
        .fillMaxWidth(0.92f)
        .clip(RoundedCornerShape(18.dp)),
      shape = RoundedCornerShape(18.dp),
      color = BlackBackground,
      border = BorderStroke(1.2.dp, GoldBorder)
    ) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .verticalScroll(rememberScrollState())
          .padding(20.dp)
      ) {
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
              imageVector = Icons.Default.AddPhotoAlternate,
              contentDescription = null,
              tint = GoldPrimary,
              modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
              text = "تغيير صورة المنتج",
              color = GoldLight,
              fontSize = 17.sp,
              fontWeight = FontWeight.Bold
            )
          }
          IconButton(onClick = onDismiss) {
            Icon(Icons.Default.Close, contentDescription = "إلغاء", tint = WhiteMuted)
          }
        }

        Spacer(modifier = Modifier.height(10.dp))

        Text(
          text = product.name,
          color = WhitePrimary,
          fontSize = 14.sp,
          fontWeight = FontWeight.Medium
        )

        Spacer(modifier = Modifier.height(14.dp))

        // Current / Preview Image
        Box(
          modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(12.dp))
            .border(1.dp, GoldBorder, RoundedCornerShape(12.dp))
            .background(BlackSurfaceCard),
          contentAlignment = Alignment.Center
        ) {
          if (selectedUri != null) {
            AsyncImage(
              model = ImageRequest.Builder(LocalContext.current).data(selectedUri).crossfade(true).build(),
              contentDescription = "صورة جديدة",
              modifier = Modifier.fillMaxWidth().height(180.dp),
              contentScale = ContentScale.Crop
            )
          } else if (imageUrlStr.isNotBlank()) {
            AsyncImage(
              model = ImageRequest.Builder(LocalContext.current).data(imageUrlStr).crossfade(true).build(),
              contentDescription = product.name,
              modifier = Modifier.fillMaxWidth().height(180.dp),
              contentScale = ContentScale.Crop
            )
          } else {
            ProductImageDisplay(product = product, modifier = Modifier.fillMaxWidth().height(180.dp))
          }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Buttons for picker and URL
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
          Button(
            onClick = {
              photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            },
            modifier = Modifier.weight(1f).testTag("quick_pick_image_button"),
            shape = RoundedCornerShape(10.dp),
            colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
          ) {
            Icon(Icons.Default.AddPhotoAlternate, contentDescription = null, tint = Color.Black, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text("اختيار من المعرض", color = Color.Black, fontSize = 12.sp, fontWeight = FontWeight.Bold)
          }

          OutlinedButton(
            onClick = { showUrlMode = !showUrlMode },
            modifier = Modifier.weight(1f),
            shape = RoundedCornerShape(10.dp),
            border = BorderStroke(1.dp, GoldBorder)
          ) {
            Icon(Icons.Default.Link, contentDescription = null, tint = GoldLight, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text(if (showUrlMode) "إخفاء الرابط" else "إدخال رابط", color = WhitePrimary, fontSize = 12.sp)
          }
        }

        if (showUrlMode) {
          Spacer(modifier = Modifier.height(10.dp))
          OutlinedTextField(
            value = imageUrlStr,
            onValueChange = { imageUrlStr = it },
            label = { Text("رابط الصورة المباشر (URL)", color = WhiteMuted) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
              focusedBorderColor = GoldPrimary,
              unfocusedBorderColor = GoldBorder,
              focusedTextColor = WhitePrimary,
              unfocusedTextColor = WhitePrimary
            )
          )
        }

        Spacer(modifier = Modifier.height(12.dp))

        Text(
          text = "ملاحظة: سيتم رفع الصورة الجديدة إلى Firebase Storage وحذف الصورة القديمة بأمان لتوفير المساحة.",
          color = WhiteMuted,
          fontSize = 11.sp,
          lineHeight = 16.sp
        )

        Spacer(modifier = Modifier.height(18.dp))

        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
          OutlinedButton(
            onClick = onDismiss,
            modifier = Modifier.weight(1f),
            shape = RoundedCornerShape(10.dp),
            border = BorderStroke(1.dp, GoldBorder)
          ) {
            Text("إلغاء", color = WhitePrimary)
          }

          Button(
            onClick = {
              onConfirmImage(
                selectedUri,
                if (imageUrlStr.isNotBlank() && imageUrlStr != product.imageUrl) imageUrlStr.trim() else null
              )
            },
            modifier = Modifier.weight(1f).testTag("save_quick_image_button"),
            shape = RoundedCornerShape(10.dp),
            colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
          ) {
            Text("رفع وتحديث", color = Color.Black, fontWeight = FontWeight.Bold)
          }
        }
      }
    }
  }
}

/**
 * Quick Dialog to edit product stock availability and quantity
 */
@Composable
fun QuickStockDialog(
  product: Product,
  onDismiss: () -> Unit,
  onConfirmStock: (inStock: Boolean, quantity: Int) -> Unit
) {
  var inStock by remember { mutableStateOf(product.inStock) }
  var quantityStr by remember { mutableStateOf(product.stockQuantity.toString()) }

  Dialog(
    onDismissRequest = onDismiss,
    properties = DialogProperties(usePlatformDefaultWidth = false)
  ) {
    Surface(
      modifier = Modifier
        .fillMaxWidth(0.9f)
        .clip(RoundedCornerShape(18.dp)),
      shape = RoundedCornerShape(18.dp),
      color = BlackBackground,
      border = BorderStroke(1.2.dp, GoldBorder)
    ) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .padding(20.dp)
      ) {
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
              imageVector = Icons.Default.Inventory2,
              contentDescription = null,
              tint = GoldPrimary,
              modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
              text = "تعديل حالة المخزون",
              color = GoldLight,
              fontSize = 17.sp,
              fontWeight = FontWeight.Bold
            )
          }
          IconButton(onClick = onDismiss) {
            Icon(Icons.Default.Close, contentDescription = "إلغاء", tint = WhiteMuted)
          }
        }

        Spacer(modifier = Modifier.height(10.dp))

        Text(
          text = product.name,
          color = WhitePrimary,
          fontSize = 14.sp,
          fontWeight = FontWeight.Medium
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Stock Toggle Row
        Surface(
          shape = RoundedCornerShape(12.dp),
          color = BlackSurfaceElevated,
          border = BorderStroke(0.8.dp, GoldBorder),
          modifier = Modifier.fillMaxWidth()
        ) {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .padding(horizontal = 14.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
          ) {
            Column {
              Text(
                text = "حالة توفر المنتج:",
                color = WhitePrimary,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold
              )
              Text(
                text = if (inStock) "المنتج متوفر بالمخزن ويمكن طلبه" else "المنتج غير متوفر حالياً بالمخزن",
                color = if (inStock) GoldLight else WhiteMuted,
                fontSize = 11.sp
              )
            }

            Switch(
              checked = inStock,
              onCheckedChange = { inStock = it },
              colors = SwitchDefaults.colors(
                checkedThumbColor = Color.Black,
                checkedTrackColor = GoldPrimary,
                uncheckedThumbColor = WhiteMuted,
                uncheckedTrackColor = BlackSurfaceCard
              )
            )
          }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Quantity Input
        OutlinedTextField(
          value = quantityStr,
          onValueChange = { quantityStr = it },
          label = { Text("الكمية المتوفرة بالمخزن", color = WhiteMuted) },
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
          singleLine = true,
          modifier = Modifier.fillMaxWidth(),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        Spacer(modifier = Modifier.height(20.dp))

        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
          OutlinedButton(
            onClick = onDismiss,
            modifier = Modifier.weight(1f),
            shape = RoundedCornerShape(10.dp),
            border = BorderStroke(1.dp, GoldBorder)
          ) {
            Text("إلغاء", color = WhitePrimary)
          }

          Button(
            onClick = {
              val qty = quantityStr.toIntOrNull() ?: 10
              onConfirmStock(inStock, qty)
            },
            modifier = Modifier.weight(1f).testTag("save_quick_stock_button"),
            shape = RoundedCornerShape(10.dp),
            colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
          ) {
            Text("حفظ التعديل", color = Color.Black, fontWeight = FontWeight.Bold)
          }
        }
      }
    }
  }
}

/**
 * Delete Confirmation Dialog with clear warning message
 */
@Composable
fun DeleteConfirmDialog(
  product: Product,
  onDismiss: () -> Unit,
  onConfirmDelete: () -> Unit
) {
  Dialog(
    onDismissRequest = onDismiss,
    properties = DialogProperties(usePlatformDefaultWidth = false)
  ) {
    Surface(
      modifier = Modifier
        .fillMaxWidth(0.9f)
        .clip(RoundedCornerShape(18.dp)),
      shape = RoundedCornerShape(18.dp),
      color = BlackBackground,
      border = BorderStroke(1.5.dp, Color(0xFFE53935))
    ) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally
      ) {
        Box(
          modifier = Modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(Color(0xFFE53935).copy(alpha = 0.15f))
            .border(1.dp, Color(0xFFE53935), CircleShape),
          contentAlignment = Alignment.Center
        ) {
          Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            tint = Color(0xFFE53935),
            modifier = Modifier.size(32.dp)
          )
        }

        Spacer(modifier = Modifier.height(14.dp))

        Text(
          text = "تأكيد حذف المنتج",
          color = Color(0xFFE53935),
          fontSize = 18.sp,
          fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
          text = "هل أنت متأكد من رغبتك في حذف هذا المنتج نهائياً؟",
          color = WhitePrimary,
          fontSize = 14.sp,
          textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(6.dp))

        Text(
          text = "\"${product.name}\"",
          color = GoldPrimary,
          fontSize = 15.sp,
          fontWeight = FontWeight.Bold,
          textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(10.dp))

        Surface(
          shape = RoundedCornerShape(8.dp),
          color = BlackSurfaceElevated,
          border = BorderStroke(0.8.dp, GoldBorder),
          modifier = Modifier.fillMaxWidth()
        ) {
          Text(
            text = "تنبيه: سيتم حذف هذا المنتج من Firebase Firestore وحذف صورته بأمان من Firebase Storage، ولن يظهر لأي عميل.",
            color = WhiteMuted,
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(10.dp),
            lineHeight = 16.sp
          )
        }

        Spacer(modifier = Modifier.height(20.dp))

        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
          OutlinedButton(
            onClick = onDismiss,
            modifier = Modifier.weight(1f),
            shape = RoundedCornerShape(10.dp),
            border = BorderStroke(1.dp, GoldBorder)
          ) {
            Text("إلغاء", color = WhitePrimary)
          }

          Button(
            onClick = onConfirmDelete,
            modifier = Modifier.weight(1f).testTag("confirm_delete_product_button"),
            shape = RoundedCornerShape(10.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE53935))
          ) {
            Icon(Icons.Default.Delete, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(4.dp))
            Text("حذف نهائي", color = Color.White, fontWeight = FontWeight.Bold)
          }
        }
      }
    }
  }
}
