class TableModel {
  final String id;
  final int tableNumber;
  final String deviceId;
  final String status; // 'idle', 'pending', 'accepted', 'completed'
  final int flag; // 0 = pending, 1 = accepted, -1 = idle
  final String waiterName;
  final bool isDeviceOnline;
  final int createdAt;
  final int? updatedAt;
  final int? acceptedAt;

  const TableModel({
    required this.id,
    required this.tableNumber,
    required this.deviceId,
    this.status = 'idle',
    this.flag = -1,
    this.waiterName = '',
    this.isDeviceOnline = false,
    required this.createdAt,
    this.updatedAt,
    this.acceptedAt,
  });

  bool get isPending => flag == 0 || status == 'pending';
  bool get isAccepted => flag == 1 || status == 'accepted';
  bool get isIdle => !isPending && !isAccepted;
  bool get isOnline => isDeviceOnline;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'table_number': tableNumber,
      'device_id': deviceId,
      'status': status,
      'flag': flag,
      'waiter_name': waiterName,
      'device_online': isDeviceOnline,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'accepted_at': acceptedAt,
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
    } else if (map['status'] == 'pending') {
      parsedFlag = 0;
    } else if (map['status'] == 'accepted') {
      parsedFlag = 1;
    }

    int parsedTableNumber = 1;
    if (map['table_number'] != null) {
      parsedTableNumber = (map['table_number'] as num).toInt();
    } else if (map['tableNumber'] != null) {
      parsedTableNumber = int.tryParse(map['tableNumber'].toString()) ?? 1;
    } else {
      // Parse from ID (e.g. table_1 -> 1)
      final numStr = id.replaceAll(RegExp(r'[^0-9]'), '');
      if (numStr.isNotEmpty) {
        parsedTableNumber = int.tryParse(numStr) ?? 1;
      }
    }

    final bool online = (map['device_online'] == true) ||
        (map['online'] == true) ||
        (map['is_online'] == true);

    return TableModel(
      id: map['id']?.toString() ?? id,
      tableNumber: parsedTableNumber,
      deviceId: map['device_id']?.toString() ?? map['deviceId']?.toString() ?? 'device_$parsedTableNumber',
      status: map['status']?.toString() ?? (parsedFlag == 0 ? 'pending' : (parsedFlag == 1 ? 'accepted' : 'idle')),
      flag: parsedFlag,
      waiterName: map['waiter_name']?.toString() ?? map['waiterName']?.toString() ?? '',
      isDeviceOnline: online,
      createdAt: (map['created_at'] as num?)?.toInt() ?? (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? (map['updatedAt'] as num?)?.toInt(),
      acceptedAt: (map['accepted_at'] as num?)?.toInt() ?? (map['acceptedAt'] as num?)?.toInt(),
    );
  }

  TableModel copyWith({
    String? status,
    int? flag,
    String? waiterName,
    bool? isDeviceOnline,
    int? updatedAt,
    int? acceptedAt,
  }) {
    return TableModel(
      id: id,
      tableNumber: tableNumber,
      deviceId: deviceId,
      status: status ?? this.status,
      flag: flag ?? this.flag,
      waiterName: waiterName ?? this.waiterName,
      isDeviceOnline: isDeviceOnline ?? this.isDeviceOnline,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }
}
