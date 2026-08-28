import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/dashboard_summary_card.dart';
import '../../../core/widgets/request_card.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../service_requests/domain/service_request_model.dart';
import '../../service_requests/presentation/service_request_providers.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _selectedFilter = 'pending'; // 'all', 'pending', 'accepted', 'completed'

  // Local Router ESP32 Sync
  String? _esp32Ip;
  Timer? _pollTimer;
  ServiceRequestModel? _localEspRequest;
  bool _isEspConnected = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startEspPolling(String ip) {
    _esp32Ip = ip.trim().replaceAll('http://', '').replaceAll('/', '');
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _fetchEspStatus();
    });
    _fetchEspStatus();
  }

  Future<void> _fetchEspStatus() async {
    if (_esp32Ip == null || _esp32Ip!.isEmpty) return;
    try {
      final url = Uri.parse('http://$_esp32Ip/status');
      final res = await http.get(url).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final status = data['status'] as String? ?? 'idle';
        setState(() {
          _isEspConnected = true;
          if (status == 'pending') {
            _localEspRequest = ServiceRequestModel(
              requestId: 'esp32_hardware_req',
              roomNumber: data['room']?.toString() ?? '101',
              tableNumber: data['table']?.toString() ?? 'T1',
              requestType: data['service']?.toString() ?? 'water',
              status: 'pending',
              createdAt: DateTime.now().millisecondsSinceEpoch,
            );
          } else if (status == 'accepted') {
            if (_localEspRequest != null) {
              _localEspRequest = _localEspRequest!.copyWith(status: 'accepted');
            } else {
              _localEspRequest = ServiceRequestModel(
                requestId: 'esp32_hardware_req',
                roomNumber: data['room']?.toString() ?? '101',
                tableNumber: data['table']?.toString() ?? 'T1',
                requestType: data['service']?.toString() ?? 'water',
                status: 'accepted',
                createdAt: DateTime.now().millisecondsSinceEpoch,
              );
            }
          } else {
            _localEspRequest = null;
          }
        });
      }
    } catch (_) {
      if (mounted && _isEspConnected) {
        setState(() => _isEspConnected = false);
      }
    }
  }

  Future<void> _sendEspAction(String action) async {
    if (_esp32Ip == null) return;
    try {
      final url = Uri.parse('http://$_esp32Ip/$action');
      await http.get(url).timeout(const Duration(seconds: 2));
      _fetchEspStatus();
    } catch (_) {}
  }

  void _showEspConnectDialog() {
    final controller = TextEditingController(text: _esp32Ip ?? '');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.wifi_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Connect to ESP32'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the local IP of your ESP32 connected to the Wi-Fi router:'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ESP32 IP Address',
                  hintText: 'e.g. 192.168.1.50',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _pollTimer?.cancel();
                setState(() {
                  _esp32Ip = null;
                  _isEspConnected = false;
                  _localEspRequest = null;
                });
                Navigator.pop(context);
              },
              child: const Text('Disconnect'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  _startEspPolling(controller.text.trim());
                }
                Navigator.pop(context);
              },
              child: const Text('Connect & Sync'),
            ),
          ],
        );
      },
    );
  }

  void _showDetailsBottomSheet(ServiceRequestModel request) {
    final theme = Theme.of(context);
    final dt = DateTime.fromMillisecondsSinceEpoch(request.createdAt);
    final formattedTime = DateFormat('MMM d, yyyy • h:mm:ss a').format(dt);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Request Details',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: request.status == 'pending'
                          ? const Color(0xFFE53935).withValues(alpha: 0.15)
                          : const Color(0xFF2E7D32).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      request.status.toUpperCase(),
                      style: TextStyle(
                        color: request.status == 'pending' ? const Color(0xFFE53935) : const Color(0xFF2E7D32),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              _buildDetailRow('Request ID', request.requestId),
              _buildDetailRow('Room Number', 'Room ${request.roomNumber}'),
              _buildDetailRow('Table Number', 'Table ${request.tableNumber}'),
              _buildDetailRow('Service Type', request.requestType.toUpperCase()),
              _buildDetailRow('Created Time', formattedTime),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }

  // Simulate an ESP32 tap for instant local testing!
  Future<void> _simulateEsp32Tap() async {
    final newId = 'esp32_req_${DateTime.now().millisecondsSinceEpoch % 10000}';
    final sampleReq = ServiceRequestModel(
      requestId: newId,
      roomNumber: '101',
      tableNumber: 'T1',
      requestType: 'water',
      status: 'pending',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    final db = ref.read(firebaseRealtimeServiceProvider);
    await db.createRequest(sampleReq);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔴 Simulated ESP32 Touch: RED New Request created!'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProfileAsync = ref.watch(currentUserProfileProvider);
    final allRequestsAsync = ref.watch(serviceRequestsStreamProvider);
    final user = ref.watch(authStateProvider).value;

    List<ServiceRequestModel> firebaseList = allRequestsAsync.value ?? [];
    List<ServiceRequestModel> combinedList = List.from(firebaseList);

    // Merge direct local ESP32 request if active
    if (_localEspRequest != null) {
      combinedList.removeWhere((r) => r.requestId == _localEspRequest!.requestId);
      combinedList.insert(0, _localEspRequest!);
    }

    final pendingList = combinedList.where((req) => req.status == 'pending').toList();
    final acceptedList = combinedList.where((req) => req.status == 'accepted').toList();
    final completedList = combinedList.where((req) => req.status == 'completed').toList();

    List<ServiceRequestModel> displayList = [];
    if (_selectedFilter == 'pending') {
      displayList = pendingList;
    } else if (_selectedFilter == 'accepted') {
      displayList = acceptedList;
    } else if (_selectedFilter == 'completed') {
      displayList = completedList;
    } else {
      displayList = combinedList;
    }

    final repo = ref.read(serviceRequestRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.hotel_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tab2Notify', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                userProfileAsync.when(
                  data: (profile) => Text(
                    profile?.fullName ?? 'Manager',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (error, stackTrace) => const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isEspConnected ? 'ESP32 Wi-Fi Connected' : 'Connect ESP32 via Wi-Fi',
            icon: Icon(
              Icons.wifi_tethering_rounded,
              color: _isEspConnected ? Colors.green : Colors.grey,
            ),
            onPressed: _showEspConnectDialog,
          ),
          IconButton(
            tooltip: 'Simulate Touch Tap',
            icon: const Icon(Icons.touch_app_rounded, color: Colors.orange),
            onPressed: _simulateEsp32Tap,
          ),
          IconButton(
            tooltip: 'Toggle Theme',
            icon: Icon(theme.brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Router Sync Status Bar
                  if (_esp32Ip != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: _isEspConnected
                            ? const Color(0xFF2E7D32).withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isEspConnected ? Colors.green : Colors.orange,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isEspConnected ? Icons.check_circle : Icons.sync,
                            size: 18,
                            color: _isEspConnected ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isEspConnected
                                  ? 'Connected directly to ESP32 at $_esp32Ip'
                                  : 'Connecting to ESP32 at $_esp32Ip...',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _isEspConnected ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  Text('Overview', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.4,
                    children: [
                      DashboardSummaryCard(
                        title: 'Pending (Red)',
                        count: '${pendingList.length}',
                        icon: Icons.notifications_active_rounded,
                        color: const Color(0xFFE53935),
                      ),
                      DashboardSummaryCard(
                        title: 'Accepted (Green)',
                        count: '${acceptedList.length}',
                        icon: Icons.check_circle_outline,
                        color: const Color(0xFF2E7D32),
                      ),
                      DashboardSummaryCard(
                        title: 'Completed',
                        count: '${completedList.length}',
                        icon: Icons.task_alt,
                        color: Colors.blue,
                      ),
                      DashboardSummaryCard(
                        title: 'Total Today',
                        count: '${combinedList.length}',
                        icon: Icons.calendar_today,
                        color: Colors.purple,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Service Requests', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      Text('${displayList.length} items', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('Pending 🔴 (${pendingList.length})', 'pending'),
                        _buildFilterChip('Accepted 🟢 (${acceptedList.length})', 'accepted'),
                        _buildFilterChip('Completed (${completedList.length})', 'completed'),
                        _buildFilterChip('All (${combinedList.length})', 'all'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          if (displayList.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 16.0),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text(
                        _selectedFilter == 'pending'
                            ? 'No pending requests!'
                            : 'No requests in this category.',
                        style: TextStyle(
                          fontSize: 16,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the touch sensor on the ESP32 or press 👆 to test.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final req = displayList[index];
                    return RequestCard(
                      request: req,
                      onTap: () => _showDetailsBottomSheet(req),
                      onAccept: () async {
                        // If direct local ESP32
                        if (req.requestId == 'esp32_hardware_req') {
                          await _sendEspAction('accept');
                        } else {
                          await repo.acceptRequest(req.requestId, user?.uid ?? 'manager');
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('🟢 Request for Room ${req.roomNumber} Accepted (Hardware Green)'),
                              backgroundColor: const Color(0xFF2E7D32),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      onReject: () async {
                        if (req.requestId == 'esp32_hardware_req') {
                          await _sendEspAction('reject');
                        } else {
                          await repo.rejectRequest(req.requestId);
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Request for Room ${req.roomNumber} Rejected'),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      onComplete: () async {
                        if (req.requestId == 'esp32_hardware_req') {
                          setState(() => _localEspRequest = null);
                        } else {
                          await repo.completeRequest(req.requestId);
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ Room ${req.roomNumber} marked Completed'),
                              backgroundColor: Colors.blue,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    );
                  },
                  childCount: displayList.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: theme.colorScheme.primary,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : theme.colorScheme.onSurface.withValues(alpha: 0.8),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (_) => setState(() => _selectedFilter = value),
      ),
    );
  }
}
