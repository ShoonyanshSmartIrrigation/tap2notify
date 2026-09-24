class TableModel {
  final String id;
  final dynamic tableNumber;
  final String deviceId;
  final String status; // 'idle', 'pending', 'accepted', 'completed', 'in_progress'
  final int flag; // 0 = pending, 1 = accepted, -1 = idle, -2 = locked
  final String waiterName;
  final String assignedWaiterId;
  final bool isDeviceOnline;
  final bool isUnlocked; // Authorization status (Manager-only password unlock)
  final int? unlockedAt;
  final String? unlockedBy;
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
    this.isUnlocked = false,
    this.unlockedAt,
    this.unlockedBy,
    this.managerPhone = '',
    this.managerUid = '',
    this.managerEmail,
    required this.createdAt,
    this.updatedAt,
    this.acceptedAt,
    this.requestSentAt,
  });

  bool get isPending {
    if (flag == 0) return true;
    if (flag == 1 || flag == -1 || flag == -2) return false;
    final s = status.trim().toLowerCase();
    return s == 'pending' || s == 'new_request' || s == 'calling';
  }

  bool get isAccepted {
    if (flag == 1) return true;
    if (flag == 0 || flag == -1 || flag == -2) return false;
    final s = status.trim().toLowerCase();
    return s == 'accepted' || s == 'in_progress' || s == 'serving';
  }

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
      'is_unlocked': isUnlocked,
      'unlocked_at': unlockedAt,
      'unlocked_by': unlockedBy,
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
      } else {
        final flagStr = map['flag'].toString().trim().toLowerCase();
        if (flagStr == '0' || flagStr == 'pending' || flagStr == 'new_request' || flagStr == 'calling') {
          parsedFlag = 0;
        } else if (flagStr == '1' || flagStr == 'accepted' || flagStr == 'in_progress' || flagStr == 'serving') {
          parsedFlag = 1;
        } else if (flagStr == '-2' || flagStr == 'locked') {
          parsedFlag = -2;
        } else {
          parsedFlag = -1;
        }
      }
    } else if (map['status'] != null) {
      final statusStr = map['status'].toString().trim().toLowerCase();
      if (statusStr == 'pending' || statusStr == 'new_request' || statusStr == 'calling') {
        parsedFlag = 0;
      } else if (statusStr == 'accepted' || statusStr == 'in_progress' || statusStr == 'serving') {
        parsedFlag = 1;
      } else if (statusStr == 'locked') {
        parsedFlag = -2;
      } else {
        parsedFlag = -1;
      }
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

    final bool unlocked = (map['is_unlocked'] == true) ||
        (map['isUnlocked'] == true) ||
        (map['unlocked'] == true) ||
        (map['assigned_waiter_id'] != null && map['assigned_waiter_id'].toString().isNotEmpty);

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

    final String normalizedStatus = parsedFlag == 0
        ? 'pending'
        : (parsedFlag == 1
            ? 'accepted'
            : (parsedFlag == -1 || parsedFlag == -2
                ? 'idle'
                : (map['status']?.toString().toLowerCase() ?? 'idle')));

    final int createdAtTime = (map['created_at'] as num?)?.toInt() ??
        (map['createdAt'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;

    final int? updatedTime = (map['updated_at'] as num?)?.toInt() ??
        (map['updatedAt'] as num?)?.toInt();

    final int? accAt = (map['accepted_at'] as num?)?.toInt() ??
        (map['acceptedAt'] as num?)?.toInt();

    int? reqSentAt = (map['request_sent_at'] as num?)?.toInt() ??
        (map['requestSentAt'] as num?)?.toInt();
    if (parsedFlag == 0 && reqSentAt == null) {
      reqSentAt = updatedTime ?? createdAtTime;
    }

    return TableModel(
      id: map['id']?.toString() ?? id,
      tableNumber: parsedTableNumber,
      deviceId: map['device_id']?.toString() ?? map['deviceId']?.toString() ?? 'device_$parsedTableNumber',
      status: normalizedStatus,
      flag: parsedFlag,
      waiterName: wName,
      assignedWaiterId: wId,
      isDeviceOnline: online,
      isUnlocked: unlocked,
      unlockedAt: (map['unlocked_at'] as num?)?.toInt() ?? (map['unlockedAt'] as num?)?.toInt(),
      unlockedBy: map['unlocked_by']?.toString() ?? map['unlockedBy']?.toString(),
      managerPhone: mPhone,
      managerUid: mUid,
      managerEmail: mEmail,
      createdAt: createdAtTime,
      updatedAt: updatedTime,
      acceptedAt: accAt,
      requestSentAt: reqSentAt,
    );
  }

  TableModel copyWith({
    String? status,
    int? flag,
    String? waiterName,
    String? assignedWaiterId,
    bool? isDeviceOnline,
    bool? isUnlocked,
    int? unlockedAt,
    String? unlockedBy,
    String? managerPhone,
    String? managerUid,
    String? managerEmail,
    int? updatedAt,
    int? acceptedAt,
    int? requestSentAt,
  }) {
    final int newFlag = flag ?? this.flag;
    String newStatus = status ?? this.status;

    // Synchronize status with flag if flag is explicitly provided without status
    if (flag != null && status == null) {
      if (newFlag == 0) {
        newStatus = 'pending';
      } else if (newFlag == 1) {
        newStatus = 'accepted';
      } else if (newFlag == -1 || newFlag == -2) {
        newStatus = 'idle';
      }
    } else if (status != null && flag == null) {
      if (newStatus == 'pending' || newStatus == 'new_request' || newStatus == 'calling') {
        // Flag can be inferred if not provided
      }
    }

    return TableModel(
      id: id,
      tableNumber: tableNumber,
      deviceId: deviceId,
      status: newStatus,
      flag: newFlag,
      waiterName: waiterName ?? this.waiterName,
      assignedWaiterId: assignedWaiterId ?? this.assignedWaiterId,
      isDeviceOnline: isDeviceOnline ?? this.isDeviceOnline,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      unlockedBy: unlockedBy ?? this.unlockedBy,
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
