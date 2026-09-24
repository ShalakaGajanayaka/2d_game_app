import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/currency.dart';
import 'package:intl/intl.dart';

class BetHistorySheet extends StatefulWidget {
  final Currency currency;
  final String authToken;
  final String serverBaseUrl;

  const BetHistorySheet({
    super.key,
    required this.currency,
    required this.authToken,
    required this.serverBaseUrl,
  });

  @override
  State<BetHistorySheet> createState() => _BetHistorySheetState();
}

class _BetHistorySheetState extends State<BetHistorySheet> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _betHistory = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('${widget.serverBaseUrl}/auth/bet-history');
      final res = await http.get(url, headers: {
        'Authorization': 'Bearer ${widget.authToken}'
      });

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _betHistory = data ?? [];
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to load bet history. Status: ${res.statusCode}\n${res.body}';
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
                      Icon(Icons.history, color: Color(0xFF38BDF8), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'My Bet History',
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
            const SizedBox(height: 12),

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
                      : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_betHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.inbox, size: 48, color: Colors.white24),
            SizedBox(height: 12),
            Text('No bets yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
            SizedBox(height: 4),
            Text('Your betting history will appear here.', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _betHistory.length,
      itemBuilder: (context, index) {
        final item = _betHistory[index];
        final betAmount = double.tryParse(item['betAmount'].toString()) ?? 0.0;
        final winAmount = double.tryParse(item['winAmount'].toString()) ?? 0.0;
        final crashPoint = double.tryParse(item['crashPoint'].toString()) ?? 1.0;
        final cashOutMultiplier = item['cashOutMultiplier'] != null ? double.tryParse(item['cashOutMultiplier'].toString()) : null;
        
        final isWin = winAmount > 0;
        final date = DateTime.tryParse(item['createdAt'] ?? '') ?? DateTime.now();
        final currency = item['currency'] ?? 'LKR';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isWin ? Colors.greenAccent.withOpacity(0.3) : Colors.redAccent.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isWin ? Colors.greenAccent.withOpacity(0.1) : Colors.redAccent.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isWin ? Icons.arrow_upward : Icons.arrow_downward,
                          color: isWin ? Colors.greenAccent : Colors.redAccent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isWin ? 'Cashed Out' : 'Crashed',
                            style: TextStyle(
                              color: isWin ? Colors.greenAccent : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('MMM d, yyyy • h:mm a').format(date),
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isWin ? '+$currency ${winAmount.toStringAsFixed(2)}' : '-$currency ${betAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isWin ? Colors.greenAccent : Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Bet: $currency ${betAmount.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Colors.white12, height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn('Crash Point', '${crashPoint.toStringAsFixed(2)}x', Colors.white70),
                  _buildStatColumn(
                    'Cash Out', 
                    cashOutMultiplier != null ? '${cashOutMultiplier.toStringAsFixed(2)}x' : '-', 
                    isWin ? Colors.greenAccent : Colors.white54
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatColumn(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }
}
