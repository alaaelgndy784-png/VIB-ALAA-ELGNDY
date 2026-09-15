package com.example.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.R
import com.example.model.SanitaryCategory
import com.example.security.AdminSecurityManager
import com.example.security.findFragmentActivity
import com.example.ui.components.AddEditProductDialog
import com.example.ui.components.AdminModeBanner
import com.example.ui.components.AdminPanelDialog
import com.example.ui.components.CartDialog
import com.example.ui.components.CategoryFilterPill
import com.example.ui.components.DeleteConfirmDialog
import com.example.ui.components.LoginDialog
import com.example.ui.components.LuxuryTopAppBar
import com.example.ui.components.OrderConfirmationDialog
import com.example.ui.components.PriceDisplay
import com.example.ui.components.ProductCard
import com.example.ui.components.ProductDetailDialog
import com.example.ui.components.QuickImageDialog
import com.example.ui.components.QuickPriceDialog
import com.example.ui.components.QuickStockDialog
import com.example.ui.theme.BlackBackground
import com.example.ui.theme.BlackSurfaceCard
import com.example.ui.theme.GoldBorder
import com.example.ui.theme.GoldLight
import com.example.ui.theme.GoldPrimary
import com.example.ui.theme.WhatsAppGreen
import com.example.ui.theme.WhiteMuted
import com.example.ui.theme.WhitePrimary
import com.example.viewmodel.VibViewModel

