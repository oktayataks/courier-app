class Courier {
  final String id;
  final String userId;
  final String name;
  final String phone;
  final String? avatarUrl;
  final String status;
  final String vehicleType;
  final String? vehiclePlate;
  final double rating;
  final int totalDeliveries;
  final double totalEarnings;
  final double todayEarnings;
  final int todayDeliveries;
  final double? currentLatitude;
  final double? currentLongitude;
  final bool isAvailable;
  final int activeOrders;

  const Courier({
    required this.id,
    required this.userId,
    required this.name,
    required this.phone,
    this.avatarUrl,
    this.status = 'offline',
    this.vehicleType = 'motorcycle',
    this.vehiclePlate,
    this.rating = 0.0,
    this.totalDeliveries = 0,
    this.totalEarnings = 0.0,
    this.todayEarnings = 0.0,
    this.todayDeliveries = 0,
    this.currentLatitude,
    this.currentLongitude,
    this.isAvailable = false,
    this.activeOrders = 0,
  });

  // Yeni \u015fema ile uyumluluk getter'lar\u0131
  bool get isOnline => isAvailable;
  double? get latitude => currentLatitude;
  double? get longitude => currentLongitude;

  factory Courier.fromJson(Map<String, dynamic> json) {
    return Courier(
      id: json['id']?.toString() ?? '',
      userId: (json['user_id'] ?? json['userId'])?.toString() ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      avatarUrl: (json['avatar_url'] ?? json['avatarUrl']) as String?,
      status: json['status'] as String? ?? 'offline',
      vehicleType:
          (json['vehicle_type'] ?? json['vehicleType']) as String? ??
              'motorcycle',
      vehiclePlate: (json['vehicle_plate'] ?? json['vehiclePlate']) as String?,
      rating: ((json['rating']) as num?)?.toDouble() ?? 5.0,
      totalDeliveries:
          ((json['total_deliveries'] ?? json['totalDeliveries']) as num?)
                  ?.toInt() ??
              0,
      totalEarnings:
          ((json['total_earnings'] ?? json['totalEarnings']) as num?)
                  ?.toDouble() ??
              0.0,
      todayEarnings:
          ((json['today_earnings'] ?? json['todayEarnings']) as num?)
                  ?.toDouble() ??
              0.0,
      todayDeliveries:
          ((json['today_deliveries'] ?? json['todayDeliveries']) as num?)
                  ?.toInt() ??
              0,
      currentLatitude:
          ((json['current_latitude'] ?? json['latitude']) as num?)?.toDouble(),
      currentLongitude:
          ((json['current_longitude'] ?? json['longitude']) as num?)
              ?.toDouble(),
      isAvailable:
          (json['is_available'] ?? json['isOnline']) as bool? ?? false,
      activeOrders: (json['activeOrders'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'phone': phone,
      'avatarUrl': avatarUrl,
      'status': status,
      'vehicleType': vehicleType,
      'vehiclePlate': vehiclePlate,
      'rating': rating,
      'totalDeliveries': totalDeliveries,
      'totalEarnings': totalEarnings,
      'todayEarnings': todayEarnings,
      'todayDeliveries': todayDeliveries,
      'latitude': currentLatitude,
      'longitude': currentLongitude,
      'isOnline': isAvailable,
      'activeOrders': activeOrders,
    };
  }

  Courier copyWith({
    String? status,
    double? currentLatitude,
    double? currentLongitude,
    double? latitude,
    double? longitude,
    bool? isAvailable,
    bool? isOnline,
    double? todayEarnings,
    int? todayDeliveries,
    int? activeOrders,
  }) {
    return Courier(
      id: id,
      userId: userId,
      name: name,
      phone: phone,
      avatarUrl: avatarUrl,
      status: status ?? this.status,
      vehicleType: vehicleType,
      vehiclePlate: vehiclePlate,
      rating: rating,
      totalDeliveries: totalDeliveries,
      totalEarnings: totalEarnings,
      todayEarnings: todayEarnings ?? this.todayEarnings,
      todayDeliveries: todayDeliveries ?? this.todayDeliveries,
      currentLatitude:
          latitude ?? currentLatitude ?? this.currentLatitude,
      currentLongitude:
          longitude ?? currentLongitude ?? this.currentLongitude,
      isAvailable: isOnline ?? isAvailable ?? this.isAvailable,
      activeOrders: activeOrders ?? this.activeOrders,
    );
  }
}
