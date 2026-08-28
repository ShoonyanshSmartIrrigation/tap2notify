import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../data/service_request_repository.dart';
import '../domain/service_request_model.dart';

final serviceRequestRepositoryProvider = Provider<ServiceRequestRepository>((ref) {
  final dbService = ref.watch(firebaseRealtimeServiceProvider);
  return ServiceRequestRepository(dbService);
});

// Stream of all requests
final serviceRequestsStreamProvider = StreamProvider<List<ServiceRequestModel>>((ref) {
  final repo = ref.watch(serviceRequestRepositoryProvider);
  return repo.getServiceRequestsStream();
});

// Derived Providers for filtered requests
final pendingRequestsProvider = Provider<List<ServiceRequestModel>>((ref) {
  final requestsAsync = ref.watch(serviceRequestsStreamProvider);
  return requestsAsync.value?.where((req) => req.status == 'pending').toList() ?? [];
});

final acceptedRequestsProvider = Provider<List<ServiceRequestModel>>((ref) {
  final requestsAsync = ref.watch(serviceRequestsStreamProvider);
  return requestsAsync.value?.where((req) => req.status == 'accepted').toList() ?? [];
});

final completedRequestsProvider = Provider<List<ServiceRequestModel>>((ref) {
  final requestsAsync = ref.watch(serviceRequestsStreamProvider);
  return requestsAsync.value?.where((req) => req.status == 'completed').toList() ?? [];
});

final todayRequestsCountProvider = Provider<int>((ref) {
  final requestsAsync = ref.watch(serviceRequestsStreamProvider);
  final all = requestsAsync.value ?? [];
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  return all.where((req) => req.createdAt >= startOfDay).length;
});
