/// Backend bir alanı String, int veya double olarak döndürebileceği için
/// tüm sayısal/tarih parse işlemleri bu yardımcılardan geçer. Direkt
/// `as String` / `as int` / `as num` cast'i yapmazlar; bunun yerine
/// `?.toString()` ile coerce edip `tryParse` kullanırlar.
double _parseDouble(dynamic v) =>
    double.tryParse(v?.toString() ?? '') ?? 0.0;

int _parseInt(dynamic v) {
  if (v == null) return 0;
  final s = v.toString();
  return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? 0;
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

class Address {
  final String fullAddress;
  final String? title;
  final double latitude;
  final double longitude;
  final String? floor;
  final String? doorNo;
  final String? note;

  const Address({
    required this.fullAddress,
    this.title,
    required this.latitude,
    required this.longitude,
    this.floor,
    this.doorNo,
    this.note,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      fullAddress:
          (json['fullAddress'] ?? json['full_address'])?.toString() ?? '',
      title: json['title']?.toString(),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      floor: json['floor']?.toString(),
      doorNo: (json['doorNo'] ?? json['door_no'])?.toString(),
      note: json['note']?.toString(),
    );
  }

  factory Address.fromRestaurantJson(Map<String, dynamic> json) {
    return Address(
      fullAddress: json['address']?.toString() ?? '',
      title: json['name']?.toString(),
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'full_address': fullAddress,
      'title': title,
      'latitude': latitude,
      'longitude': longitude,
      'floor': floor,
      'door_no': doorNo,
      'note': note,
    };
  }
}

class Customer {
  final String name;
  final String phone;
  final String? email;

  const Customer({
    required this.name,
    required this.phone,
    this.email,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
    };
  }
}

class Order {
  final String id;
  final String orderNumber;
  final String status;
  final Customer customer;
  final Address pickupAddress;
  final Address deliveryAddress;
  final double totalAmount;
  final double deliveryFee;
  final String paymentMethod;
  final double distanceKm;
  final int estimatedMinutes;
  final String? notes;
  final List<OrderItem> items;
  final DateTime createdAt;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final String? restaurantId;
  final String? courierId;
  final Restaurant? restaurant;

  const Order({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.customer,
    required this.pickupAddress,
    required this.deliveryAddress,
    required this.totalAmount,
    required this.deliveryFee,
    required this.paymentMethod,
    required this.distanceKm,
    required this.estimatedMinutes,
    this.notes,
    this.items = const [],
    required this.createdAt,
    this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.restaurantId,
    this.courierId,
    this.restaurant,
  });

  // Geriye d\u00f6n\u00fck uyumluluk: eski `acceptedAt` referanslar\u0131 i\u00e7in
  DateTime? get acceptedAt => assignedAt;

  String get customerName => customer.name;
  String get customerPhone => customer.phone;
  double get orderTotal => totalAmount;
  double get deliveryLatitude => deliveryAddress.latitude;
  double get deliveryLongitude => deliveryAddress.longitude;

  factory Order.fromJson(Map<String, dynamic> json) {
    final customerRaw = json['customer'];
    final customer = customerRaw is Map<String, dynamic>
        ? Customer.fromJson(customerRaw)
        : Customer(
            name: json['customerName']?.toString() ?? '',
            phone: json['customerPhone']?.toString() ?? '',
          );

    final pickupRaw = json['pickup_address'] ?? json['pickupAddress'];
    final Address pickupAddress;
    if (pickupRaw is Map<String, dynamic>) {
      pickupAddress = Address.fromJson(pickupRaw);
    } else if (json['restaurant'] is Map<String, dynamic>) {
      pickupAddress = Address.fromRestaurantJson(
        json['restaurant'] as Map<String, dynamic>,
      );
    } else {
      pickupAddress = Address(
        fullAddress: pickupRaw?.toString() ?? '',
        latitude: 0,
        longitude: 0,
      );
    }

    final deliveryRaw = json['delivery_address'] ?? json['deliveryAddress'];
    final Address deliveryAddress;
    if (deliveryRaw is Map<String, dynamic>) {
      deliveryAddress = Address.fromJson(deliveryRaw);
    } else {
      deliveryAddress = Address(
        fullAddress: deliveryRaw?.toString() ?? '',
        latitude: _parseDouble(json['deliveryLatitude']),
        longitude: _parseDouble(json['deliveryLongitude']),
      );
    }

    return Order(
      id: json['id']?.toString() ?? '',
      orderNumber:
          (json['orderNumber'] ?? json['order_number'])?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      customer: customer,
      pickupAddress: pickupAddress,
      deliveryAddress: deliveryAddress,
      totalAmount: _parseDouble(
        json['orderTotal'] ?? json['totalAmount'] ?? json['total_amount'],
      ),
      deliveryFee: _parseDouble(
        json['deliveryFee'] ?? json['delivery_fee'],
      ),
      paymentMethod:
          (json['paymentMethod'] ?? json['payment_method'])?.toString() ??
              'cash',
      distanceKm: _parseDouble(
        json['distanceKm'] ?? json['distance_km'],
      ),
      estimatedMinutes: _parseInt(
        json['estimatedMinutes'] ?? json['estimated_minutes'],
      ),
      notes: json['notes']?.toString(),
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt:
          _parseDate(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      assignedAt: _parseDate(
        json['assignedAt'] ?? json['assigned_at'] ?? json['accepted_at'],
      ),
      pickedUpAt: _parseDate(json['pickedUpAt'] ?? json['picked_up_at']),
      deliveredAt: _parseDate(json['deliveredAt'] ?? json['delivered_at']),
      restaurantId:
          (json['restaurantId'] ?? json['restaurant_id'])?.toString(),
      courierId: (json['courierId'] ?? json['courier_id'])?.toString(),
      restaurant: json['restaurant'] is Map<String, dynamic>
          ? Restaurant.fromJson(json['restaurant'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderNumber': orderNumber,
      'status': status,
      'customer': customer.toJson(),
      'customerName': customer.name,
      'customerPhone': customer.phone,
      'pickup_address': pickupAddress.toJson(),
      'delivery_address': deliveryAddress.toJson(),
      'deliveryAddress': deliveryAddress.fullAddress,
      'deliveryLatitude': deliveryAddress.latitude,
      'deliveryLongitude': deliveryAddress.longitude,
      'orderTotal': totalAmount,
      'deliveryFee': deliveryFee,
      'paymentMethod': paymentMethod,
      'distance_km': distanceKm,
      'estimated_minutes': estimatedMinutes,
      'notes': notes,
      'items': items.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'assignedAt': assignedAt?.toIso8601String(),
      'pickedUpAt': pickedUpAt?.toIso8601String(),
      'deliveredAt': deliveredAt?.toIso8601String(),
      'restaurantId': restaurantId,
      'courierId': courierId,
      'restaurant': restaurant?.toJson(),
    };
  }

  Order copyWith({
    String? status,
    DateTime? assignedAt,
    DateTime? pickedUpAt,
    DateTime? deliveredAt,
    String? courierId,
  }) {
    return Order(
      id: id,
      orderNumber: orderNumber,
      status: status ?? this.status,
      customer: customer,
      pickupAddress: pickupAddress,
      deliveryAddress: deliveryAddress,
      totalAmount: totalAmount,
      deliveryFee: deliveryFee,
      paymentMethod: paymentMethod,
      distanceKm: distanceKm,
      estimatedMinutes: estimatedMinutes,
      notes: notes,
      items: items,
      createdAt: createdAt,
      assignedAt: assignedAt ?? this.assignedAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      restaurantId: restaurantId,
      courierId: courierId ?? this.courierId,
      restaurant: restaurant,
    );
  }
}

class Restaurant {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String phone;

  const Restaurant({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.phone,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      phone: json['phone']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'phone': phone,
    };
  }
}

class OrderItem {
  final String name;
  final int quantity;
  final double price;
  final String? note;

  const OrderItem({
    required this.name,
    required this.quantity,
    required this.price,
    this.note,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      name: json['name']?.toString() ?? '',
      quantity: _parseInt(json['quantity'] ?? 1),
      price: _parseDouble(json['price']),
      note: json['note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'price': price,
      'note': note,
    };
  }
}
