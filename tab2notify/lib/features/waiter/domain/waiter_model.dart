class WaiterModel {
  final String waiterId; // e.g. "W001"
  final String name;
  final String phone;
  final String passcode; // e.g. "1234"
  final String status; // "active" | "inactive" | "on_break"
  final List<String> assignedTableIds;
  final int createdAt;
  final int? updatedAt;

  const WaiterModel({
    required this.waiterId,
    required this.name,
    this.phone = '',
    this.passcode = '1234',
    this.status = 'active',
    this.assignedTableIds = const [],
    required this.createdAt,
    this.updatedAt,
  });

  bool get isActive => status == 'active';
  int get tableCount => assignedTableIds.length;

  Map<String, dynamic> toMap() {
    return {
      'waiterId': waiterId,
      'name': name,
      'phone': phone,
      'passcode': passcode,
      'status': status,
      'assignedTableIds': assignedTableIds,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory WaiterModel.fromMap(Map<dynamic, dynamic> map, String waiterId) {
    List<String> tables = [];
    if (map['assignedTableIds'] != null) {
      if (map['assignedTableIds'] is List) {
        tables = (map['assignedTableIds'] as List)
            .map((e) => e.toString())
            .toList();
      } else if (map['assignedTableIds'] is Map) {
        tables = (map['assignedTableIds'] as Map)
            .values
            .map((e) => e.toString())
            .toList();
      }
    }

    return WaiterModel(
      waiterId: map['waiterId']?.toString() ?? waiterId,
      name: map['name']?.toString() ?? 'Waiter',
      phone: map['phone']?.toString() ?? '',
      passcode: map['passcode']?.toString() ?? '1234',
      status: map['status']?.toString() ?? 'active',
      assignedTableIds: tables,
      createdAt: (map['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updatedAt'] as num?)?.toInt(),
    );
  }

  WaiterModel copyWith({
    String? name,
    String? phone,
    String? passcode,
    String? status,
    List<String>? assignedTableIds,
    int? updatedAt,
  }) {
    return WaiterModel(
      waiterId: waiterId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      passcode: passcode ?? this.passcode,
      status: status ?? this.status,
      assignedTableIds: assignedTableIds ?? this.assignedTableIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
