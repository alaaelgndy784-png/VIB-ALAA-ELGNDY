package com.example.model

import com.example.R

object SanitaryCategory {
  const val ALL = "الكل"
  const val BRASS = "النحاسات"
  const val FAUCETS = "الحنفيات"
  const val ACCESSORIES = "الإكسسوارات"
  const val COLORS = "الألوان"

  val list = listOf(ALL, BRASS, FAUCETS, ACCESSORIES, COLORS)
  val editList = listOf(BRASS, FAUCETS, ACCESSORIES, COLORS)
}

fun getCategoryDefaultDrawable(category: String): Int {
  return when (category) {
    SanitaryCategory.BRASS -> R.drawable.brass_fitting
    SanitaryCategory.FAUCETS -> R.drawable.faucet_gold
    SanitaryCategory.ACCESSORIES -> R.drawable.accessories_set
    SanitaryCategory.COLORS -> R.drawable.colors_sanitary
    else -> R.drawable.vib_logo
  }
}

data class Product(
  val id: String = "",
  val name: String = "",
  val price: Double = 0.0,
  val category: String = SanitaryCategory.BRASS,
  val description: String = "",
  val imageUrl: String = "",
  val drawableRes: Int? = null,
  val inStock: Boolean = true,
  val stockQuantity: Int = 10,
  val createdAt: Long = System.currentTimeMillis()
) {
  fun toMap(): Map<String, Any?> {
    return mapOf(
      "id" to id,
      "name" to name,
      "price" to price,
      "category" to category,
      "description" to description,
      "imageUrl" to imageUrl,
      "inStock" to inStock,
      "stockQuantity" to stockQuantity,
      "createdAt" to createdAt
    )
  }

  companion object {
    fun fromMap(id: String, map: Map<String, Any?>): Product {
      return Product(
        id = id,
        name = map["name"] as? String ?: "",
        price = (map["price"] as? Number)?.toDouble() ?: 0.0,
        category = map["category"] as? String ?: SanitaryCategory.BRASS,
        description = map["description"] as? String ?: "",
        imageUrl = map["imageUrl"] as? String ?: "",
        inStock = map["inStock"] as? Boolean ?: true,
        stockQuantity = (map["stockQuantity"] as? Number)?.toInt() ?: 10,
        createdAt = (map["createdAt"] as? Number)?.toLong() ?: System.currentTimeMillis()
      )
    }
  }
}

data class CartItem(
  val product: Product,
  val quantity: Int = 1
) {
  val subtotal: Double
    get() = product.price * quantity
}

data class Customer(
  val id: String = "",
  val name: String = "",
  val phone: String = "",
  val address: String = "",
  val notes: String = ""
) {
  fun toMap(): Map<String, Any?> {
    return mapOf(
      "id" to id,
      "name" to name,
      "phone" to phone,
      "address" to address,
      "notes" to notes
    )
  }

  companion object {
    fun fromMap(id: String, map: Map<String, Any?>): Customer {
      return Customer(
        id = id,
        name = map["name"] as? String ?: "",
        phone = map["phone"] as? String ?: "",
        address = map["address"] as? String ?: "",
        notes = map["notes"] as? String ?: ""
      )
    }
  }
}

data class Order(
  val id: String = "",
  val customer: Customer,
  val items: List<CartItem>,
  val totalAmount: Double,
  val createdAt: Long = System.currentTimeMillis(),
  val status: String = "جديد"
)
