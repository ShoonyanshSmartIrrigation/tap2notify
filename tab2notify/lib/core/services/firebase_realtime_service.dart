import 'package:firebase_database/firebase_database.dart';
import '../../features/authentication/domain/user_model.dart';
import '../../features/service_requests/domain/service_request_model.dart';

class FirebaseRealtimeService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // Users Node
  DatabaseReference get _usersRef => _db.ref('users');
  
  // Service Requests Node
  DatabaseReference get _requestsRef => _db.ref('serviceRequests');

  // Create User Profile in DB
  Future<void> createUserProfile(UserModel user) async {
    await _usersRef.child(user.uid).set(user.toMap());
  }

  // Get User Profile
  Future<UserModel?> getUserProfile(String uid) async {
    final snapshot = await _usersRef.child(uid).get();
    if (snapshot.exists && snapshot.value != null) {
      return UserModel.fromMap(snapshot.value as Map<dynamic, dynamic>, uid);
    }
    return null;
  }

  // Listen to Service Requests in real time
  Stream<List<ServiceRequestModel>> getServiceRequestsStream() {
    return _requestsRef.onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) {
        return <ServiceRequestModel>[];
      }

      final Map<dynamic, dynamic> values = snapshot.value as Map<dynamic, dynamic>;
      final List<ServiceRequestModel> requests = [];

      values.forEach((key, value) {
        if (value is Map<dynamic, dynamic>) {
          requests.add(ServiceRequestModel.fromMap(value, key.toString()));
        }
      });

      // Sort by latest created first
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    });
  }

  // Update Request Status (Accept, Reject, Complete)
  Future<void> updateRequestStatus({
    required String requestId,
    required String status,
    String? managerUid,
  }) async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> updates = {
      'status': status,
      'updatedAt': now,
    };

    if (status == 'accepted' && managerUid != null) {
      updates['acceptedBy'] = managerUid;
      updates['acceptedAt'] = now;
    }

    await _requestsRef.child(requestId).update(updates);
  }

  // Add a new mock/ESP request
  Future<void> createRequest(ServiceRequestModel request) async {
    await _requestsRef.child(request.requestId).set(request.toMap());
  }
}
