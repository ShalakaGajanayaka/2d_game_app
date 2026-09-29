import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/currency.dart';

class CurrencySelectorSheet extends StatefulWidget {
  final Currency currentCurrency;
  final double currentBalance;
  final String authToken;
  final String serverBaseUrl;
  final Function(Currency newCurrency, double newBalance) onCurrencyChanged;

  const CurrencySelectorSheet({
    super.key,
    required this.currentCurrency,
    required this.currentBalance,
    required this.authToken,
    required this.serverBaseUrl,
    required this.onCurrencyChanged,
  });

  @override
  State<CurrencySelectorSheet> createState() => _CurrencySelectorSheetState();
}

class _CurrencySelectorSheetState extends State<CurrencySelectorSheet> {
  late String _selectedCode;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Fallback / standard client-side rates for instantaneous live preview
  final Map<String, double> _rates = {
    'USD': 1.0,
    'USDT': 1.0,
    'LKR': 300.0,
    'INR': 85.0,
    'EUR': 0.92,
    'GBP': 0.79,
    'AED': 3.67,
  };

  final List<Currency> _selectableCurrencies = [
    const Currency(code: 'USD', name: 'US Dollar (USDT)', symbol: '\$', flag: '🇺🇸'),
    const Currency(code: 'INR', name: 'Indian Rupee', symbol: '₹', flag: '🇮🇳'),
    const Currency(code: 'EUR', name: 'Euro', symbol: '€', flag: '🇪🇺'),
    const Currency(code: 'GBP', name: 'British Pound', symbol: '£', flag: '🇬🇧'),
    const Currency(code: 'AED', name: 'UAE Dirham', symbol: 'AED', flag: '🇦🇪'),
    const Currency(code: 'LKR', name: 'Sri Lankan Rupee', symbol: 'Rs', flag: '🇱🇰'),
  ];

  @override
  void initState() {
    super.initState();
    // Default preview target: prioritize USD as first option, or fallback smoothly
    final cur = widget.currentCurrency.code.toUpperCase();
    _selectedCode = (cur == 'USD') ? 'LKR' : 'USD';
    _fetchLiveRates();
  }

  Future<void> _fetchLiveRates() async {
    try {
      final res = await http.get(Uri.parse('${widget.serverBaseUrl}/auth/exchange-rates'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['rates'] != null && mounted) {
          setState(() {
            final Map<String, dynamic> r = data['rates'];
            r.forEach((k, v) {
              if (v is num) _rates[k.toUpperCase()] = v.toDouble();
            });
          });
        }
      }
    } catch (_) {}
  }

  double _estimateConverted(double amount, String from, String to) {
    if (from == to) return amount;
    final fromRate = _rates[from] ?? 1.0;
    final toRate = _rates[to] ?? 1.0;
    final raw = (amount / fromRate) * toRate;
    return (raw * 100).floorToDouble() / 100.0;
  }

  String _formatRate(String from, String to) {
    if (from == to) return '1:1';
    final fromRate = _rates[from] ?? 1.0;
    final toRate = _rates[to] ?? 1.0;
    final rate = toRate / fromRate;
    return '1 $from = ${rate.toStringAsFixed(rate >= 1 ? 2 : 4)} $to';
  }

  Future<void> _handleConfirm() async {
    if (_selectedCode == widget.currentCurrency.code.toUpperCase()) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${widget.serverBaseUrl}/auth/change-currency'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.authToken}',
        },
        body: jsonEncode({
          'targetCurrency': _selectedCode,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        final newCur = Currency.getByCode(_selectedCode);
        final newBal = (data['newBalance'] as num?)?.toDouble() ??
            _estimateConverted(widget.currentBalance, widget.currentCurrency.code.toUpperCase(), _selectedCode);

        if (!mounted) return;
        Navigator.of(context).pop();

        widget.onCurrencyChanged(newCur, newBal);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Switched to ${newCur.flag} ${newCur.code}! New Balance: ${newCur.symbol}${newBal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Failed to switch currency';
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
    final curCode = widget.currentCurrency.code.toUpperCase();
    final targetCurrency = Currency.getByCode(_selectedCode);
    final convertedAmount = _estimateConverted(widget.currentBalance, curCode, _selectedCode);

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

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.currency_exchange, color: Color(0xFF38BDF8), size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Change Account Currency',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
              'Switch your game wallet currency. Your active balance will be converted using official platform exchange rates.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 18),

            // Current Balance Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CURRENT WALLET',
                        style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(widget.currentCurrency.flag, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text(
                            widget.currentCurrency.code,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'BALANCE',
                        style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.currentCurrency.symbol}${widget.currentBalance.toStringAsFixed(2)}',
                        style: const TextStyle(color: Color(0xFF10B981), fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Currency Options List
            const Text(
              'SELECT TARGET CURRENCY',
              style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectableCurrencies.map((c) {
                final isCurrent = c.code == curCode;
                final isSelected = c.code == _selectedCode;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCode = c.code;
                      _errorMessage = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.16)
                          : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF38BDF8) : Colors.white10,
                        width: isSelected ? 1.8 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(c.flag, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.code,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              isCurrent ? 'Current' : c.symbol,
                              style: TextStyle(
                                color: isCurrent
                                    ? const Color(0xFF10B981)
                                    : (isSelected ? const Color(0xFF38BDF8) : Colors.white38),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            // Live Conversion Preview Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'CONVERSION PREVIEW',
                        style: TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _formatRate(curCode, _selectedCode),
                        style: const TextStyle(color: Colors.white54, fontSize: 10, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${widget.currentCurrency.symbol}${widget.currentBalance.toStringAsFixed(2)} ($curCode)',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                      const Icon(Icons.arrow_forward, color: Color(0xFFFBBF24), size: 16),
                      Text(
                        '${targetCurrency.symbol}${convertedAmount.toStringAsFixed(2)} (${targetCurrency.code})',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Safety Warning Notice
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.shield_outlined, color: Colors.white54, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fair Play Protection: Currency cannot be changed while an active plane bet is in flight. After switching, bet presets will adapt to the new currency.',
                      style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
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

            const SizedBox(height: 18),

            // Confirm Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (_selectedCode == curCode)
                      ? const Color(0xFF334155)
                      : const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: (_isSubmitting || _selectedCode == curCode) ? null : _handleConfirm,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _selectedCode == curCode
                                ? 'Already on $curCode'
                                : 'Confirm & Switch to $_selectedCode',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
