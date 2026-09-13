package com.example.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AdminPanelSettings
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.example.model.Product
import com.example.ui.theme.BlackBackground
import com.example.ui.theme.BlackSurfaceCard
import com.example.ui.theme.BlackSurfaceElevated
import com.example.ui.theme.DangerRed
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.SuccessGreen
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary

@Composable
fun AdminPanelDialog(
  isAdminLoggedIn: Boolean,
  products: List<Product>,
  adminWhatsAppNumber: String,
  onDismiss: () -> Unit,
  onVerifyPin: (String) -> Boolean,
  onLogoutAdmin: () -> Unit,
  onOpenAddProduct: () -> Unit,
  onOpenEditProduct: (Product) -> Unit,
  onDeleteProduct: (String) -> Unit,
  onUpdateAdminWhatsApp: (String) -> Unit,
  isFirebaseConnected: Boolean = false,
  isSyncing: Boolean = false,
  onSyncFirestore: () -> Unit = {},
  onConfigureFirebase: (projectId: String, apiKey: String, appId: String, storageBucket: String) -> Unit = { _, _, _, _ -> },
  biometricNotice: String? = null,
  onRetryBiometric: (() -> Unit)? = null,
  onUpdateAdminPassword: ((String) -> Boolean)? = null,
  modifier: Modifier = Modifier
) {
  var pinInput by remember { mutableStateOf("") }
  var pinError by remember { mutableStateOf(false) }

  var whatsappNumberInput by remember { mutableStateOf(adminWhatsAppNumber) }
  var isEditingWhatsApp by remember { mutableStateOf(false) }

  var showFirebaseConfigDialog by remember { mutableStateOf(false) }
  var productToDelete by remember { mutableStateOf<Product?>(null) }

  var showChangePasswordDialog by remember { mutableStateOf(false) }
  var newPasswordInput by remember { mutableStateOf("") }
  var confirmPasswordInput by remember { mutableStateOf("") }
  var changePasswordError by remember { mutableStateOf<String?>(null) }

  Dialog(
    onDismissRequest = onDismiss,
    properties = DialogProperties(usePlatformDefaultWidth = false)
  ) {
    Surface(
      modifier = modifier
        .fillMaxWidth(0.95f)
        .fillMaxHeight(0.92f),
      shape = RoundedCornerShape(20.dp),
      color = BlackBackground,
      border = BorderStroke(1.2.dp, GoldBorder)
    ) {
      if (!isAdminLoggedIn) {
        // Biometric & Fallback Password Screen for Admin
        Column(
          modifier = Modifier
            .fillMaxWidth()
            .padding(24.dp),
          horizontalAlignment = Alignment.CenterHorizontally,
          verticalArrangement = Arrangement.Center
        ) {
          Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End
          ) {
            IconButton(onClick = onDismiss) {
              Icon(Icons.Default.Close, contentDescription = "إغلاق", tint = WhiteMuted)
            }
          }

          Spacer(modifier = Modifier.height(4.dp))

          Box(
            modifier = Modifier
              .size(68.dp)
              .clip(CircleShape)
              .background(GoldPrimary.copy(alpha = 0.15f))
              .border(1.5.dp, GoldPrimary, CircleShape),
            contentAlignment = Alignment.Center
          ) {
            Icon(
              imageVector = Icons.Default.Fingerprint,
              contentDescription = "بصمة المدير",
              tint = GoldPrimary,
              modifier = Modifier.size(42.dp)
            )
          }

          Spacer(modifier = Modifier.height(14.dp))

          Text(
            text = "تسجيل دخول إدارة VIB ALAA ELGNDY",
            color = WhitePrimary,
            fontSize = 17.sp,
            fontWeight = FontWeight.Bold
          )

          Text(
            text = "الوصول الحصري للمدير لإدارة وتعديل المعروضات والأسعار",
            color = WhiteMuted,
            fontSize = 11.sp,
            modifier = Modifier.padding(top = 4.dp, bottom = 14.dp)
          )

          // Biometric retry button if supported
          if (onRetryBiometric != null) {
            Button(
              onClick = onRetryBiometric,
              modifier = Modifier
                .fillMaxWidth(0.88f)
                .height(48.dp)
                .testTag("admin_biometric_retry_button"),
              shape = RoundedCornerShape(12.dp),
              colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
            ) {
              Icon(
                imageVector = Icons.Default.Fingerprint,
                contentDescription = null,
                tint = Color.Black,
                modifier = Modifier.size(22.dp)
              )
              Spacer(modifier = Modifier.width(8.dp))
              Text(
                text = "التحقق ببصمة الإصبع الآن",
                color = Color.Black,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold
              )
            }

            Spacer(modifier = Modifier.height(12.dp))

            Row(
              modifier = Modifier.fillMaxWidth(0.88f),
              verticalAlignment = Alignment.CenterVertically
            ) {
              HorizontalDivider(modifier = Modifier.weight(1f), color = GoldBorder)
              Text(
                text = " أو بكلمة المرور المشفرة ",
                color = GoldLight,
                fontSize = 11.sp,
                modifier = Modifier.padding(horizontal = 6.dp)
              )
              HorizontalDivider(modifier = Modifier.weight(1f), color = GoldBorder)
            }

            Spacer(modifier = Modifier.height(12.dp))
          }

          // Biometric notice message if biometric failed or unavailable
          if (!biometricNotice.isNullOrBlank()) {
            Surface(
              color = BlackSurfaceElevated,
              shape = RoundedCornerShape(10.dp),
              border = BorderStroke(0.8.dp, GoldBorder.copy(alpha = 0.7f)),
              modifier = Modifier
                .fillMaxWidth(0.88f)
                .padding(bottom = 12.dp)
            ) {
              Row(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
              ) {
                Icon(
                  imageVector = Icons.Default.Security,
                  contentDescription = null,
                  tint = GoldLight,
                  modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                  text = biometricNotice,
                  color = WhiteMuted,
                  fontSize = 11.sp,
                  lineHeight = 15.sp
                )
              }
            }
          }

          OutlinedTextField(
            value = pinInput,
            onValueChange = {
              pinInput = it
              pinError = false
            },
            label = { Text("كلمة مرور المدير المشفرة", color = WhiteMuted) },
            leadingIcon = {
              Icon(Icons.Default.Lock, contentDescription = null, tint = GoldPrimary, modifier = Modifier.size(18.dp))
            },
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            singleLine = true,
            modifier = Modifier
              .fillMaxWidth(0.88f)
              .testTag("admin_pin_input"),
            colors = OutlinedTextFieldDefaults.colors(
              focusedBorderColor = GoldPrimary,
              unfocusedBorderColor = GoldBorder,
              focusedTextColor = WhitePrimary,
              unfocusedTextColor = WhitePrimary
            )
          )

          if (pinError) {
            Text(
              text = "كلمة المرور غير صحيحة، يرجى إعادة المحاولة",
              color = DangerRed,
              fontSize = 12.sp,
              modifier = Modifier.padding(top = 8.dp)
            )
          }

          Spacer(modifier = Modifier.height(16.dp))

          Button(
            onClick = {
              if (onVerifyPin(pinInput)) {
                pinError = false
              } else {
                pinError = true
              }
            },
            modifier = Modifier
              .fillMaxWidth(0.88f)
              .height(48.dp)
              .testTag("admin_login_submit_button"),
            shape = RoundedCornerShape(12.dp),
            colors = ButtonDefaults.buttonColors(
              containerColor = if (onRetryBiometric != null) BlackSurfaceElevated else GoldPrimary
            ),
            border = if (onRetryBiometric != null) BorderStroke(1.2.dp, GoldPrimary) else null
          ) {
            Text(
              text = "تسجيل دخول بكلمة المرور",
              color = if (onRetryBiometric != null) GoldPrimary else Color.Black,
              fontSize = 14.sp,
              fontWeight = FontWeight.Bold
            )
          }

          Spacer(modifier = Modifier.height(14.dp))

          Text(
            text = "🔒 حماية مشفرة بتقنية SHA-256 تمنع كشف كلمة المرور أو وصول العملاء",
            color = WhiteMuted.copy(alpha = 0.7f),
            fontSize = 10.sp
          )
        }
      } else {
        // Admin Logged In Screen
        Column(
          modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
        ) {
          // Top Bar
          Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
          ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
              Icon(
                imageVector = Icons.Default.AdminPanelSettings,
                contentDescription = null,
                tint = GoldPrimary,
                modifier = Modifier.size(24.dp)
              )
              Spacer(modifier = Modifier.width(8.dp))
              Column {
                Text(
                  text = "إدارة المنتجات - VIB",
                  color = WhitePrimary,
                  fontSize = 16.sp,
                  fontWeight = FontWeight.Bold
                )
                Text(
                  text = "إجمالي المعروضات: ${products.size} منتج",
                  color = GoldLight,
                  fontSize = 12.sp
                )
              }
            }

            Row {
              IconButton(onClick = onLogoutAdmin) {
                Icon(
                  imageVector = Icons.AutoMirrored.Filled.Logout,
                  contentDescription = "خروج المدير",
                  tint = DangerRed
                )
              }
              IconButton(onClick = onDismiss) {
                Icon(
                  imageVector = Icons.Default.Close,
                  contentDescription = "إغلاق",
                  tint = WhiteMuted
                )
              }
            }
          }

          HorizontalDivider(
            color = GoldBorder,
            thickness = 0.8.dp,
            modifier = Modifier.padding(vertical = 8.dp)
          )

          // WhatsApp Configuration Card
          Surface(
            color = BlackSurfaceElevated,
            shape = RoundedCornerShape(10.dp),
            border = BorderStroke(0.8.dp, GoldBorder),
            modifier = Modifier.fillMaxWidth()
          ) {
            Column(modifier = Modifier.padding(10.dp)) {
              Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
              ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                  Icon(
                    imageVector = Icons.Default.Phone,
                    contentDescription = null,
                    tint = GoldPrimary,
                    modifier = Modifier.size(16.dp)
                  )
                  Spacer(modifier = Modifier.width(6.dp))
                  Text(
                    text = "رقم واتساب استلام الطلبات:",
                    color = WhitePrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium
                  )
                }

                TextButton(
                  onClick = {
                    if (isEditingWhatsApp) {
                      onUpdateAdminWhatsApp(whatsappNumberInput.trim())
                      isEditingWhatsApp = false
                    } else {
                      isEditingWhatsApp = true
                    }
                  }
                ) {
                  Text(
                    text = if (isEditingWhatsApp) "حفظ" else "تعديل",
                    color = GoldLight,
                    fontSize = 12.sp
                  )
                }
              }

              if (isEditingWhatsApp) {
                OutlinedTextField(
                  value = whatsappNumberInput,
                  onValueChange = { whatsappNumberInput = it },
                  singleLine = true,
                  keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                  modifier = Modifier.fillMaxWidth().height(52.dp),
                  colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = GoldPrimary,
                    unfocusedBorderColor = GoldBorder,
                    focusedTextColor = WhitePrimary,
                    unfocusedTextColor = WhitePrimary
                  )
                )
              } else {
                Text(
                  text = adminWhatsAppNumber,
                  color = GoldPrimary,
                  fontSize = 13.sp,
                  fontWeight = FontWeight.Bold
                )
              }
            }
          }

          Spacer(modifier = Modifier.height(8.dp))

          // Firebase Cloud Status & Sync Card
          Surface(
            color = BlackSurfaceElevated,
            shape = RoundedCornerShape(10.dp),
            border = BorderStroke(0.8.dp, if (isFirebaseConnected) SuccessGreen.copy(alpha = 0.6f) else GoldBorder),
            modifier = Modifier.fillMaxWidth()
          ) {
            Row(
              modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 8.dp),
              horizontalArrangement = Arrangement.SpaceBetween,
              verticalAlignment = Alignment.CenterVertically
            ) {
              Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                  modifier = Modifier
                    .size(10.dp)
                    .clip(CircleShape)
                    .background(if (isFirebaseConnected) SuccessGreen else GoldLight)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Column {
                  Text(
                    text = if (isFirebaseConnected) "السحابة: متصل بـ Firestore ✅" else "مزامنة سحابية جاهزة",
                    color = WhitePrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                  )
                  Text(
                    text = "Storage لحفظ ومزامنة صور المنتجات",
                    color = WhiteMuted,
                    fontSize = 10.sp
                  )
                }
              }

              Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(
                  onClick = onSyncFirestore,
                  enabled = !isSyncing,
                  modifier = Modifier.size(34.dp)
                ) {
                  if (isSyncing) {
                    CircularProgressIndicator(
                      color = GoldPrimary,
                      modifier = Modifier.size(18.dp),
                      strokeWidth = 2.dp
                    )
                  } else {
                    Icon(
                      imageVector = Icons.Default.CloudSync,
                      contentDescription = "مزامنة مع السحابة",
                      tint = GoldPrimary,
                      modifier = Modifier.size(20.dp)
                    )
                  }
                }
                IconButton(
                  onClick = { showFirebaseConfigDialog = true },
                  modifier = Modifier.size(34.dp)
                ) {
                  Icon(
                    imageVector = Icons.Default.Settings,
                    contentDescription = "إعدادات الربط",
                    tint = WhiteMuted,
                    modifier = Modifier.size(18.dp)
                  )
                }
              }
            }
          }

          Spacer(modifier = Modifier.height(8.dp))

          // Admin Security & Biometrics Card
          Surface(
            color = BlackSurfaceElevated,
            shape = RoundedCornerShape(10.dp),
            border = BorderStroke(0.8.dp, GoldBorder),
            modifier = Modifier.fillMaxWidth()
          ) {
            Row(
              modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 8.dp),
              horizontalArrangement = Arrangement.SpaceBetween,
              verticalAlignment = Alignment.CenterVertically
            ) {
              Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                  imageVector = Icons.Default.Fingerprint,
                  contentDescription = null,
                  tint = GoldPrimary,
                  modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(6.dp))
                Column {
                  Text(
                    text = "أمان المدير: البصمة + تشفير SHA-256",
                    color = WhitePrimary,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold
                  )
                  Text(
                    text = "محمي من وصول العملاء • تشفير غير قابل للعكس",
                    color = WhiteMuted,
                    fontSize = 10.sp
                  )
                }
              }

              if (onUpdateAdminPassword != null) {
                TextButton(onClick = {
                  newPasswordInput = ""
                  confirmPasswordInput = ""
                  changePasswordError = null
                  showChangePasswordDialog = true
                }) {
                  Text("تغيير الرمز", color = GoldLight, fontSize = 11.sp)
                }
              }
            }
          }

          Spacer(modifier = Modifier.height(10.dp))

          // Add Product Button
          Button(
            onClick = onOpenAddProduct,
            modifier = Modifier
              .fillMaxWidth()
              .height(46.dp)
              .testTag("admin_add_product_button"),
            shape = RoundedCornerShape(10.dp),
            colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
          ) {
            Icon(Icons.Default.Add, contentDescription = null, tint = Color.Black, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text(
              text = "إضافة صنف / منتج جديد",
              color = Color.Black,
              fontSize = 14.sp,
              fontWeight = FontWeight.Bold
            )
          }

          Spacer(modifier = Modifier.height(10.dp))

          // Products List with Edit / Delete actions
          LazyColumn(
            modifier = Modifier
              .weight(1f)
              .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
          ) {
            items(products, key = { it.id }) { product ->
              Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(10.dp),
                colors = CardDefaults.cardColors(containerColor = BlackSurfaceCard),
                border = BorderStroke(0.6.dp, GoldBorder)
              ) {
                Row(
                  modifier = Modifier
                    .fillMaxWidth()
                    .padding(8.dp),
                  verticalAlignment = Alignment.CenterVertically
                ) {
                  // Image
                  Box(
                    modifier = Modifier
                      .size(50.dp)
                      .clip(RoundedCornerShape(6.dp))
                  ) {
                    ProductImageDisplay(
                      product = product,
                      modifier = Modifier.fillMaxSize()
                    )
                  }

                  Spacer(modifier = Modifier.width(10.dp))

                  // Info
                  Column(modifier = Modifier.weight(1f)) {
                    Text(
                      text = product.name,
                      color = WhitePrimary,
                      fontSize = 13.sp,
                      fontWeight = FontWeight.Bold,
                      maxLines = 1,
                      overflow = TextOverflow.Ellipsis
                    )
                    Text(
                      text = product.category,
                      color = GoldLight,
                      fontSize = 11.sp
                    )
                    PriceDisplay(price = product.price, fontSize = 12)
                  }

                  // Edit button
                  IconButton(
                    onClick = { onOpenEditProduct(product) },
                    modifier = Modifier.size(32.dp).testTag("admin_edit_${product.id}")
                  ) {
                    Icon(
                      imageVector = Icons.Default.Edit,
                      contentDescription = "تعديل",
                      tint = GoldPrimary,
                      modifier = Modifier.size(18.dp)
                    )
                  }

                  // Delete button
                  IconButton(
                    onClick = { productToDelete = product },
                    modifier = Modifier.size(32.dp).testTag("admin_delete_${product.id}")
                  ) {
                    Icon(
                      imageVector = Icons.Default.Delete,
                      contentDescription = "حذف",
                      tint = DangerRed,
                      modifier = Modifier.size(18.dp)
                    )
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Delete Confirmation Dialog
  if (productToDelete != null) {
    AlertDialog(
      onDismissRequest = { productToDelete = null },
      title = {
        Text(
          text = "تأكيد حذف المنتج",
          color = WhitePrimary,
          fontWeight = FontWeight.Bold,
          fontSize = 16.sp
        )
      },
      text = {
        Text(
          text = "هل أنت متأكد من رغبتك في حذف \"${productToDelete?.name}\" من قاعدة البيانات نهائياً؟",
          color = WhiteMuted,
          fontSize = 13.sp
        )
      },
      confirmButton = {
        Button(
          onClick = {
            productToDelete?.let { onDeleteProduct(it.id) }
            productToDelete = null
          },
          colors = ButtonDefaults.buttonColors(containerColor = DangerRed)
        ) {
          Text("تأكيد الحذف", color = Color.White)
        }
      },
      dismissButton = {
        TextButton(onClick = { productToDelete = null }) {
          Text("إلغاء", color = WhiteMuted)
        }
      },
      containerColor = BlackSurfaceElevated,
      shape = RoundedCornerShape(14.dp)
    )
  }

  // Firebase Configuration Dialog
  if (showFirebaseConfigDialog) {
    var projectId by remember { mutableStateOf("") }
    var apiKey by remember { mutableStateOf("") }
    var appId by remember { mutableStateOf("") }
    var bucket by remember { mutableStateOf("") }

    AlertDialog(
      onDismissRequest = { showFirebaseConfigDialog = false },
      title = {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Icon(Icons.Default.CloudDone, contentDescription = null, tint = GoldPrimary, modifier = Modifier.size(22.dp))
          Spacer(modifier = Modifier.width(6.dp))
          Text(text = "إعدادات Firebase السحابية", color = WhitePrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
      },
      text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          Text(
            text = "يمكنك تشغيل المزامنة عبر وضع ملف google-services.json أو كتابة البيانات هنا:",
            color = WhiteMuted,
            fontSize = 12.sp
          )
          OutlinedTextField(
            value = projectId,
            onValueChange = { projectId = it },
            label = { Text("Project ID", fontSize = 11.sp, color = WhiteMuted) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
          )
          OutlinedTextField(
            value = apiKey,
            onValueChange = { apiKey = it },
            label = { Text("Web API Key", fontSize = 11.sp, color = WhiteMuted) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
          )
          OutlinedTextField(
            value = appId,
            onValueChange = { appId = it },
            label = { Text("Application ID", fontSize = 11.sp, color = WhiteMuted) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
          )
          OutlinedTextField(
            value = bucket,
            onValueChange = { bucket = it },
            label = { Text("Storage Bucket (مثال: myapp.appspot.com)", fontSize = 11.sp, color = WhiteMuted) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
          )
        }
      },
      confirmButton = {
        Button(
          onClick = {
            if (projectId.isNotBlank()) {
              onConfigureFirebase(projectId, apiKey, appId, bucket)
            }
            showFirebaseConfigDialog = false
          },
          colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
        ) {
          Text("حفظ وتطبيق", color = Color.Black, fontWeight = FontWeight.Bold)
        }
      },
      dismissButton = {
        TextButton(onClick = { showFirebaseConfigDialog = false }) {
          Text("إغلاق", color = WhiteMuted)
        }
      },
      containerColor = BlackSurfaceElevated,
      shape = RoundedCornerShape(14.dp)
    )
  }

  // Change Admin Password Dialog (SHA-256 Hashed)
  if (showChangePasswordDialog) {
    AlertDialog(
      onDismissRequest = { showChangePasswordDialog = false },
      containerColor = BlackSurfaceElevated,
      shape = RoundedCornerShape(16.dp),
      title = {
        Row(verticalAlignment = Alignment.CenterVertically) {
          Icon(Icons.Default.Security, contentDescription = null, tint = GoldPrimary, modifier = Modifier.size(20.dp))
          Spacer(modifier = Modifier.width(8.dp))
          Text(text = "تغيير كلمة مرور المدير", color = GoldPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        }
      },
      text = {
        Column {
          Text(
            text = "يتم حفظ كلمة المرور مشفرة كلياً عبر خوارزمية SHA-256 الآمنة لحماية لوحة الإدارة.",
            color = WhiteMuted,
            fontSize = 11.sp,
            modifier = Modifier.padding(bottom = 12.dp)
          )

          OutlinedTextField(
            value = newPasswordInput,
            onValueChange = { newPasswordInput = it },
            label = { Text("كلمة المرور الجديدة", color = WhiteMuted) },
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
              focusedBorderColor = GoldPrimary,
              unfocusedBorderColor = GoldBorder,
              focusedTextColor = WhitePrimary,
              unfocusedTextColor = WhitePrimary
            )
          )

          Spacer(modifier = Modifier.height(8.dp))

          OutlinedTextField(
            value = confirmPasswordInput,
            onValueChange = { confirmPasswordInput = it },
            label = { Text("تأكيد كلمة المرور", color = WhiteMuted) },
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            colors = OutlinedTextFieldDefaults.colors(
              focusedBorderColor = GoldPrimary,
              unfocusedBorderColor = GoldBorder,
              focusedTextColor = WhitePrimary,
              unfocusedTextColor = WhitePrimary
            )
          )

          if (changePasswordError != null) {
            Text(
              text = changePasswordError ?: "",
              color = DangerRed,
              fontSize = 11.sp,
              modifier = Modifier.padding(top = 6.dp)
            )
          }
        }
      },
      confirmButton = {
        Button(
          onClick = {
            if (newPasswordInput.length < 4) {
              changePasswordError = "يجب ألا تقل عن 4 أرقام أو حروف"
            } else if (newPasswordInput != confirmPasswordInput) {
              changePasswordError = "كلمتا المرور غير متطابقتين"
            } else {
              val ok = onUpdateAdminPassword?.invoke(newPasswordInput) ?: false
              if (ok) {
                showChangePasswordDialog = false
              } else {
                changePasswordError = "فشل تحديث كلمة المرور"
              }
            }
          },
          colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
        ) {
          Text("حفظ وتشفير", color = Color.Black, fontWeight = FontWeight.Bold)
        }
      },
      dismissButton = {
        TextButton(onClick = { showChangePasswordDialog = false }) {
          Text("إلغاء", color = WhiteMuted)
        }
      }
    )
  }
}
