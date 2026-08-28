class UserModel {
  final String uid;
  final String fullName;
  final String email;
  final String phone;
  final String role;
  final int createdAt;

  const UserModel({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.phone,
    this.role = 'manager',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'role': role,
      'createdAt': createdAt,
    };
  }

  factory UserModel.fromMap(Map<dynamic, dynamic> map, String uid) {
    return UserModel(
      uid: uid,
      fullName: map['fullName'] as String? ?? 'Manager',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      role: map['role'] as String? ?? 'manager',
      createdAt: (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
