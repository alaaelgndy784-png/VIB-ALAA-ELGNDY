package com.example.data

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import com.example.model.Customer
import com.example.model.Order
import com.example.model.Product
import com.example.model.getCategoryDefaultDrawable
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.storage.FirebaseStorage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class FirebaseRepository(val context: Context) {

  companion object {
    // Default VIB Firebase project. Keeping these defaults in the app means a
    // newly installed customer copy connects to the same catalogue immediately,
    // without requiring the admin-only manual configuration screen.
    private const val DEFAULT_FIREBASE_PROJECT_ID = "vib-alaaelgndy"
    private const val DEFAULT_FIREBASE_API_KEY = "AIzaSyASUi-6xrJDrd8NWunLvEWvD3uR08LOuLs"
    private const val DEFAULT_FIREBASE_APP_ID = "1:984952125141:android:9f0c3e79cdebbf0b6f945c"
    private const val DEFAULT_FIREBASE_STORAGE_BUCKET = "vib-alaaelgndy.firebasestorage.app"
    private const val DEFAULT_ADMIN_WHATSAPP = "201013631323"
  }

  private val TAG = "FirebaseRepository"
  private val prefs: SharedPreferences = context.getSharedPreferences("vib_alaa_prefs", Context.MODE_PRIVATE)

  private val _products = MutableStateFlow<List<Product>>(emptyList())
  val products: StateFlow<List<Product>> = _products.asStateFlow()

  private val _currentCustomer = MutableStateFlow<Customer?>(null)
  val currentCustomer: StateFlow<Customer?> = _currentCustomer.asStateFlow()

  private val _adminPhone = MutableStateFlow(DEFAULT_ADMIN_WHATSAPP)
  val adminPhone: StateFlow<String> = _adminPhone.asStateFlow()

  private val _isFirebaseConnected = MutableStateFlow(false)
  val isFirebaseConnected: StateFlow<Boolean> = _isFirebaseConnected.asStateFlow()

  private val _isSyncing = MutableStateFlow(false)
  val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

  private var firestoreListener: ListenerRegistration? = null
  private var settingsListener: ListenerRegistration? = null
  private val scope = CoroutineScope(Dispatchers.IO)

  init {
    // Immediately set default in memory so UI renders first frame with zero lag
    _products.value = InitialProducts.defaultCatalog
    scope.launch {
      try {
        loadSavedCustomer()
        loadSavedAdminPhone()
        loadCachedProducts()
        ensureFirebaseApp()
        initFirebaseSync()
      } catch (e: Exception) {
        Log.e(TAG, "Error in background repository initialization: ${e.message}")
      }
    }
  }

  private suspend fun ensureFirebaseApp(): Boolean = withContext(Dispatchers.IO) {
    try {
      if (isFirebaseConfigured()) {
        _isFirebaseConnected.value = true
        return@withContext true
      }

      // Prefer settings entered by the manager, otherwise use the VIB project
      // bundled with the app so every customer device receives live updates.
      val projectId = prefs.getString("firebase_project_id", null)
        ?.takeIf { it.isNotBlank() }?.trim() ?: DEFAULT_FIREBASE_PROJECT_ID
      val apiKey = prefs.getString("firebase_api_key", null)
        ?.takeIf { it.isNotBlank() }?.trim() ?: DEFAULT_FIREBASE_API_KEY
      val appId = prefs.getString("firebase_app_id", null)
        ?.takeIf { it.isNotBlank() }?.trim() ?: DEFAULT_FIREBASE_APP_ID
      val bucket = prefs.getString("firebase_storage_bucket", null)
        ?.takeIf { it.isNotBlank() }?.trim() ?: DEFAULT_FIREBASE_STORAGE_BUCKET

      val options = FirebaseOptions.Builder()
        .setProjectId(projectId)
        .setApiKey(apiKey)
        .setApplicationId(appId)
        .setStorageBucket(bucket)
        .build()

      if (FirebaseApp.getApps(context).isEmpty()) {
        FirebaseApp.initializeApp(context, options)
      }

      val isOk = isFirebaseConfigured()
      _isFirebaseConnected.value = isOk
      if (isOk) {
        Log.i(TAG, "Firebase initialized for project: $projectId")
      }
      isOk
    } catch (e: Exception) {
      Log.w(TAG, "FirebaseApp setup error: ${e.message}")
      _isFirebaseConnected.value = false
      false
    }
  }

  fun configureFirebaseManually(
    projectId: String,
    apiKey: String,
    appId: String,
    storageBucket: String
  ): Boolean {
    return try {
      prefs.edit()
        .putString("firebase_project_id", projectId.trim())
        .putString("firebase_api_key", apiKey.trim())
        .putString("firebase_app_id", appId.trim())
        .putString("firebase_storage_bucket", storageBucket.trim())
        .apply()

      val optionsBuilder = FirebaseOptions.Builder()
        .setProjectId(projectId.trim())
        .setApiKey(apiKey.trim())
        .setApplicationId(appId.trim())

      if (storageBucket.isNotBlank()) {
        optionsBuilder.setStorageBucket(storageBucket.trim())
      }

      if (FirebaseApp.getApps(context).isEmpty()) {
        FirebaseApp.initializeApp(context, optionsBuilder.build())
      }
      _isFirebaseConnected.value = isFirebaseConfigured()
      initFirebaseSync()
      true
    } catch (e: Exception) {
      Log.e(TAG, "Failed manual Firebase configuration: ${e.message}")
      false
    }
  }

  fun isFirebaseConfigured(): Boolean {
    return try {
      val apps = FirebaseApp.getApps(context)
      if (apps.isEmpty()) return false
      val app = FirebaseApp.getInstance()
      val projId = app.options.projectId
      val apiKey = app.options.apiKey
      !projId.isNullOrBlank() && projId != "[DEFAULT]" && projId != "null" &&
        !apiKey.isNullOrBlank() && apiKey != "null"
    } catch (e: Exception) {
      false
    }
  }

  private suspend fun loadSavedCustomer() = withContext(Dispatchers.IO) {
    val id = prefs.getString("customer_id", null)
    val phone = prefs.getString("customer_phone", null)
    val name = prefs.getString("customer_name", null)
    val address = prefs.getString("customer_address", "") ?: ""
    val notes = prefs.getString("customer_notes", "") ?: ""

    if (!id.isNullOrBlank() && !phone.isNullOrBlank()) {
      _currentCustomer.value = Customer(
        id = id,
        name = name ?: "",
        phone = phone,
        address = address,
        notes = notes
      )
    }
  }

  private suspend fun loadSavedAdminPhone() = withContext(Dispatchers.IO) {
    val phone = prefs.getString("admin_whatsapp_number", DEFAULT_ADMIN_WHATSAPP) ?: DEFAULT_ADMIN_WHATSAPP
    _adminPhone.value = phone
  }

  fun setAdminWhatsAppNumber(phone: String) {
    val normalized = normalizeEgyptianWhatsApp(phone)
    _adminPhone.value = normalized
    prefs.edit().putString("admin_whatsapp_number", normalized).apply()
    scope.launch {
      if (ensureFirebaseApp()) {
        try {
          FirebaseFirestore.getInstance()
            .collection("settings")
            .document("app")
            .set(mapOf("adminWhatsApp" to normalized), com.google.firebase.firestore.SetOptions.merge())
            .await()
        } catch (e: Exception) {
          Log.w(TAG, "Could not sync admin WhatsApp number: ${e.message}")
        }
      }
    }
  }

  private suspend fun loadCachedProducts() = withContext(Dispatchers.IO) {
    val jsonString = prefs.getString("cached_products_json", null)
    if (!jsonString.isNullOrBlank()) {
      try {
        val array = JSONArray(jsonString)
        val list = mutableListOf<Product>()
        for (i in 0 until array.length()) {
          val obj = array.getJSONObject(i)
          val id = obj.optString("id", "")
          val name = obj.optString("name", "")
          val price = obj.optDouble("price", 0.0)
          val category = obj.optString("category", "")
          val description = obj.optString("description", "")
          val imageUrl = obj.optString("imageUrl", "")
          val inStock = obj.optBoolean("inStock", true)
          // Resolve drawable safely from current R constants to prevent obsolete/invalid AAPT IDs across builds
          val resolvedDrawable = InitialProducts.defaultCatalog.find { it.id == id }?.drawableRes
            ?: getCategoryDefaultDrawable(category)

          list.add(
            Product(
              id = id,
              name = name,
              price = price,
              category = category,
              description = description,
              imageUrl = imageUrl,
              drawableRes = resolvedDrawable,
              inStock = inStock
            )
          )
        }
        if (list.isNotEmpty()) {
          _products.value = list
          return@withContext
        }
      } catch (e: Exception) {
        Log.e(TAG, "Error parsing cached products: ${e.message}")
      }
    }
  }

  private suspend fun saveProductsLocally(list: List<Product>) = withContext(Dispatchers.IO) {
    try {
      val array = JSONArray()
      for (p in list) {
        val obj = JSONObject()
        obj.put("id", p.id)
        obj.put("name", p.name)
        obj.put("price", p.price)
        obj.put("category", p.category)
        obj.put("description", p.description)
        obj.put("imageUrl", p.imageUrl)
        obj.put("inStock", p.inStock)
        // Intentionally do not write raw int drawableRes to avoid outdated AAPT IDs across builds
        array.put(obj)
      }
      prefs.edit().putString("cached_products_json", array.toString()).apply()
    } catch (e: Exception) {
      Log.e(TAG, "Error caching products locally: ${e.message}")
    }
  }

  fun initFirebaseSync() {
    scope.launch {
      if (!isFirebaseConfigured()) {
        Log.i(TAG, "Firebase not configured; continuing with local catalog.")
        _isFirebaseConnected.value = false
        return@launch
      }

      _isFirebaseConnected.value = true

      try {
        val db = FirebaseFirestore.getInstance()
        val collection = db.collection("products")

        withContext(Dispatchers.Main) {
          firestoreListener?.remove()
          firestoreListener = collection.addSnapshotListener { snapshot, error ->
            if (error != null) {
              Log.w(TAG, "Firestore listen error: ${error.message}")
              return@addSnapshotListener
            }

            if (snapshot != null && !snapshot.isEmpty) {
              scope.launch {
                val list = mutableListOf<Product>()
                for (doc in snapshot.documents) {
                  val data = doc.data ?: continue
                  val baseProduct = Product.fromMap(doc.id, data)
                  val resolvedDrawable = InitialProducts.defaultCatalog.find { it.id == baseProduct.id }?.drawableRes
                    ?: getCategoryDefaultDrawable(baseProduct.category)
                  list.add(baseProduct.copy(drawableRes = resolvedDrawable))
                }
                if (list.isNotEmpty()) {
                  _products.value = list
                  saveProductsLocally(list)
                }
              }
            }
          }

          settingsListener?.remove()
          settingsListener = db.collection("settings").document("app")
            .addSnapshotListener { snapshot, error ->
              if (error != null) {
                Log.w(TAG, "Settings listen error: ${error.message}")
                return@addSnapshotListener
              }
              val cloudPhone = snapshot?.getString("adminWhatsApp")
              val normalized = normalizeEgyptianWhatsApp(cloudPhone ?: DEFAULT_ADMIN_WHATSAPP)
              _adminPhone.value = normalized
              prefs.edit().putString("admin_whatsapp_number", normalized).apply()
            }
        }
      } catch (e: Exception) {
        Log.w(TAG, "Failed to start Firestore listener: ${e.message}")
      }
    }
  }

  suspend fun syncAllToFirestore(): Boolean = withContext(Dispatchers.IO) {
    if (!isFirebaseConfigured()) return@withContext false
    return@withContext try {
      _isSyncing.value = true
      withTimeoutOrNull(10000L) {
        val db = FirebaseFirestore.getInstance()
        val batch = db.batch()
        val currentList = _products.value.ifEmpty { InitialProducts.defaultCatalog }

        for (product in currentList) {
          val docRef = db.collection("products").document(product.id)
          batch.set(docRef, product.toMap())
        }
        batch.commit().await()
        Log.d(TAG, "Synced all ${currentList.size} products to Firestore successfully")
        true
      } ?: run {
        Log.w(TAG, "Sync to Firestore timed out")
        false
      }
    } catch (e: Exception) {
      Log.e(TAG, "Error syncing to Firestore: ${e.message}")
      false
    } finally {
      _isSyncing.value = false
    }
  }

  private suspend fun seedFirestoreWithDefaultCatalog() {
    syncAllToFirestore()
  }

  private suspend fun copyUriToInternalStorage(uri: Uri): Uri = withContext(Dispatchers.IO) {
    try {
      val imagesDir = File(context.filesDir, "product_images").apply { mkdirs() }
      val targetFile = File(imagesDir, "prod_${UUID.randomUUID()}.jpg")

      context.contentResolver.openInputStream(uri)?.use { input ->
        FileOutputStream(targetFile).use { output ->
          input.copyTo(output)
        }
      }
      Uri.fromFile(targetFile)
    } catch (e: Exception) {
      Log.w(TAG, "Failed to copy image to internal storage: ${e.message}")
      uri
    }
  }

  suspend fun uploadImageToStorage(uri: Uri): String? = withContext(Dispatchers.IO) {
    // 1. First persist locally so it's always available on this device
    val internalUri = copyUriToInternalStorage(uri)

    if (!isFirebaseConfigured()) {
      return@withContext internalUri.toString()
    }

    // 2. Upload to Firebase Storage so ALL customers see the same image
    return@withContext try {
      withTimeoutOrNull(10000L) {
        val storage = FirebaseStorage.getInstance()
        val filename = "prod_${UUID.randomUUID()}.jpg"
        val storageRef = storage.reference.child("product_images/$filename")

        storageRef.putFile(internalUri).await()
        val downloadUrl = storageRef.downloadUrl.await().toString()
        Log.d(TAG, "Uploaded image to Firebase Storage: $downloadUrl")
        downloadUrl
      } ?: run {
        Log.w(TAG, "Storage upload timed out, falling back to local URI")
        internalUri.toString()
      }
    } catch (e: Exception) {
      Log.e(TAG, "Firebase Storage upload failed, falling back to local URI: ${e.message}")
      internalUri.toString()
    }
  }

  suspend fun deleteImageFromStorage(imageUrl: String?) = withContext(Dispatchers.IO) {
    if (imageUrl.isNullOrBlank()) return@withContext
    try {
      if (isFirebaseConfigured() && (imageUrl.contains("firebasestorage.googleapis.com") || imageUrl.contains("storage.googleapis.com"))) {
        withTimeoutOrNull(5000L) {
          val storage = FirebaseStorage.getInstance()
          val ref = storage.getReferenceFromUrl(imageUrl)
          ref.delete().await()
          Log.d(TAG, "Deleted image from Firebase Storage successfully: $imageUrl")
        }
      } else if (imageUrl.startsWith("file://")) {
        val path = Uri.parse(imageUrl).path
        if (path != null) {
          val file = File(path)
          if (file.exists()) {
            file.delete()
            Log.d(TAG, "Deleted local image file: $path")
          }
        }
      }
    } catch (e: Exception) {
      Log.w(TAG, "Notice: could not delete image from storage (safely ignored): ${e.message}")
    }
  }

  suspend fun addProduct(
    name: String,
    price: Double,
    category: String,
    description: String,
    imageUri: Uri?,
    customImageUrl: String? = null,
    inStock: Boolean = true,
    stockQuantity: Int = 10
  ): Boolean = withContext(Dispatchers.IO) {
    val id = "prod_${System.currentTimeMillis()}"
    var finalImageUrl = if (!customImageUrl.isNullOrBlank()) customImageUrl.trim() else ""

    if (imageUri != null) {
      finalImageUrl = uploadImageToStorage(imageUri) ?: imageUri.toString()
    }

    val newProduct = Product(
      id = id,
      name = name,
      price = price,
      category = category,
      description = description,
      imageUrl = finalImageUrl,
      inStock = inStock,
      stockQuantity = stockQuantity,
      createdAt = System.currentTimeMillis()
    )

    // Update local immediately
    val updated = listOf(newProduct) + _products.value
    _products.value = updated
    saveProductsLocally(updated)

    // Sync to Firestore directly
    if (isFirebaseConfigured()) {
      try {
        withTimeoutOrNull(6000L) {
          val db = FirebaseFirestore.getInstance()
          db.collection("products").document(id).set(newProduct.toMap()).await()
          Log.d(TAG, "Added product $id to Firestore")
        }
      } catch (e: Exception) {
        Log.w(TAG, "Could not sync new product to Firestore: ${e.message}")
      }
    }
    return@withContext true
  }

  suspend fun updateProduct(
    product: Product,
    newImageUri: Uri?,
    customImageUrl: String? = null
  ): Boolean = withContext(Dispatchers.IO) {
    val oldProduct = _products.value.find { it.id == product.id }
    val oldImageUrl = oldProduct?.imageUrl ?: product.imageUrl

    var finalImageUrl = if (!customImageUrl.isNullOrBlank()) customImageUrl.trim() else product.imageUrl
    var imageWasChanged = false

    if (newImageUri != null) {
      val uploaded = uploadImageToStorage(newImageUri)
      if (uploaded != null) {
        finalImageUrl = uploaded
        imageWasChanged = true
      }
    } else if (!customImageUrl.isNullOrBlank() && customImageUrl != oldImageUrl) {
      imageWasChanged = true
    }

    val updatedProduct = product.copy(imageUrl = finalImageUrl)

    val updated = _products.value.map {
      if (it.id == product.id) updatedProduct else it
    }
    _products.value = updated
    saveProductsLocally(updated)

    // Direct Firestore update
    if (isFirebaseConfigured()) {
      try {
        withTimeoutOrNull(6000L) {
          val db = FirebaseFirestore.getInstance()
          db.collection("products").document(product.id).set(updatedProduct.toMap()).await()
          Log.d(TAG, "Updated product ${product.id} in Firestore")
        }
      } catch (e: Exception) {
        Log.w(TAG, "Could not update product in Firestore: ${e.message}")
      }
    }

    // Safely delete old image from Firebase Storage if replaced
    if (imageWasChanged && oldImageUrl.isNotBlank() && oldImageUrl != finalImageUrl) {
      deleteImageFromStorage(oldImageUrl)
    }

    return@withContext true
  }

  suspend fun updateProductPrice(productId: String, newPrice: Double): Boolean {
    val product = _products.value.find { it.id == productId } ?: return false
    return updateProduct(product.copy(price = newPrice), null)
  }

  suspend fun updateProductStock(productId: String, inStock: Boolean, stockQuantity: Int): Boolean {
    val product = _products.value.find { it.id == productId } ?: return false
    return updateProduct(product.copy(inStock = inStock, stockQuantity = stockQuantity), null)
  }

  suspend fun updateProductImage(productId: String, newImageUri: Uri?, customImageUrl: String?): Boolean {
    val product = _products.value.find { it.id == productId } ?: return false
    return updateProduct(product, newImageUri, customImageUrl)
  }

  suspend fun deleteProduct(productId: String): Boolean = withContext(Dispatchers.IO) {
    val productToDelete = _products.value.find { it.id == productId }
    val oldImageUrl = productToDelete?.imageUrl

    val updated = _products.value.filter { it.id != productId }
    _products.value = updated
    saveProductsLocally(updated)

    // Direct Firestore deletion
    if (isFirebaseConfigured()) {
      try {
        withTimeoutOrNull(6000L) {
          val db = FirebaseFirestore.getInstance()
          db.collection("products").document(productId).delete().await()
          Log.d(TAG, "Deleted product $productId from Firestore")
        }
      } catch (e: Exception) {
        Log.w(TAG, "Could not delete product from Firestore: ${e.message}")
      }
    }

    // Safely delete old image from Firebase Storage
    if (!oldImageUrl.isNullOrBlank()) {
      deleteImageFromStorage(oldImageUrl)
    }

    return@withContext true
  }

  suspend fun fetchCustomerByPhone(phone: String): Customer? = withContext(Dispatchers.IO) {
    val cleanPhone = phone.replace(Regex("[^0-9]"), "")
    if (isFirebaseConfigured()) {
      try {
        return@withContext withTimeoutOrNull(6000L) {
          val db = FirebaseFirestore.getInstance()
          // Try direct document by ID
          val doc = db.collection("customers").document("cust_$cleanPhone").get().await()
          if (doc.exists() && doc.data != null) {
            return@withTimeoutOrNull Customer.fromMap(doc.id, doc.data!!)
          }

          // Try query by phone
          val querySnap = db.collection("customers").whereEqualTo("phone", phone).limit(1).get().await()
          if (!querySnap.isEmpty) {
            val firstDoc = querySnap.documents.first()
            return@withTimeoutOrNull Customer.fromMap(firstDoc.id, firstDoc.data ?: emptyMap())
          }
          null
        }
      } catch (e: Exception) {
        Log.w(TAG, "Error fetching customer from Firestore: ${e.message}")
      }
    }
    return@withContext null
  }

  suspend fun saveCustomer(name: String, phone: String, address: String, notes: String): Customer = withContext(Dispatchers.IO) {
    val cleanPhone = phone.replace(Regex("[^0-9]"), "")
    val id = _currentCustomer.value?.id ?: "cust_$cleanPhone"
    val customer = Customer(
      id = id,
      name = name,
      phone = phone,
      address = address,
      notes = notes
    )
    _currentCustomer.value = customer

    prefs.edit()
      .putString("customer_id", customer.id)
      .putString("customer_phone", customer.phone)
      .putString("customer_name", customer.name)
      .putString("customer_address", customer.address)
      .putString("customer_notes", customer.notes)
      .apply()

    if (isFirebaseConfigured()) {
      try {
        withTimeoutOrNull(6000L) {
          val db = FirebaseFirestore.getInstance()
          db.collection("customers").document(customer.id).set(customer.toMap()).await()
        }
      } catch (e: Exception) {
        Log.w(TAG, "Failed to save customer to Firestore: ${e.message}")
      }
    }

    return@withContext customer
  }

  fun logoutCustomer() {
    _currentCustomer.value = null
    prefs.edit()
      .remove("customer_id")
      .remove("customer_phone")
      .remove("customer_name")
      .remove("customer_address")
      .remove("customer_notes")
      .apply()
  }

  suspend fun recordOrderInFirestore(order: Order): Boolean = withContext(Dispatchers.IO) {
    if (!isFirebaseConfigured()) return@withContext true
    return@withContext try {
      withTimeoutOrNull(6000L) {
        val db = FirebaseFirestore.getInstance()
        val orderMap = mapOf(
          "id" to order.id,
          "customer" to order.customer.toMap(),
          "totalAmount" to order.totalAmount,
          "itemCount" to order.items.sumOf { it.quantity },
          "createdAt" to order.createdAt,
          "status" to order.status,
          "items" to order.items.map {
            mapOf(
              "productId" to it.product.id,
              "productName" to it.product.name,
              "quantity" to it.quantity,
              "price" to it.product.price,
              "subtotal" to it.subtotal
            )
          }
        )
        db.collection("orders").document(order.id).set(orderMap).await()
        true
      } ?: false
    } catch (e: Exception) {
      Log.w(TAG, "Failed to record order in Firestore: ${e.message}")
      false
    }
  }

  private fun normalizeEgyptianWhatsApp(phone: String): String {
    var digits = phone.filter(Char::isDigit)
    if (digits.startsWith("00")) digits = digits.drop(2)
    if (digits.startsWith("0")) digits = "20${digits.drop(1)}"
    if (!digits.startsWith("20") && digits.length == 10) digits = "20$digits"
    return digits.ifBlank { DEFAULT_ADMIN_WHATSAPP }
  }
}
