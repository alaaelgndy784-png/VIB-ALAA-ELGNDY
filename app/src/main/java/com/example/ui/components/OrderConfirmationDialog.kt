package com.example.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.WhatsAppGreen
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary

@Composable
fun OrderConfirmationDialog(
  savedCustomer: Customer?,
  totalAmount: Double,
  itemCount: Int,
  onDismiss: () -> Unit,
  onConfirmOrder: (name: String, phone: String, address: String, notes: String) -> Unit,
  modifier: Modifier = Modifier
) {
  var name by remember { mutableStateOf(savedCustomer?.name ?: "") }
  var phone by remember { mutableStateOf(savedCustomer?.phone ?: "") }
  var address by remember { mutableStateOf(savedCustomer?.address ?: "") }
  var notes by remember { mutableStateOf("") }
  var errorText by remember { mutableStateOf<String?>(null) }

  Dialog(onDismissRequest = onDismiss) {
    Surface(
      modifier = modifier.fillMaxWidth(),
      shape = RoundedCornerShape(20.dp),
      color = BlackBackground,
      border = BorderStroke(1.2.dp, GoldBorder)
    ) {
      Column(
        modifier = Modifier
          .padding(20.dp)
          .verticalScroll(rememberScrollState())
      ) {
        // Header
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically
        ) {
          Column {
            Text(
              text = "تأكيد بيانات الطلب",
              color = WhitePrimary,
              fontSize = 17.sp,
              fontWeight = FontWeight.Bold
            )
            Text(
              text = "سيتم إرسال الفاتورة مباشرة لمحادثة واتساب VIB",
              color = GoldLight,
              fontSize = 12.sp
            )
          }

          IconButton(onClick = onDismiss) {
            Icon(imageVector = Icons.Default.Close, contentDescription = "إلغاء", tint = WhiteMuted)
          }
        }

        HorizontalDivider(
          color = GoldBorder,
          thickness = 0.8.dp,
          modifier = Modifier.padding(vertical = 12.dp)
        )

        // Summary Card
        Surface(
          color = BlackSurfaceElevated,
          shape = RoundedCornerShape(10.dp),
          border = BorderStroke(0.8.dp, GoldBorder),
          modifier = Modifier.fillMaxWidth()
        ) {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
          ) {
            Text(
              text = "عدد الأصناف: $itemCount",
              color = WhitePrimary,
              fontSize = 13.sp
            )
            PriceDisplay(price = totalAmount, fontSize = 16, isLarge = true)
          }
        }

        Spacer(modifier = Modifier.height(14.dp))

        // Name Field
        OutlinedTextField(
          value = name,
          onValueChange = { name = it; errorText = null },
          label = { Text("الاسم بالكامل", color = WhiteMuted) },
          leadingIcon = { Icon(Icons.Default.Person, contentDescription = null, tint = GoldPrimary) },
          singleLine = true,
          modifier = Modifier
            .fillMaxWidth()
            .testTag("order_name_input"),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        Spacer(modifier = Modifier.height(10.dp))

        // Phone Field
        OutlinedTextField(
          value = phone,
          onValueChange = { phone = it; errorText = null },
          label = { Text("رقم الهاتف / الواتساب", color = WhiteMuted) },
          leadingIcon = { Icon(Icons.Default.Phone, contentDescription = null, tint = GoldPrimary) },
          keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
          singleLine = true,
          modifier = Modifier
            .fillMaxWidth()
            .testTag("order_phone_input"),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        Spacer(modifier = Modifier.height(10.dp))

        // Address Field
        OutlinedTextField(
          value = address,
          onValueChange = { address = it },
          label = { Text("عنوان التوصيل / المدينة", color = WhiteMuted) },
          leadingIcon = { Icon(Icons.Default.Home, contentDescription = null, tint = GoldPrimary) },
          singleLine = true,
          modifier = Modifier
            .fillMaxWidth()
            .testTag("order_address_input"),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        Spacer(modifier = Modifier.height(10.dp))

        // Notes Field
        OutlinedTextField(
          value = notes,
          onValueChange = { notes = it },
          label = { Text("ملاحظات خاصة (اختياري)", color = WhiteMuted) },
          leadingIcon = { Icon(Icons.AutoMirrored.Filled.Notes, contentDescription = null, tint = GoldPrimary) },
          maxLines = 2,
          modifier = Modifier.fillMaxWidth(),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = GoldPrimary,
            unfocusedBorderColor = GoldBorder,
            focusedTextColor = WhitePrimary,
            unfocusedTextColor = WhitePrimary
          )
        )

        if (errorText != null) {
          Spacer(modifier = Modifier.height(8.dp))
          Text(
            text = errorText ?: "",
            color = Color.Red,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium
          )
        }

        Spacer(modifier = Modifier.height(18.dp))

        Button(
          onClick = {
            if (name.isBlank()) {
              errorText = "يرجى كتابة الاسم لتسجيل الطلب"
            } else if (phone.isBlank() || phone.length < 8) {
              errorText = "يرجى كتابة رقم هاتف صحيح"
            } else {
              onConfirmOrder(name.trim(), phone.trim(), address.trim(), notes.trim())
            }
          },
          modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .testTag("confirm_order_send_button"),
          shape = RoundedCornerShape(12.dp),
          colors = ButtonDefaults.buttonColors(containerColor = WhatsAppGreen)
        ) {
          Icon(
            imageVector = Icons.AutoMirrored.Filled.Send,
            contentDescription = null,
            tint = Color.White,
            modifier = Modifier.size(18.dp)
          )
          Spacer(modifier = Modifier.width(8.dp))
          Text(
            text = "تأكيد وإرسال إلى واتساب",
            color = Color.White,
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold
          )
        }
      }
    }
  }
}
