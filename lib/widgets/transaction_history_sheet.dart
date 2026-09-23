import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/currency.dart';

class TransactionHistorySheet extends StatefulWidget {
  final Currency currency;
  final String authToken;
  final String serverBaseUrl;

  const TransactionHistorySheet({
    super.key,
    required this.currency,
    required this.authToken,
    required this.serverBaseUrl,
  });

  @override
  State<TransactionHistorySheet> createState() => _TransactionHistorySheetState();
}

class _TransactionHistorySheetState extends State<TransactionHistorySheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _errorMessage;

  List<dynamic> _deposits = [];
  List<dynamic> _withdrawals = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('${widget.serverBaseUrl}/admin/my-history?token=${Uri.encodeComponent(widget.authToken)}');
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _deposits = data['deposits'] ?? [];
            _withdrawals = data['withdrawals'] ?? [];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to load transaction history';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Connection error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle bar
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // Sheet Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.receipt_long, color: Color(0xFF38BDF8), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'My Transactions',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                          )
                        : const Icon(Icons.refresh, color: Colors.white70, size: 20),
                    onPressed: _isLoading ? null : _fetchHistory,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),

            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF38BDF8).withOpacity(0.2),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: const Color(0xFF38BDF8),
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                tabs: [
                  Tab(text: 'All (${_deposits.length + _withdrawals.length})'),
                  Tab(text: 'Deposits (${_deposits.length})'),
                  Tab(text: 'Withdrawals (${_withdrawals.length})'),
                ],
              ),
            ),

            // Tab Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                              const SizedBox(height: 8),
                              Text(_errorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _fetchHistory,
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
                                child: const Text('Try Again', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildCombinedList(),
                            _buildDepositsList(),
                            _buildWithdrawalsList(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedList() {
    List<Map<String, dynamic>> combined = [];

    for (var d in _deposits) {
      combined.add({
        'type': 'DEPOSIT',
        'date': DateTime.tryParse(d['createdAt'] ?? '') ?? DateTime.now(),
        'data': d,
      });
    }

    for (var w in _withdrawals) {
      combined.add({
        'type': 'WITHDRAWAL',
        'date': DateTime.tryParse(w['createdAt'] ?? '') ?? DateTime.now(),
        'data': w,
      });
    }

    combined.sort((a, b) => b['date'].compareTo(a['date']));

    if (combined.isEmpty) {
      return _buildEmptyState('No transactions yet', 'Deposits and withdrawal requests will appear here.');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: combined.length,
      itemBuilder: (context, index) {
        final item = combined[index];
        if (item['type'] == 'DEPOSIT') {
          return _buildDepositCard(item['data']);
        } else {
          return _buildWithdrawalCard(item['data']);
        }
      },
    );
  }

  Widget _buildDepositsList() {
    if (_deposits.isEmpty) {
      return _buildEmptyState('No deposits found', 'Submit a deposit request to add credits to your wallet.');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _deposits.length,
      itemBuilder: (context, index) => _buildDepositCard(_deposits[index]),
    );
  }

  Widget _buildWithdrawalsList() {
    if (_withdrawals.isEmpty) {
      return _buildEmptyState('No withdrawals found', 'You have not submitted any withdrawal requests yet.');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _withdrawals.length,
      itemBuilder: (context, index) => _buildWithdrawalCard(_withdrawals[index]),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_toggle_off, color: Colors.white.withOpacity(0.2), size: 48),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepositCard(dynamic d) {
    final status = d['status'] ?? 'PENDING';
    final amount = (d['amount'] as num?)?.toDouble() ?? 0.0;
    final currency = d['currency'] ?? widget.currency.code;
    final method = (d['paymentMethod'] ?? 'MANUAL').toString().toUpperCase();
    final ref = d['referenceNumber'] ?? '';
    final createdAt = d['createdAt'] != null
        ? DateTime.tryParse(d['createdAt'])?.toLocal().toString().split('.')[0]
        : '';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (status == 'APPROVED') {
      statusColor = const Color(0xFF10B981);
      statusText = 'CREDITED';
      statusIcon = Icons.check_circle;
    } else if (status == 'REJECTED') {
      statusColor = Colors.redAccent;
      statusText = 'REJECTED';
      statusIcon = Icons.cancel;
    } else {
      statusColor = const Color(0xFFF59E0B);
      statusText = 'PENDING';
      statusIcon = Icons.access_time_filled;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.arrow_downward, color: Color(0xFF10B981), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Deposit ($method)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Text(
                '+$currency ${amount.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ref: $ref',
                style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'monospace'),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (createdAt != null && createdAt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              createdAt,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWithdrawalCard(dynamic w) {
    final status = w['status'] ?? 'PENDING';
    final amount = (w['amount'] as num?)?.toDouble() ?? 0.0;
    final currency = w['currency'] ?? widget.currency.code;
    final method = (w['method'] ?? 'PAYOUT').toString().toUpperCase();
    final note = w['adminNote'];
    final createdAt = w['createdAt'] != null
        ? DateTime.tryParse(w['createdAt'])?.toLocal().toString().split('.')[0]
        : '';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (status == 'PAID') {
      statusColor = const Color(0xFF10B981);
      statusText = 'PAID';
      statusIcon = Icons.check_circle;
    } else if (status == 'REJECTED') {
      statusColor = Colors.redAccent;
      statusText = 'REFUNDED';
      statusIcon = Icons.replay;
    } else {
      statusColor = const Color(0xFFF59E0B);
      statusText = 'PROCESSING';
      statusIcon = Icons.hourglass_top;
    }

    final payoutDetails = w['payoutDetails'];
    String destination = '';
    if (payoutDetails is Map) {
      if (payoutDetails['bankName'] != null) {
        destination = '${payoutDetails['bankName']} - ${payoutDetails['accountNumber'] ?? ''}';
      } else if (payoutDetails['mobileNumber'] != null) {
        destination = '${payoutDetails['mobileNumber']}';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.arrow_upward, color: Color(0xFFF43F5E), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Withdrawal ($method)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Text(
                '-$currency ${amount.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          if (destination.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'To: $destination',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (createdAt != null && createdAt.isNotEmpty)
                Text(
                  createdAt,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                )
              else
                const SizedBox(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (note != null && note.toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Note: $note',
                style: TextStyle(
                  color: status == 'REJECTED' ? Colors.redAccent.withOpacity(0.8) : Colors.white60,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
