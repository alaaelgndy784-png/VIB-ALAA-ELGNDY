package com.example.viewmodel

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.data.FirebaseRepository
import com.example.model.CartItem
import com.example.model.Customer
import com.example.model.Order
import com.example.model.Product
import com.example.model.SanitaryCategory
import com.example.security.AdminSecurityManager
import com.example.util.WhatsAppHelper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class VibViewModel(private val repository: FirebaseRepository) : ViewModel() {

  val allProducts: StateFlow<List<Product>> = repository.products
  val currentCustomer: StateFlow<Customer?> = repository.currentCustomer
  val adminWhatsAppNumber: StateFlow<String> = repository.adminPhone
  val isFirebaseConnected: StateFlow<Boolean> = repository.isFirebaseConnected
  val isSyncing: StateFlow<Boolean> = repository.isSyncing

  private val _selectedCategory = MutableStateFlow(SanitaryCategory.ALL)
  val selectedCategory: StateFlow<String> = _selectedCategory.asStateFlow()

  private val _searchQuery = MutableStateFlow("")
  val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

  val filteredProducts: StateFlow<List<Product>> = combine(
    allProducts,
    _selectedCategory,
    _searchQuery
  ) { products, category, query ->
    products.filter { product ->
      val matchesCategory = (category == SanitaryCategory.ALL || product.category == category)
      val matchesQuery = if (query.isBlank()) {
        true
      } else {
        product.name.contains(query, ignoreCase = true) ||
          product.description.contains(query, ignoreCase = true) ||
          product.category.contains(query, ignoreCase = true)
      }
      matchesCategory && matchesQuery
    }
  }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

  // Cart State
  private val _cartItems = MutableStateFlow<List<CartItem>>(emptyList())
  val cartItems: StateFlow<List<CartItem>> = _cartItems.asStateFlow()

  val cartTotal: StateFlow<Double> = _cartItems.map { items ->
    items.sumOf { it.subtotal }
  }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0.0)

  val cartCount: StateFlow<Int> = _cartItems.map { items ->
    items.sumOf { it.quantity }
  }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0)

  // Dialog & Navigation states
  private val _isAdminLoggedIn = MutableStateFlow(false)
  val isAdminLoggedIn: StateFlow<Boolean> = _isAdminLoggedIn.asStateFlow()

  private val _selectedProductForDetail = MutableStateFlow<Product?>(null)
  val selectedProductForDetail: StateFlow<Product?> = _selectedProductForDetail.asStateFlow()

  private val _productBeingEdited = MutableStateFlow<Product?>(null)
  val productBeingEdited: StateFlow<Product?> = _productBeingEdited.asStateFlow()

  private val _showCart = MutableStateFlow(false)
  val showCart: StateFlow<Boolean> = _showCart.asStateFlow()

  private val _showAdmin = MutableStateFlow(false)
  val showAdmin: StateFlow<Boolean> = _showAdmin.asStateFlow()

  private val _biometricNotice = MutableStateFlow<String?>(null)
  val biometricNotice: StateFlow<String?> = _biometricNotice.asStateFlow()

  private val _showLogin = MutableStateFlow(false)
  val showLogin: StateFlow<Boolean> = _showLogin.asStateFlow()

  private val _showAddEditProduct = MutableStateFlow(false)
  val showAddEditProduct: StateFlow<Boolean> = _showAddEditProduct.asStateFlow()

  private val _showOrderConfirmation = MutableStateFlow(false)
  val showOrderConfirmation: StateFlow<Boolean> = _showOrderConfirmation.asStateFlow()

  // Quick Admin Dialog States for each product
  private val _productForQuickPrice = MutableStateFlow<Product?>(null)
  val productForQuickPrice: StateFlow<Product?> = _productForQuickPrice.asStateFlow()

  private val _productForQuickImage = MutableStateFlow<Product?>(null)
  val productForQuickImage: StateFlow<Product?> = _productForQuickImage.asStateFlow()

  private val _productForQuickStock = MutableStateFlow<Product?>(null)
  val productForQuickStock: StateFlow<Product?> = _productForQuickStock.asStateFlow()

  private val _productForDeleteConfirm = MutableStateFlow<Product?>(null)
  val productForDeleteConfirm: StateFlow<Product?> = _productForDeleteConfirm.asStateFlow()

  private val _isLoading = MutableStateFlow(false)
  val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

  private val _statusMessage = MutableStateFlow<String?>(null)
  val statusMessage: StateFlow<String?> = _statusMessage.asStateFlow()

  fun selectCategory(category: String) {
    _selectedCategory.value = category
  }

  fun setSearchQuery(query: String) {
    _searchQuery.value = query
  }

  fun addToCart(product: Product) {
    val current = _cartItems.value.toMutableList()
    val index = current.indexOfFirst { it.product.id == product.id }
    if (index >= 0) {
      val existing = current[index]
      current[index] = existing.copy(quantity = existing.quantity + 1)
    } else {
      current.add(CartItem(product = product, quantity = 1))
    }
    _cartItems.value = current
    _statusMessage.value = "تمت إضافة \"${product.name}\" إلى السلة"
  }

  fun updateCartQuantity(productId: String, delta: Int) {
    val current = _cartItems.value.toMutableList()
    val index = current.indexOfFirst { it.product.id == productId }
    if (index >= 0) {
      val newQty = current[index].quantity + delta
      if (newQty <= 0) {
        current.removeAt(index)
      } else {
        current[index] = current[index].copy(quantity = newQty)
      }
      _cartItems.value = current
    }
  }

  fun removeFromCart(productId: String) {
    _cartItems.value = _cartItems.value.filter { it.product.id != productId }
  }

  fun clearCart() {
    _cartItems.value = emptyList()
  }

  fun openProductDetail(product: Product) {
    _selectedProductForDetail.value = product
  }

  fun closeProductDetail() {
    _selectedProductForDetail.value = null
  }

  fun toggleCart(show: Boolean) {
    _showCart.value = show
  }

  fun toggleAdmin(show: Boolean) {
    _showAdmin.value = show
  }

  fun toggleLogin(show: Boolean) {
    _showLogin.value = show
  }

  fun toggleOrderConfirmation(show: Boolean) {
    _showOrderConfirmation.value = show
  }

  fun openAddProduct() {
    _productBeingEdited.value = null
    _showAddEditProduct.value = true
  }

  fun openEditProduct(product: Product) {
    _productBeingEdited.value = product
    _showAddEditProduct.value = true
  }

  fun closeAddEditProduct() {
    _productBeingEdited.value = null
    _showAddEditProduct.value = false
  }

  fun onBiometricAuthSuccess() {
    _isAdminLoggedIn.value = true
    _showAdmin.value = true
    _biometricNotice.value = null
    _statusMessage.value = "تم التحقق بالبصمة بنجاح - مرحباً بالمدير علاء الجندي"
  }

  fun openAdminLoginFallback(notice: String? = null) {
    _showAdmin.value = true
    _biometricNotice.value = notice
  }

  fun onBiometricAttemptFailed() {
    _statusMessage.value = "لم يتم التعرف على البصمة، يمكنك المحاولة مجدداً أو إدخال كلمة المرور"
  }

  fun checkAdminPassword(input: String): Boolean {
    val isValid = AdminSecurityManager.verifyAdminPassword(repository.context, input)
    if (isValid) {
      _isAdminLoggedIn.value = true
      _showAdmin.value = true
      _biometricNotice.value = null
      _statusMessage.value = "تم تسجيل دخول المدير بنجاح"
      return true
    }
    return false
  }

  fun checkAdminPin(pin: String): Boolean {
    // Verifies via salted SHA-256 hash comparison - no plaintext password stored
    return checkAdminPassword(pin)
  }

  fun updateAdminPassword(newPass: String): Boolean {
    if (newPass.length < 4) {
      _statusMessage.value = "كلمة المرور يجب أن لا تقل عن 4 أرقام أو حروف"
      return false
    }
    AdminSecurityManager.setCustomPassword(repository.context, newPass)
    _statusMessage.value = "تم تحديث وتشفير كلمة مرور المدير بنجاح"
    return true
  }

  fun logoutAdmin() {
    _isAdminLoggedIn.value = false
    _showAdmin.value = false
    _biometricNotice.value = null
    _statusMessage.value = "تم تسجيل خروج المدير والعودة لوضع العميل"
  }

  fun openQuickPrice(product: Product) {
    _productForQuickPrice.value = product
  }

  fun closeQuickPrice() {
    _productForQuickPrice.value = null
  }

  fun openQuickImage(product: Product) {
    _productForQuickImage.value = product
  }

  fun closeQuickImage() {
    _productForQuickImage.value = null
  }

  fun openQuickStock(product: Product) {
    _productForQuickStock.value = product
  }

  fun closeQuickStock() {
    _productForQuickStock.value = null
  }

  fun openDeleteConfirm(product: Product) {
    _productForDeleteConfirm.value = product
  }

  fun closeDeleteConfirm() {
    _productForDeleteConfirm.value = null
  }

  fun updateProductPrice(productId: String, newPrice: Double) {
    viewModelScope.launch {
      _isLoading.value = true
      repository.updateProductPrice(productId, newPrice)
      _isLoading.value = false
      _statusMessage.value = "تم تحديث السعر في Firebase بنجاح"
      closeQuickPrice()
    }
  }

  fun updateProductStock(productId: String, inStock: Boolean, stockQuantity: Int) {
    viewModelScope.launch {
      _isLoading.value = true
      repository.updateProductStock(productId, inStock, stockQuantity)
      _isLoading.value = false
      _statusMessage.value = "تم تحديث حالة المخزون في Firebase بنجاح"
      closeQuickStock()
    }
  }

  fun updateProductImage(productId: String, newImageUri: Uri?, customImageUrl: String?) {
    viewModelScope.launch {
      _isLoading.value = true
      repository.updateProductImage(productId, newImageUri, customImageUrl)
      _isLoading.value = false
      _statusMessage.value = "تم تغيير الصورة ورفعها لـ Firebase Storage بنجاح"
      closeQuickImage()
    }
  }

  fun saveProduct(
    name: String,
    price: Double,
    category: String,
    description: String,
    imageUri: Uri?,
    customImageUrl: String? = null,
    inStock: Boolean = true,
    stockQuantity: Int = 10
  ) {
    viewModelScope.launch {
      _isLoading.value = true
      val existing = _productBeingEdited.value
      if (existing != null) {
        val updated = existing.copy(
          name = name,
          price = price,
          category = category,
          description = description,
          inStock = inStock,
          stockQuantity = stockQuantity
        )
        repository.updateProduct(updated, imageUri, customImageUrl)
        _statusMessage.value = "تم حفظ التعديلات في Firebase ومزامنة الصور بنجاح"
      } else {
        repository.addProduct(
          name = name,
          price = price,
          category = category,
          description = description,
          imageUri = imageUri,
          customImageUrl = customImageUrl,
          inStock = inStock,
          stockQuantity = stockQuantity
        )
        _statusMessage.value = "تمت إضافة المنتج ونشره على السحابة بنجاح"
      }
      _isLoading.value = false
      closeAddEditProduct()
    }
  }

  fun deleteProduct(productId: String) {
    viewModelScope.launch {
      _isLoading.value = true
      repository.deleteProduct(productId)
      _isLoading.value = false
      closeDeleteConfirm()
      _statusMessage.value = "تم حذف المنتج والصورة من Firebase بنجاح"
    }
  }

  fun syncCatalogToFirestore() {
    viewModelScope.launch {
      _isLoading.value = true
      val success = repository.syncAllToFirestore()
      _isLoading.value = false
      if (success) {
        _statusMessage.value = "تمت مزامنة جميع المعروضات مع Firebase Firestore بنجاح"
      } else {
        _statusMessage.value = "جاري الحفظ المحلي. تأكد من إعدادات اتصال Firebase"
      }
    }
  }

  fun configureFirebase(projectId: String, apiKey: String, appId: String, storageBucket: String) {
    val ok = repository.configureFirebaseManually(projectId, apiKey, appId, storageBucket)
    if (ok) {
      _statusMessage.value = "تم حفظ إعدادات Firebase وتفعيل المزامنة السحابية بنجاح"
    } else {
      _statusMessage.value = "حدث خطأ أثناء تطبيق إعدادات Firebase"
    }
  }

  fun lookupCustomerByPhone(phone: String, onResult: (Customer?) -> Unit) {
    viewModelScope.launch {
      _isLoading.value = true
      val customer = repository.fetchCustomerByPhone(phone)
      _isLoading.value = false
      onResult(customer)
    }
  }

  fun saveCustomerProfile(name: String, phone: String, address: String, notes: String = "") {
    viewModelScope.launch {
      _isLoading.value = true
      repository.saveCustomer(name, phone, address, notes)
      _isLoading.value = false
      _showLogin.value = false
      _statusMessage.value = "مرحباً بك يا $name"
    }
  }

  fun logoutCustomer() {
    repository.logoutCustomer()
    _statusMessage.value = "تم تسجيل الخروج"
  }

  fun updateAdminWhatsAppNumber(number: String) {
    repository.setAdminWhatsAppNumber(number)
    _statusMessage.value = "تم تحديث رقم واتساب الإدارة"
  }

  fun submitOrderAndSendWhatsApp(
    context: Context,
    customerName: String,
    customerPhone: String,
    customerAddress: String,
    notes: String
  ) {
    viewModelScope.launch {
      if (_cartItems.value.isEmpty()) return@launch

      _isLoading.value = true
      val customer = repository.saveCustomer(customerName, customerPhone, customerAddress, notes)

      val order = Order(
        id = "ORD-${System.currentTimeMillis() % 1000000}",
        customer = customer,
        items = _cartItems.value,
        totalAmount = cartTotal.value,
        createdAt = System.currentTimeMillis(),
        status = "تم الإرسال عبر واتساب"
      )

      // Save to Firestore
      repository.recordOrderInFirestore(order)

      // Send via WhatsApp
      WhatsAppHelper.sendOrderViaWhatsApp(
        context = context,
        order = order,
        customer = customer,
        targetWhatsAppNumber = adminWhatsAppNumber.value
      )

      _isLoading.value = false
      _showOrderConfirmation.value = false
      _showCart.value = false
      clearCart()
      _statusMessage.value = "تم تجهيز الطلب وإرساله إلى واتساب بنجاح"
    }
  }

  fun clearStatusMessage() {
    _statusMessage.value = null
  }
}

class VibViewModelFactory(private val repository: FirebaseRepository) : ViewModelProvider.Factory {
  override fun <T : ViewModel> create(modelClass: Class<T>): T {
    if (modelClass.isAssignableFrom(VibViewModel::class.java)) {
      @Suppress("UNCHECKED_CAST")
      return VibViewModel(repository) as T
    }
    throw IllegalArgumentException("Unknown ViewModel class")
  }
}
