package com.example.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import com.example.model.Customer
import com.example.ui.theme.BlackBackground
import com.example.ui.theme.BlackSurfaceElevated
import com.example.ui.theme.DangerRed
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.SuccessGreen
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary

@Composable
fun LoginDialog(
  currentCustomer: Customer?,
  onDismiss: () -> Unit,
  onSaveCustomer: (name: String, phone: String, address: String) -> Unit,
  onLogout: () -> Unit,
  onLookupCustomerByPhone: ((phone: String, onResult: (Customer?) -> Unit) -> Unit)? = null,
  modifier: Modifier = Modifier
) {
  var name by remember { mutableStateOf(currentCustomer?.name ?: "") }
  var phone by remember { mutableStateOf(currentCustomer?.phone ?: "") }
  var address by remember { mutableStateOf(currentCustomer?.address ?: "") }
  var errorText by remember { mutableStateOf<String?>(null) }
  var lookupStatus by remember { mutableStateOf<String?>(null) }
  var isSearchingPhone by remember { mutableStateOf(false) }

  Dialog(onDismissRequest = onDismiss) {
    Surface(
      modifier = modifier.fillMaxWidth(),
      shape = RoundedCornerShape(20.dp),
      color = BlackBackground,
      border = BorderStroke(1.2.dp, GoldBorder)
    ) {
      Column(modifier = Modifier.padding(20.dp)) {
        // Header
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
              imageVector = Icons.Default.AccountCircle,
              contentDescription = null,
              tint = GoldPrimary,
              modifier = Modifier.size(26.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
              text = if (currentCustomer != null) "الملف الشخصي للعميل" else "تسجيل الدخول بالهاتف",
              color = WhitePrimary,
              fontSize = 17.sp,
              fontWeight = FontWeight.Bold
            )
          }

          IconButton(onClick = onDismiss) {
            Icon(imageVector = Icons.Default.Close, contentDescription = "إغلاق", tint = WhiteMuted)
          }
        }

        HorizontalDivider(
          color = GoldBorder,
          thickness = 0.8.dp,
          modifier = Modifier.padding(vertical = 12.dp)
        )

        if (currentCustomer != null) {
          // Logged in info view
          Surface(
            color = BlackSurfaceElevated,
            shape = RoundedCornerShape(12.dp),
            border = BorderStroke(0.8.dp, GoldBorder),
            modifier = Modifier.fillMaxWidth()
          ) {
            Column(modifier = Modifier.padding(14.dp)) {
              Text(
                text = "مرحباً بك: ${currentCustomer.name}",
                color = GoldPrimary,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold
              )
              Spacer(modifier = Modifier.height(4.dp))
              Text(
                text = "رقم الهاتف: ${currentCustomer.phone}",
                color = WhitePrimary,
                fontSize = 13.sp
              )
              if (currentCustomer.address.isNotBlank()) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                  text = "العنوان: ${currentCustomer.address}",
                  color = WhiteMuted,
                  fontSize = 12.sp
                )
              }
            }
          }

          Spacer(modifier = Modifier.height(16.dp))

          Text(
            text = "تعديل البيانات المسجلة:",
            color = GoldLight,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium
          )
          Spacer(modifier = Modifier.height(8.dp))
        } else {
          Text(
            text = "أدخل رقم هاتفك لتسجيل الدخول أو استرجاع بياناتك السابقة المسجلة في السحابة فوراً",
            color = WhiteMuted,
            fontSize = 12.sp,
            lineHeight = 18.sp
          )
          Spacer(modifier = Modifier.height(14.dp))
        }

        // Phone input
        OutlinedTextField(
          value = phone,
          onValueChange = {
            phone = it
            errorText = null
            lookupStatus = null
          },
          label = { Text("رقم الهاتف المحمول", color = WhiteMuted) },
          leadingIcon = { Icon(Icons.Default.Phone, contentDescription = null, tint = GoldPrimary) },
          trailingIcon = {
            if (currentCustomer == null && onLookupCustomerByPhone != null && phone.length >= 8) {
              IconButton(
                onClick = {
                  isSearchingPhone = true
                  onLookupCustomerByPhone(phone.trim()) { found ->
                    isSearchingPhone = false
                    if (found != null) {
                      name = found.name
                      address = found.address
                      lookupStatus = "تم العثور على حسابك المسجل: ${found.name}"
                    } else {
                      lookupStatus = "رقم جديد - يرجى كتابة اسمك للمتابعة"
                    }
                  }
                }
              ) {
                if (isSearchingPhone) {
                  CircularProgressIndicator(
                    color = GoldPrimary,
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp
                  )
                } else {
                  Icon(
                    imageVector = Icons.Default.Search,
                    contentDescription = "بحث عن حسابي",
                    tint = GoldLight
                  )
                }
              }
            }
          },
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
          singleLine = true,
          modifier = Modifier.fillMaxWidth().testTag("login_phone_input"),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        if (lookupStatus != null) {
          Spacer(modifier = Modifier.height(4.dp))
          Text(
            text = lookupStatus ?: "",
            color = SuccessGreen,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium
          )
        }

        Spacer(modifier = Modifier.height(10.dp))

        // Name input
        OutlinedTextField(
          value = name,
          onValueChange = { name = it; errorText = null },
          label = { Text("الاسم بالكامل", color = WhiteMuted) },
          leadingIcon = { Icon(Icons.Default.Person, contentDescription = null, tint = GoldPrimary) },
          singleLine = true,
          modifier = Modifier.fillMaxWidth().testTag("login_name_input"),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        Spacer(modifier = Modifier.height(10.dp))

        // Address input
        OutlinedTextField(
          value = address,
          onValueChange = { address = it },
          label = { Text("العنوان الافتراضي للتوصيل (اختياري)", color = WhiteMuted) },
          leadingIcon = { Icon(Icons.Default.Home, contentDescription = null, tint = GoldPrimary) },
          singleLine = true,
          modifier = Modifier.fillMaxWidth(),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        if (errorText != null) {
          Spacer(modifier = Modifier.height(6.dp))
          Text(text = errorText ?: "", color = Color.Red, fontSize = 12.sp)
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Save Button
        Button(
          onClick = {
            if (phone.isBlank() || phone.length < 8) {
              errorText = "يرجى كتابة رقم هاتف صحيح"
            } else if (name.isBlank()) {
              errorText = "يرجى كتابة الاسم"
            } else {
              onSaveCustomer(name.trim(), phone.trim(), address.trim())
            }
          },
          modifier = Modifier.fillMaxWidth().height(48.dp).testTag("save_profile_button"),
          shape = RoundedCornerShape(12.dp),
          colors = ButtonDefaults.buttonColors(containerColor = GoldPrimary)
        ) {
          Text(
            text = if (currentCustomer != null) "حفظ التعديلات" else "تسجيل الدخول والمتابعة",
            color = Color.Black,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold
          )
        }

        if (currentCustomer != null) {
          Spacer(modifier = Modifier.height(10.dp))
          OutlinedButton(
            onClick = {
              onLogout()
              onDismiss()
            },
            modifier = Modifier.fillMaxWidth().height(44.dp),
            shape = RoundedCornerShape(12.dp),
            border = BorderStroke(0.8.dp, DangerRed.copy(alpha = 0.5f))
          ) {
            Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null, tint = DangerRed, modifier = Modifier.size(16.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text("تسجيل الخروج", color = DangerRed, fontSize = 13.sp)
          }
        }
      }
    }
  }
}
