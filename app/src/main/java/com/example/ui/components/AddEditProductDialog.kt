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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.example.model.Product
import com.example.model.SanitaryCategory
import com.example.ui.theme.BlackBackground
import com.example.ui.theme.BlackSurfaceCard
import com.example.ui.theme.BlackSurfaceElevated
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary

@Composable
fun AddEditProductDialog(
  productToEdit: Product?,
  isLoading: Boolean,
  onDismiss: () -> Unit,
  onSaveProduct: (
    name: String,
    price: Double,
    category: String,
    description: String,
    imageUri: Uri?,
    customImageUrl: String?,
    inStock: Boolean,
    stockQuantity: Int
  ) -> Unit,
  modifier: Modifier = Modifier
) {
  var name by remember { mutableStateOf(productToEdit?.name ?: "") }
  var priceStr by remember {
    mutableStateOf(if (productToEdit != null) "%.0f".format(productToEdit.price) else "")
  }
  var category by remember { mutableStateOf(productToEdit?.category ?: SanitaryCategory.BRASS) }
  var description by remember { mutableStateOf(productToEdit?.description ?: "") }
  var inStock by remember { mutableStateOf(productToEdit?.inStock ?: true) }
  var stockQuantityStr by remember { mutableStateOf(productToEdit?.stockQuantity?.toString() ?: "10") }
  var selectedImageUri by remember { mutableStateOf<Uri?>(null) }
  var customImageUrl by remember { mutableStateOf(productToEdit?.imageUrl ?: "") }
  var showUrlField by remember { mutableStateOf(false) }
  var errorMessage by remember { mutableStateOf<String?>(null) }

  // Modern Android Photo Picker (zero-permission)
  val photoPickerLauncher = rememberLauncherForActivityResult(
    contract = ActivityResultContracts.PickVisualMedia()
  ) { uri: Uri? ->
    if (uri != null) {
      selectedImageUri = uri
    }
  }

  Dialog(
    onDismissRequest = onDismiss,
    properties = DialogProperties(usePlatformDefaultWidth = false)
  ) {
    Surface(
      modifier = modifier
        .fillMaxWidth(0.95f)
        .clip(RoundedCornerShape(20.dp)),
      shape = RoundedCornerShape(20.dp),
      color = BlackBackground,
      border = BorderStroke(1.2.dp, GoldBorder)
    ) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .verticalScroll(rememberScrollState())
          .padding(20.dp)
      ) {
        // Header
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          Text(
            text = if (productToEdit != null) "تعديل بيانات المنتج" else "إضافة منتج جديد",
            color = WhitePrimary,
            fontSize = 17.sp,
            fontWeight = FontWeight.Bold
          )

          IconButton(onClick = onDismiss) {
            Icon(Icons.Default.Close, contentDescription = "إغلاق", tint = WhiteMuted)
          }
        }

        HorizontalDivider(
          color = GoldBorder,
          thickness = 0.8.dp,
          modifier = Modifier.padding(vertical = 12.dp)
        )

        // Image Picker Area
        Box(
          modifier = Modifier
            .fillMaxWidth()
            .height(150.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(BlackSurfaceCard)
            .border(1.dp, GoldBorder, RoundedCornerShape(12.dp))
            .clickable {
              photoPickerLauncher.launch(
                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
              )
            }
            .testTag("admin_pick_image_button"),
          contentAlignment = Alignment.Center
        ) {
          if (selectedImageUri != null) {
            AsyncImage(
              model = ImageRequest.Builder(LocalContext.current)
                .data(selectedImageUri)
                .crossfade(true)
                .build(),
              contentDescription = "صورة المنتج المختارة",
              modifier = Modifier.fillMaxSize(),
              contentScale = ContentScale.Crop
            )
          } else if (customImageUrl.isNotBlank()) {
            AsyncImage(
              model = ImageRequest.Builder(LocalContext.current)
                .data(customImageUrl)
                .crossfade(true)
                .build(),
              contentDescription = "صورة المنتج عبر الرابط",
              modifier = Modifier.fillMaxSize(),
              contentScale = ContentScale.Crop
            )
          } else if (productToEdit != null) {
            ProductImageDisplay(
              product = productToEdit,
              modifier = Modifier.fillMaxSize()
            )
          } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
              Icon(
                imageVector = Icons.Default.AddPhotoAlternate,
                contentDescription = null,
                tint = GoldPrimary,
                modifier = Modifier.size(38.dp)
              )
              Spacer(modifier = Modifier.height(6.dp))
              Text(
                text = "اختر صورة المنتج من المعرض (Photo Picker)",
                color = GoldLight,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium
              )
              Text(
                text = "سيتم رفعها لـ Firebase Storage لتظهر فوراً لجميع العملاء",
                color = WhiteMuted,
                fontSize = 10.sp
              )
            }
          }
        }

        // Toggle Direct URL Field
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          Text(
            text = if (showUrlField) "إخفاء رابط الصورة المباشر" else "أو أدخل رابط صورة خارجي (URL)",
            color = GoldLight,
            fontSize = 11.sp,
            modifier = Modifier.clickable { showUrlField = !showUrlField }
          )
          Icon(
            imageVector = Icons.Default.Link,
            contentDescription = null,
            tint = GoldLight,
            modifier = Modifier.size(14.dp)
          )
        }

        if (showUrlField) {
          Spacer(modifier = Modifier.height(6.dp))
          OutlinedTextField(
            value = customImageUrl,
            onValueChange = { customImageUrl = it },
            label = { Text("رابط الصورة المباشر (https://...)", color = WhiteMuted) },
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

        Spacer(modifier = Modifier.height(14.dp))

        // Product Name
        OutlinedTextField(
          value = name,
          onValueChange = { name = it; errorMessage = null },
          label = { Text("اسم المنتج / الصنف", color = WhiteMuted) },
          singleLine = true,
          modifier = Modifier.fillMaxWidth().testTag("product_name_input"),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        Spacer(modifier = Modifier.height(10.dp))

        // Category Selector
        Text(
          text = "القسم / الفئة:",
          color = GoldLight,
          fontSize = 12.sp,
          fontWeight = FontWeight.Bold,
          modifier = Modifier.padding(bottom = 6.dp)
        )

        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
          SanitaryCategory.editList.forEach { cat ->
            val isSelected = category == cat
            Surface(
              modifier = Modifier
                .weight(1f)
                .clip(RoundedCornerShape(8.dp))
                .clickable { category = cat },
              shape = RoundedCornerShape(8.dp),
              color = if (isSelected) GoldPrimary else BlackSurfaceElevated,
              border = BorderStroke(1.dp, if (isSelected) GoldPrimary else GoldBorder)
            ) {
              Text(
                text = cat,
                color = if (isSelected) Color.Black else WhitePrimary,
                fontSize = 11.sp,
                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                modifier = Modifier.padding(vertical = 8.dp, horizontal = 4.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
              )
            }
          }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Price Input
        OutlinedTextField(
          value = priceStr,
          onValueChange = { priceStr = it; errorMessage = null },
          label = { Text("السعر (بالجنيه ج.م)", color = WhiteMuted) },
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
          singleLine = true,
          modifier = Modifier.fillMaxWidth().testTag("product_price_input"),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        Spacer(modifier = Modifier.height(10.dp))

        // Description Input
        OutlinedTextField(
          value = description,
          onValueChange = { description = it; errorMessage = null },
          label = { Text("الوصف والمواصفات الفنية", color = WhiteMuted) },
          minLines = 3,
          maxLines = 5,
          modifier = Modifier.fillMaxWidth().testTag("product_description_input"),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        Spacer(modifier = Modifier.height(12.dp))

        // Stock and Inventory Controls
        Surface(
          shape = RoundedCornerShape(10.dp),
          color = BlackSurfaceElevated,
          border = BorderStroke(0.8.dp, GoldBorder),
          modifier = Modifier.fillMaxWidth()
        ) {
          Column(modifier = Modifier.padding(12.dp)) {
            Row(
              modifier = Modifier.fillMaxWidth(),
              horizontalArrangement = Arrangement.SpaceBetween,
              verticalAlignment = Alignment.CenterVertically
            ) {
              Column {
                Text(
                  text = "حالة توفر المنتج بالمخزن",
                  color = WhitePrimary,
                  fontSize = 13.sp,
                  fontWeight = FontWeight.Bold
                )
                Text(
                  text = if (inStock) "متوفر حالياً للطلب" else "غير متوفر بالمخزن",
                  color = if (inStock) GoldLight else Color.Red,
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

            Spacer(modifier = Modifier.height(10.dp))

            OutlinedTextField(
              value = stockQuantityStr,
              onValueChange = { stockQuantityStr = it },
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
          }
        }

        if (errorMessage != null) {
          Spacer(modifier = Modifier.height(8.dp))
          Text(
            text = errorMessage ?: "",
            color = Color.Red,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium
          )
        }

        Spacer(modifier = Modifier.height(20.dp))

        // Save Button
        Button(
          onClick = {
            val price = priceStr.toDoubleOrNull()
            val qty = stockQuantityStr.toIntOrNull() ?: 10
            if (name.isBlank()) {
              errorMessage = "يرجى كتابة اسم المنتج"
            } else if (price == null || price <= 0) {
              errorMessage = "يرجى كتابة سعر صحيح"
            } else if (description.isBlank()) {
              errorMessage = "يرجى كتابة مواصفات المنتج"
            } else {
              onSaveProduct(
                name.trim(),
                price,
                category,
                description.trim(),
                selectedImageUri,
                if (customImageUrl.isNotBlank()) customImageUrl.trim() else null,
                inStock,
                qty
              )
            }
          },
          enabled = true,
          modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .testTag("save_product_submit_button"),
          shape = RoundedCornerShape(12.dp),
          colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
        ) {
          if (isLoading) {
            CircularProgressIndicator(color = Color.Black, modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
            Spacer(modifier = Modifier.width(8.dp))
            Text("جاري الحفظ والمزامنة مع السحابة...", color = Color.Black, fontWeight = FontWeight.Bold)
          } else {
            Icon(Icons.Default.Save, contentDescription = null, tint = Color.Black, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text(
              text = if (productToEdit != null) "حفظ ومزامنة التعديلات" else "إضافة المنتج ونشره للعملاء",
              color = Color.Black,
              fontSize = 14.sp,
              fontWeight = FontWeight.Bold
            )
          }
        }
      }
    }
  }
}
