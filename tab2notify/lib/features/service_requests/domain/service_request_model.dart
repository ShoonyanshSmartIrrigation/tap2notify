class ServiceRequestModel {
  final String requestId;
  final String hotelId;
  final String roomNumber;
  final String tableNumber;
  final String requestType;
  final String status; // pending, accepted, rejected, completed
  final String priority; // normal, urgent
  final String managerPhone;
  final String managerUid;
  final String? managerEmail;
  final int createdAt;
  final int? updatedAt;
  final String? acceptedBy;
  final int? acceptedAt;
  final int? requestSentAt;

  const ServiceRequestModel({
    required this.requestId,
    this.hotelId = 'default_hotel',
    required this.roomNumber,
    required this.tableNumber,
    required this.requestType,
    required this.status,
    this.priority = 'normal',
    this.managerPhone = '',
    this.managerUid = '',
    this.managerEmail,
    required this.createdAt,
    this.updatedAt,
    this.acceptedBy,
    this.acceptedAt,
    this.requestSentAt,
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
      'managerPhone': managerPhone,
      'manager_phone': managerPhone,
      'managerUid': managerUid,
      'managerEmail': managerEmail,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'acceptedBy': acceptedBy,
      'acceptedAt': acceptedAt,
      'requestSentAt': requestSentAt,
      'request_sent_at': requestSentAt,
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
      managerPhone: map['managerPhone']?.toString() ?? map['manager_phone']?.toString() ?? '',
      managerUid: map['managerUid']?.toString() ?? map['manager_uid']?.toString() ?? '',
      managerEmail: map['managerEmail']?.toString() ?? map['manager_email']?.toString(),
      createdAt: (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updatedAt'] as num?)?.toInt(),
      acceptedBy: map['acceptedBy'] as String?,
      acceptedAt: (map['acceptedAt'] as num?)?.toInt(),
      requestSentAt: (map['requestSentAt'] as num?)?.toInt() ?? (map['request_sent_at'] as num?)?.toInt(),
    );
  }

  ServiceRequestModel copyWith({
    String? status,
    int? updatedAt,
    String? acceptedBy,
    int? acceptedAt,
    int? requestSentAt,
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
  }) {
    return ServiceRequestModel(
      requestId: requestId,
      hotelId: hotelId,
      roomNumber: roomNumber,
      tableNumber: tableNumber,
      requestType: requestType,
      status: status ?? this.status,
      priority: priority,
      managerPhone: managerPhone ?? this.managerPhone,
      managerUid: managerUid ?? this.managerUid,
      managerEmail: managerEmail ?? this.managerEmail,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      acceptedBy: acceptedBy ?? this.acceptedBy,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      requestSentAt: requestSentAt ?? this.requestSentAt,
    );
  }
}
