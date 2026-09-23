import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/currency.dart';

class DepositSheet extends StatefulWidget {
  final Currency currency;
  final String authToken;
  final String serverBaseUrl;
  final VoidCallback? onDepositSubmitted;

  const DepositSheet({
    super.key,
    required this.currency,
    required this.authToken,
    required this.serverBaseUrl,
    this.onDepositSubmitted,
  });

  @override
  State<DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends State<DepositSheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _refController = TextEditingController();

  String _selectedChannel = 'ipay';
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<Map<String, dynamic>> _channels = [
    {
      'id': 'ipay',
      'name': 'iPay (Sri Lanka)',
      'badge': 'Instant QR / App',
      'accountNumber': 'IPAY-784210',
      'accountName': 'SkyRush Entertainment LK',
      'instructions': 'Open your iPay app, choose Pay Merchant, enter Merchant ID IPAY-784210, include your Gamer Tag as remark, and paste the transaction reference number below.',
      'icon': Icons.qr_code_scanner,
      'color': const Color(0xFF10B981),
    },
    {
      'id': 'upay',
      'name': 'UPay (Sri Lanka)',
      'badge': 'Mobile Transfer',
      'accountNumber': '077 123 4567',
      'accountName': 'SkyRush Official UPay',
      'instructions': 'Open your UPay app, send money to 0771234567 with your Gamer Tag in description, and copy the transaction reference number below.',
      'icon': Icons.phone_android,
      'color': const Color(0xFF8B5CF6),
    },
    {
      'id': 'bank_transfer',
      'name': 'Commercial Bank of Ceylon',
      'badge': 'Direct Bank / CDM',
      'accountNumber': '1000 2489 3104',
      'accountName': 'SkyRush Interactive LK (Pvt) Ltd',
      'instructions': 'Transfer via online banking or CDM. Bank: Commercial Bank, Kollupitiya Branch. Enter your Gamer Tag in the remark and submit the slip reference below.',
      'icon': Icons.account_balance,
      'color': const Color(0xFF3B82F6),
    },
  ];

  List<double> get _quickAmounts {
    if (widget.currency.code == 'USD') {
      return [5.0, 10.0, 25.0, 50.0, 100.0];
    }
    return [500.0, 1000.0, 2500.0, 5000.0, 10000.0];
  }

  @override
  void initState() {
    super.initState();
    _amountController.text = _quickAmounts[1].toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    super.dispose();
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard! 📋'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _submitDeposit() async {
    final amountText = _amountController.text.trim();
    final refText = _refController.text.trim();

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() {
        _errorMessage = 'Please enter a valid deposit amount';
      });
      return;
    }

    if (refText.isEmpty || refText.length < 3) {
      setState(() {
        _errorMessage = 'Please enter the transaction reference / slip ID';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('${widget.serverBaseUrl}/admin/deposit-request');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': widget.authToken,
          'amount': amount,
          'currency': widget.currency.code,
          'paymentMethod': _selectedChannel,
          'referenceNumber': refText,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (!mounted) return;
        Navigator.of(context).pop(); // close sheet

        // Show confirmation dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
                SizedBox(width: 10),
                Text('Deposit Submitted!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Amount: ${widget.currency.symbol}${amount.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Reference: $refText',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your deposit request has been placed in the verification queue. Once verified by our admin, your balance will automatically update in real-time!',
                  style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK, Got It'),
              ),
            ],
          ),
        );

        widget.onDepositSubmitted?.call();
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Failed to submit deposit request';
          _isSubmitting = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentChannel = _channels.firstWhere((c) => c['id'] == _selectedChannel);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.account_balance_wallet, color: Color(0xFF10B981), size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Deposit Funds',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Text(
              'Select your preferred payment method and submit the reference number.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 18),

            // Payment Methods Tabs
            const Text(
              'PAYMENT METHOD',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 10),
            Row(
              children: _channels.map((ch) {
                final isSelected = ch['id'] == _selectedChannel;
                final Color brandColor = ch['color'] as Color;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedChannel = ch['id'] as String;
                        _errorMessage = null;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? brandColor.withOpacity(0.18) : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? brandColor : Colors.white10,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(ch['icon'] as IconData, color: isSelected ? brandColor : Colors.white70, size: 22),
                          const SizedBox(height: 6),
                          Text(
                            ch['name'].toString().split(' ')[0],
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ch['badge'] as String,
                            style: TextStyle(
                              color: isSelected ? brandColor : Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            // Selected Channel Details Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (currentChannel['color'] as Color).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (currentChannel['color'] as Color).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        currentChannel['name'] as String,
                        style: TextStyle(
                          color: currentChannel['color'] as Color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      InkWell(
                        onTap: () => _copyToClipboard(
                          currentChannel['accountNumber'] as String,
                          'Account/Merchant ID',
                        ),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.copy, size: 12, color: Colors.white70),
                              SizedBox(width: 4),
                              Text('Copy', style: TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Account / ID: ${currentChannel['accountNumber']}',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                  Text(
                    'Name: ${currentChannel['accountName']}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const Divider(color: Colors.white10, height: 16),
                  Text(
                    currentChannel['instructions'] as String,
                    style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Quick Amount Selector
            const Text(
              'SELECT AMOUNT',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickAmounts.map((amt) {
                final isSelected = _amountController.text == amt.toStringAsFixed(0);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _amountController.text = amt.toStringAsFixed(0);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF10B981) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF10B981) : Colors.white12,
                      ),
                    ),
                    child: Text(
                      '${widget.currency.symbol}${amt.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Custom Amount Input
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Deposit Amount',
                labelStyle: const TextStyle(color: Colors.white54),
                prefixText: '${widget.currency.symbol} ',
                prefixStyle: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Reference Number Input
            TextField(
              controller: _refController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Transaction Reference / Slip ID',
                labelStyle: const TextStyle(color: Colors.white54),
                hintText: 'e.g. 7842109 or Bank Slip No',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                prefixIcon: const Icon(Icons.receipt_long, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                ),
                onPressed: _isSubmitting ? null : _submitDeposit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Submit Deposit for Verification',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
