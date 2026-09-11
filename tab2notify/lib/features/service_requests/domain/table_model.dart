class TableModel {
  final String id;
  final dynamic tableNumber;
  final String deviceId;
  final String status; // 'idle', 'pending', 'accepted', 'completed', 'in_progress'
  final int flag; // 0 = pending, 1 = accepted, -1 = idle
  final String waiterName;
  final String assignedWaiterId;
  final bool isDeviceOnline;
  final String managerPhone;
  final String managerUid;
  final String? managerEmail;
  final int createdAt;
  final int? updatedAt;
  final int? acceptedAt;
  final int? requestSentAt;

  const TableModel({
    required this.id,
    required this.tableNumber,
    required this.deviceId,
    this.status = 'idle',
    this.flag = -1,
    this.waiterName = '',
    this.assignedWaiterId = '',
    this.isDeviceOnline = false,
    this.managerPhone = '',
    this.managerUid = '',
    this.managerEmail,
    required this.createdAt,
    this.updatedAt,
    this.acceptedAt,
    this.requestSentAt,
  });

  bool get isPending => flag == 0 || status == 'pending' || status == 'new_request';
  bool get isAccepted => flag == 1 || status == 'accepted' || status == 'in_progress';
  bool get isIdle => !isPending && !isAccepted;
  bool get isOnline => isDeviceOnline;
  bool get isAssigned => assignedWaiterId.isNotEmpty || waiterName.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table_number': tableNumber,
      'device_id': deviceId,
      'status': status,
      'flag': flag,
      'waiter_name': waiterName,
      'assigned_waiter_id': assignedWaiterId,
      'assigned_waiter_name': waiterName,
      'device_online': isDeviceOnline,
      'manager_phone': managerPhone,
      'manager_uid': managerUid,
      'manager_email': managerEmail,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'accepted_at': acceptedAt,
      'request_sent_at': requestSentAt,
    };
  }

  factory TableModel.fromMap(Map<dynamic, dynamic> map, String id) {
    int parsedFlag = -1;
    if (map['flag'] != null) {
      if (map['flag'] is num) {
        parsedFlag = (map['flag'] as num).toInt();
      } else if (map['flag'].toString() == '0') {
        parsedFlag = 0;
      } else if (map['flag'].toString() == '1') {
        parsedFlag = 1;
      }
    } else if (map['status'] == 'pending' || map['status'] == 'new_request') {
      parsedFlag = 0;
    } else if (map['status'] == 'accepted' || map['status'] == 'in_progress') {
      parsedFlag = 1;
    }

    dynamic parsedTableNumber = '1';
    if (map['table_number'] != null) {
      parsedTableNumber = map['table_number'];
    } else if (map['tableNumber'] != null) {
      parsedTableNumber = map['tableNumber'];
    } else {
      // Parse from ID (e.g. table_1 -> 1, table_A1 -> A1)
      final numStr = id.startsWith('table_') ? id.substring(6) : id;
      if (numStr.isNotEmpty) {
        parsedTableNumber = numStr;
      }
    }

    final bool online = (map['device_online'] == true) ||
        (map['online'] == true) ||
        (map['is_online'] == true);

    final String wName = map['assigned_waiter_name']?.toString() ??
        map['waiter_name']?.toString() ??
        map['waiterName']?.toString() ??
        '';

    final String wId = map['assigned_waiter_id']?.toString() ??
        map['waiter_id']?.toString() ??
        map['waiterId']?.toString() ??
        '';

    final String mPhone = map['manager_phone']?.toString() ??
        map['managerPhone']?.toString() ??
        '';

    final String mUid = map['manager_uid']?.toString() ??
        map['managerUid']?.toString() ??
        '';

    final String? mEmail = map['manager_email']?.toString() ??
        map['managerEmail']?.toString();

    return TableModel(
      id: map['id']?.toString() ?? id,
      tableNumber: parsedTableNumber,
      deviceId: map['device_id']?.toString() ?? map['deviceId']?.toString() ?? 'device_$parsedTableNumber',
      status: map['status']?.toString() ?? (parsedFlag == 0 ? 'pending' : (parsedFlag == 1 ? 'accepted' : 'idle')),
      flag: parsedFlag,
      waiterName: wName,
      assignedWaiterId: wId,
      isDeviceOnline: online,
      managerPhone: mPhone,
      managerUid: mUid,
      managerEmail: mEmail,
      createdAt: (map['created_at'] as num?)?.toInt() ?? (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? (map['updatedAt'] as num?)?.toInt(),
      acceptedAt: (map['accepted_at'] as num?)?.toInt() ?? (map['acceptedAt'] as num?)?.toInt(),
      requestSentAt: (map['request_sent_at'] as num?)?.toInt() ?? (map['requestSentAt'] as num?)?.toInt(),
    );
  }

  TableModel copyWith({
    String? status,
    int? flag,
    String? waiterName,
    String? assignedWaiterId,
    bool? isDeviceOnline,
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
    int? updatedAt,
    int? acceptedAt,
    int? requestSentAt,
  }) {
    return TableModel(
      id: id,
      tableNumber: tableNumber,
      deviceId: deviceId,
      status: status ?? this.status,
      flag: flag ?? this.flag,
      waiterName: waiterName ?? this.waiterName,
      assignedWaiterId: assignedWaiterId ?? this.assignedWaiterId,
      isDeviceOnline: isDeviceOnline ?? this.isDeviceOnline,
      managerPhone: managerPhone ?? this.managerPhone,
      managerUid: managerUid ?? this.managerUid,
      managerEmail: managerEmail ?? this.managerEmail,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      requestSentAt: requestSentAt ?? this.requestSentAt,
    );
  }
}
