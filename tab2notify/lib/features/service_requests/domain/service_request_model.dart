class ServiceRequestModel {
  final String requestId;
  final String hotelId;
  final String roomNumber;
  final String tableNumber;
  final String requestType;
  final String status; // pending, accepted, rejected, completed
  final String priority; // normal, urgent
  final int createdAt;
  final int? updatedAt;
  final String? acceptedBy;
  final int? acceptedAt;

  const ServiceRequestModel({
    required this.requestId,
    this.hotelId = 'default_hotel',
    required this.roomNumber,
    required this.tableNumber,
    required this.requestType,
    required this.status,
    this.priority = 'normal',
    required this.createdAt,
    this.updatedAt,
    this.acceptedBy,
    this.acceptedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'hotelId': hotelId,
      'roomNumber': roomNumber,
      'tableNumber': tableNumber,
      'requestType': requestType,
      'status': status,
      'priority': priority,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'acceptedBy': acceptedBy,
      'acceptedAt': acceptedAt,
    };
  }

  factory ServiceRequestModel.fromMap(Map<dynamic, dynamic> map, String id) {
    return ServiceRequestModel(
      requestId: map['requestId'] as String? ?? id,
      hotelId: map['hotelId'] as String? ?? 'default_hotel',
      roomNumber: map['roomNumber']?.toString() ?? '101',
      tableNumber: map['tableNumber']?.toString() ?? 'T1',
      requestType: map['requestType'] as String? ?? 'water',
      status: map['status'] as String? ?? 'pending',
      priority: map['priority'] as String? ?? 'normal',
      createdAt: (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updatedAt'] as num?)?.toInt(),
      acceptedBy: map['acceptedBy'] as String?,
      acceptedAt: (map['acceptedAt'] as num?)?.toInt(),
    );
  }

  ServiceRequestModel copyWith({
    String? status,
    int? updatedAt,
    String? acceptedBy,
    int? acceptedAt,
  }) {
    return ServiceRequestModel(
      requestId: requestId,
      hotelId: hotelId,
      roomNumber: roomNumber,
      tableNumber: tableNumber,
      requestType: requestType,
      status: status ?? this.status,
      priority: priority,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      acceptedBy: acceptedBy ?? this.acceptedBy,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }
}
