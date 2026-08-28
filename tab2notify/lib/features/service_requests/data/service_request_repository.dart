import '../../../core/services/firebase_realtime_service.dart';
import '../domain/service_request_model.dart';

class ServiceRequestRepository {
  final FirebaseRealtimeService _dbService;

  ServiceRequestRepository(this._dbService);

  Stream<List<ServiceRequestModel>> getServiceRequestsStream() {
    return _dbService.getServiceRequestsStream();
  }

  Future<void> acceptRequest(String requestId, String managerUid) async {
    await _dbService.updateRequestStatus(
      requestId: requestId,
      status: 'accepted',
      managerUid: managerUid,
    );
  }

  Future<void> rejectRequest(String requestId) async {
    await _dbService.updateRequestStatus(
      requestId: requestId,
      status: 'rejected',
    );
  }

  Future<void> completeRequest(String requestId) async {
    await _dbService.updateRequestStatus(
      requestId: requestId,
      status: 'completed',
    );
  }
}