@Composable
fun VibMainScreen(
  viewModel: VibViewModel,
  modifier: Modifier = Modifier
) {
  val context = LocalContext.current
  val snackbarHostState = remember { SnackbarHostState() }

  val products by viewModel.filteredProducts.collectAsState()
  val allProducts by viewModel.allProducts.collectAsState()
  val selectedCategory by viewModel.selectedCategory.collectAsState()
  val searchQuery by viewModel.searchQuery.collectAsState()
  val cartItems by viewModel.cartItems.collectAsState()
  val cartTotal by viewModel.cartTotal.collectAsState()
  val cartCount by viewModel.cartCount.collectAsState()
  val currentCustomer by viewModel.currentCustomer.collectAsState()
  val isAdminLoggedIn by viewModel.isAdminLoggedIn.collectAsState()
  val adminWhatsAppNumber by viewModel.adminWhatsAppNumber.collectAsState()
  val biometricNotice by viewModel.biometricNotice.collectAsState()

  val triggerBiometricAuth: () -> Unit = {
    val activity = context.findFragmentActivity()
    if (activity != null) {
      AdminSecurityManager.authenticateBiometric(
        activity = activity,
        onSuccess = {
          viewModel.onBiometricAuthSuccess()
        },
        onFallbackPassword = {
          viewModel.openAdminLoginFallback("تم اختيار الدخول بكلمة المرور المشفرة")
        },
        onError = { _, errorMsg ->
          viewModel.openAdminLoginFallback(errorMsg)
        },
        onFailedAttempt = {
          viewModel.onBiometricAttemptFailed()
        }
      )
    } else {
      viewModel.openAdminLoginFallback("تعذر بدء التحقق البيومتري على هذا الجهاز")
    }
  }

  val showCart by viewModel.showCart.collectAsState()
  val showAdmin by viewModel.showAdmin.collectAsState()
  val showLogin by viewModel.showLogin.collectAsState()
  val showAddEditProduct by viewModel.showAddEditProduct.collectAsState()
  val showOrderConfirmation by viewModel.showOrderConfirmation.collectAsState()
  val selectedProductForDetail by viewModel.selectedProductForDetail.collectAsState()
  val productBeingEdited by viewModel.productBeingEdited.collectAsState()
  val productForQuickPrice by viewModel.productForQuickPrice.collectAsState()
  val productForQuickImage by viewModel.productForQuickImage.collectAsState()
  val productForQuickStock by viewModel.productForQuickStock.collectAsState()
  val productForDeleteConfirm by viewModel.productForDeleteConfirm.collectAsState()
  val isLoading by viewModel.isLoading.collectAsState()
  val statusMessage by viewModel.statusMessage.collectAsState()

  LaunchedEffect(statusMessage) {
    statusMessage?.let { msg ->
      snackbarHostState.showSnackbar(msg)
      viewModel.clearStatusMessage()
    }
  }

  // Force RTL for standard Arabic alignment
  CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
    Scaffold(
      modifier = modifier
        .fillMaxSize()
        .background(BlackBackground),
      snackbarHost = { SnackbarHost(snackbarHostState) },
      topBar = {
        LuxuryTopAppBar(
          cartCount = cartCount,
          currentCustomer = currentCustomer,
          isAdminLoggedIn = isAdminLoggedIn,
          onCartClick = { viewModel.toggleCart(true) },
          onProfileClick = { viewModel.toggleLogin(true) },
          onAdminClick = {
            if (isAdminLoggedIn) {
              viewModel.toggleAdmin(true)
            } else {
              triggerBiometricAuth()
            }
          }
        )
      },
      bottomBar = {
        // Sticky Cart Bar if items exist
        AnimatedVisibility(
          visible = cartCount > 0,
          enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
          exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
          Surface(
            modifier = Modifier
              .fillMaxWidth()
              .navigationBarsPadding()
              .padding(horizontal = 16.dp, vertical = 10.dp),
            shape = RoundedCornerShape(16.dp),
            color = GoldPrimary,
            shadowElevation = 8.dp
          ) {
            Row(
              modifier = Modifier
                .fillMaxWidth()
                .clickable { viewModel.toggleCart(true) }
                .padding(horizontal = 16.dp, vertical = 12.dp),
              horizontalArrangement = Arrangement.SpaceBetween,
              verticalAlignment = Alignment.CenterVertically
            ) {
              Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                  modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(Color.Black),
                  contentAlignment = Alignment.Center
                ) {
                  Text(
                    text = "$cartCount",
                    color = GoldPrimary,
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp
                  )
                }
                Spacer(modifier = Modifier.width(10.dp))
                Column {
                  Text(
                    text = "سلة المشتريات جاهزة",
                    color = Color.Black,
                    fontWeight = FontWeight.Bold,
                    fontSize = 13.sp
                  )
                  Text(
                    text = "اضغط لمعاينة الطلب أو إرساله عبر واتساب",
                    color = Color.Black.copy(alpha = 0.8f),
                    fontSize = 11.sp
                  )
                }
              }

              Row(verticalAlignment = Alignment.CenterVertically) {
                PriceDisplay(price = cartTotal, fontSize = 16, isLarge = true)
                Spacer(modifier = Modifier.width(8.dp))
                Icon(
                  imageVector = Icons.Default.ShoppingCart,
                  contentDescription = null,
                  tint = Color.Black,
                  modifier = Modifier.size(20.dp)
                )
              }
            }
          }
        }
      },
      containerColor = BlackBackground
    ) { innerPadding ->
      LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 165.dp),
        modifier = Modifier
          .fillMaxSize()
          .padding(innerPadding)
          .testTag("products_grid"),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
      ) {
        // Admin Mode Dedicated Banner (Visible ONLY when admin is logged in)
        if (isAdminLoggedIn) {
          item(span = { GridItemSpan(maxLineSpan) }) {
            AdminModeBanner(
              onAddNewProduct = { viewModel.openAddProduct() },
              onOpenAdminPanel = { viewModel.toggleAdmin(true) },
              onLogoutAdmin = { viewModel.logoutAdmin() }
            )
          }
        }

        // Hero Showroom Banner (Full Width)
        item(span = { GridItemSpan(maxLineSpan) }) {
          Card(
            modifier = Modifier
              .fillMaxWidth()
              .height(180.dp),
            shape = RoundedCornerShape(16.dp),
            border = BorderStroke(1.dp, GoldBorder),
            colors = CardDefaults.cardColors(containerColor = BlackSurfaceCard)
          ) {
            Box(modifier = Modifier.fillMaxSize()) {
              Image(
                painter = painterResource(id = R.drawable.sanitary_banner),
                contentDescription = "معرض VIB للأدوات الصحية",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
              )

              // Dark Gradient Overlay for readability
              Box(
                modifier = Modifier
                  .fillMaxSize()
                  .background(
                    Brush.verticalGradient(
                      colors = listOf(
                        Color.Black.copy(alpha = 0.3f),
                        Color.Black.copy(alpha = 0.85f)
                      )
                    )
                  )
              )

              Column(
                modifier = Modifier
                  .align(Alignment.BottomStart)
                  .padding(16.dp)
              ) {
                Text(
                  text = "VIB ALAA ELGNDY",
                  color = GoldPrimary,
                  fontWeight = FontWeight.ExtraBold,
                  fontSize = 18.sp,
                  letterSpacing = 1.sp
                )
                Text(
                  text = "لتوزيع وتوريد الأدوات الصحية والسباكة الفاخرة",
                  color = WhitePrimary,
                  fontWeight = FontWeight.Bold,
                  fontSize = 13.sp
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                  text = "أعلى معايير الجودة • نحاس إيطالي أصلي • أطقم ألوان مودرن",
                  color = GoldLight,
                  fontSize = 11.sp
                )
              }
            }
          }
        }

        // Search Bar (Full Width)
        item(span = { GridItemSpan(maxLineSpan) }) {
          OutlinedTextField(
            value = searchQuery,
            onValueChange = { viewModel.setSearchQuery(it) },
            placeholder = {
              Text("ابحث عن خلاط، محبس، طقم إكسسوار، ألوان...", color = WhiteMuted, fontSize = 13.sp)
            },
            leadingIcon = {
              Icon(Icons.Default.Search, contentDescription = "بحث", tint = GoldPrimary)
            },
            trailingIcon = {
              if (searchQuery.isNotBlank()) {
                IconButton(onClick = { viewModel.setSearchQuery("") }) {
                  Icon(Icons.Default.Clear, contentDescription = "مسح", tint = WhiteMuted)
                }
              }
            },
            singleLine = true,
            modifier = Modifier
              .fillMaxWidth()
              .testTag("search_field"),
            shape = RoundedCornerShape(12.dp),
            colors = OutlinedTextFieldDefaults.colors(
              focusedBorderColor = GoldPrimary,
              unfocusedBorderColor = GoldBorder,
              focusedTextColor = WhitePrimary,
              unfocusedTextColor = WhitePrimary,
              focusedContainerColor = BlackSurfaceCard,
              unfocusedContainerColor = BlackSurfaceCard
            )
          )
        }

        // Category Filter Chips (Full Width)
        item(span = { GridItemSpan(maxLineSpan) }) {
          Column(modifier = Modifier.fillMaxWidth()) {
            Text(
              text = "الأقسام والتصنيفات:",
              color = GoldLight,
              fontSize = 13.sp,
              fontWeight = FontWeight.Bold,
              modifier = Modifier.padding(bottom = 8.dp)
            )

            LazyRow(
              horizontalArrangement = Arrangement.spacedBy(8.dp),
              modifier = Modifier.fillMaxWidth()
            ) {
              items(SanitaryCategory.list) { category ->
                CategoryFilterPill(
                  title = category,
                  isSelected = selectedCategory == category,
                  onClick = { viewModel.selectCategory(category) }
                )
              }
            }
          }
        }

        // Section Title & Result Count (Full Width)
        item(span = { GridItemSpan(maxLineSpan) }) {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .padding(top = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
          ) {
            Text(
              text = if (selectedCategory == SanitaryCategory.ALL) "جميع المنتجات" else "قسم $selectedCategory",
              color = WhitePrimary,
              fontSize = 15.sp,
              fontWeight = FontWeight.Bold
            )
            Text(
              text = "${products.size} صنف متوفر",
              color = WhiteMuted,
              fontSize = 12.sp
            )
          }
        }

        // Empty state if no products found
        if (products.isEmpty()) {
          item(span = { GridItemSpan(maxLineSpan) }) {
            Column(
              modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 40.dp),
              horizontalAlignment = Alignment.CenterHorizontally
            ) {
              Icon(
                imageVector = Icons.Default.Search,
                contentDescription = null,
                tint = GoldBorder,
                modifier = Modifier.size(56.dp)
              )
              Spacer(modifier = Modifier.height(12.dp))
              Text(
                text = "لم يتم العثور على منتجات مطابقة",
                color = WhitePrimary,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold
              )
              Text(
                text = "جرب البحث بكلمات أخرى أو اختر قسم آخر",
                color = WhiteMuted,
                fontSize = 12.sp
              )
            }
          }
        } else {
          // Product Cards Grid
          items(products, key = { it.id }) { product ->
            val cartItem = cartItems.find { it.product.id == product.id }
            val quantity = cartItem?.quantity ?: 0

            ProductCard(
              product = product,
              cartQuantity = quantity,
              isAdmin = isAdminLoggedIn,
              onProductClick = { viewModel.openProductDetail(product) },
              onAddToCart = { viewModel.addToCart(product) },
              onIncreaseQuantity = { viewModel.updateCartQuantity(product.id, 1) },
              onDecreaseQuantity = { viewModel.updateCartQuantity(product.id, -1) },
              onEditProduct = { viewModel.openEditProduct(it) },
              onQuickPrice = { viewModel.openQuickPrice(it) },
              onQuickImage = { viewModel.openQuickImage(it) },
              onQuickStock = { viewModel.openQuickStock(it) },
              onDeleteProduct = { viewModel.openDeleteConfirm(it) }
            )
          }
        }
      }
    }

    // Product Detail Dialog
    selectedProductForDetail?.let { product ->
      val inCartQty = cartItems.find { it.product.id == product.id }?.quantity ?: 0
      ProductDetailDialog(
        product = product,
        cartQuantity = inCartQty,
        isAdmin = isAdminLoggedIn,
        onDismiss = { viewModel.closeProductDetail() },
        onAddToCart = { viewModel.addToCart(product) },
        onEditProduct = { viewModel.openEditProduct(it) },
        onDeleteProduct = { viewModel.openDeleteConfirm(it) }
      )
    }

    // Cart Dialog
    if (showCart) {
      CartDialog(
        cartItems = cartItems,
        totalAmount = cartTotal,
        onDismiss = { viewModel.toggleCart(false) },
        onUpdateQuantity = { id, delta -> viewModel.updateCartQuantity(id, delta) },
        onRemoveItem = { id -> viewModel.removeFromCart(id) },
        onClearCart = { viewModel.clearCart() },
        onProceedToCheckout = { viewModel.toggleOrderConfirmation(true) }
      )
    }

    // Order Confirmation Dialog (Before WhatsApp Launch)
    if (showOrderConfirmation) {
      OrderConfirmationDialog(
        savedCustomer = currentCustomer,
        totalAmount = cartTotal,
        itemCount = cartCount,
        onDismiss = { viewModel.toggleOrderConfirmation(false) },
        onConfirmOrder = { name, phone, address, notes ->
          viewModel.submitOrderAndSendWhatsApp(
            context = context,
            customerName = name,
            customerPhone = phone,
            customerAddress = address,
            notes = notes
          )
        }
      )
    }

    // Customer Login Dialog
    if (showLogin) {
      LoginDialog(
        currentCustomer = currentCustomer,
        
        onDismiss = { viewModel.toggleLogin(false) },
        onSaveCustomer = { name, phone, address ->
          viewModel.saveCustomerProfile(name, phone, address)
        },
        onLogout = { viewModel.logoutCustomer() },
        onLookupCustomerByPhone = { phone, onResult ->
          viewModel.lookupCustomerByPhone(phone, onResult)
        }
      )
    }

    // Admin Panel Dialog
    val isFirebaseConnected by viewModel.isFirebaseConnected.collectAsState()
    val isSyncing by viewModel.isSyncing.collectAsState()

    if (showAdmin) {
      AdminPanelDialog(
        isAdminLoggedIn = isAdminLoggedIn,
        isAdmin = true,
        products = allProducts,
        adminWhatsAppNumber = adminWhatsAppNumber,
        onDismiss = { viewModel.toggleAdmin(false) },
        onVerifyPin = { pin -> viewModel.checkAdminPin(pin) },
        onLogoutAdmin = { viewModel.logoutAdmin() },
        onOpenAddProduct = { viewModel.openAddProduct() },
        onOpenEditProduct = { product -> viewModel.openEditProduct(product) },
        onDeleteProduct = { id -> viewModel.deleteProduct(id) },
        onUpdateAdminWhatsApp = { number -> viewModel.updateAdminWhatsAppNumber(number) },
        isFirebaseConnected = isFirebaseConnected,
        isSyncing = isSyncing,
        onSyncFirestore = { viewModel.syncCatalogToFirestore() },
        onConfigureFirebase = { proj, key, app, bucket ->
          viewModel.configureFirebase(proj, key, app, bucket)
        },
        biometricNotice = biometricNotice,
        onRetryBiometric = { triggerBiometricAuth() },
        onUpdateAdminPassword = { newPass -> viewModel.updateAdminPassword(newPass) }
      )
    }

    // Add / Edit Product Dialog (Admin)
    if (showAddEditProduct) {
      AddEditProductDialog(
        productToEdit = productBeingEdited,
        isLoading = isLoading,
        onDismiss = { viewModel.closeAddEditProduct() },
        onSaveProduct = { name, price, category, description, imageUri, customImageUrl, inStock, stockQuantity ->
          viewModel.saveProduct(name, price, category, description, imageUri, customImageUrl, inStock, stockQuantity)
        }
      )
    }

    // Quick Price Adjustment Dialog (Admin)
    productForQuickPrice?.let { prod ->
      QuickPriceDialog(
        product = prod,
        onDismiss = { viewModel.closeQuickPrice() },
        onConfirmPrice = { newPrice -> viewModel.updateProductPrice(prod.id, newPrice) }
      )
    }

    // Quick Image Replacement Dialog (Admin)
    productForQuickImage?.let { prod ->
      QuickImageDialog(
        product = prod,
        onDismiss = { viewModel.closeQuickImage() },
        onConfirmImage = { uri, customUrl -> viewModel.updateProductImage(prod.id, uri, customUrl) }
      )
    }

    // Quick Stock & Inventory Dialog (Admin)
    productForQuickStock?.let { prod ->
      QuickStockDialog(
        product = prod,
        onDismiss = { viewModel.closeQuickStock() },
        onConfirmStock = { inStock, qty -> viewModel.updateProductStock(prod.id, inStock, qty) }
      )
    }

    // Product Deletion Confirmation Dialog (Admin)
    productForDeleteConfirm?.let { prod ->
      DeleteConfirmDialog(
        product = prod,
        onDismiss = { viewModel.closeDeleteConfirm() },
        onConfirmDelete = { viewModel.deleteProduct(prod.id) }
      )
    }
  }
}
