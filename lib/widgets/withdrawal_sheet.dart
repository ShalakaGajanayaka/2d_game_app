import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/currency.dart';

class WithdrawalSheet extends StatefulWidget {
  final Currency currency;
  final double currentBalance;
  final String authToken;
  final String serverBaseUrl;
  final VoidCallback? onWithdrawalSubmitted;

  const WithdrawalSheet({
    super.key,
    required this.currency,
    required this.currentBalance,
    required this.authToken,
    required this.serverBaseUrl,
    this.onWithdrawalSubmitted,
  });

  @override
  State<WithdrawalSheet> createState() => _WithdrawalSheetState();
}

class _WithdrawalSheetState extends State<WithdrawalSheet> {
  final TextEditingController _amountController = TextEditingController();
  
  // Binance / USDT Controllers (Single Active Payout Method)
  final TextEditingController _binancePayIdController = TextEditingController();
  final TextEditingController _binanceNicknameController = TextEditingController();

  final String _selectedMethod = 'binance_usdt';
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _saveDetailsCheckbox = true;

  // Platform Exchange Rates (Base: USD / USDT = 1.0)
  static const Map<String, double> _platformExchangeRates = {
    'USD': 1.0,
    'USDT': 1.0,
    'LKR': 300.0,
    'INR': 85.0,
    'EUR': 0.92,
    'GBP': 0.79,
    'AED': 3.67,
  };

  double get _exchangeRate {
    final code = widget.currency.code.toUpperCase();
    return _platformExchangeRates[code] ?? 1.0;
  }

  // Minimum 7 USDT converted into the user's active currency
  double get _minAmountInUserCurrency {
    return 7.0 * _exchangeRate;
  }

  // Real-time USDT Equivalent based on user input
  double get _currentUsdtEquivalent {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (_exchangeRate <= 0) return 0.0;
    return amount / _exchangeRate;
  }

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onAmountChanged);

    // Initial default amount: minimum 7 USDT or available balance
    final minAmt = _minAmountInUserCurrency;
    if (widget.currentBalance > 0) {
      final initial = widget.currentBalance >= minAmt ? minAmt : widget.currentBalance;
      _amountController.text = initial >= 50
          ? initial.toStringAsFixed(0)
          : initial.toStringAsFixed(2);
    } else {
      _amountController.text = minAmt >= 50
          ? minAmt.toStringAsFixed(0)
          : minAmt.toStringAsFixed(2);
    }

    _loadSavedDetails();
  }

  void _onAmountChanged() {
    if (mounted) {
      setState(() {
        if (_errorMessage != null) _errorMessage = null;
      });
    }
  }

  Future<void> _loadSavedDetails() async {
    try {
      final res = await http.get(
        Uri.parse('${widget.serverBaseUrl}/auth/profile'),
        headers: {'Authorization': 'Bearer ${widget.authToken}'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        var details = data['savedWithdrawalDetails'];
        if (details is String) {
          try {
            details = jsonDecode(details);
          } catch (_) {}
        }

        if (mounted && details != null && details is Map) {
          setState(() {
            if (details['BINANCE'] != null) {
              final binance = details['BINANCE'];
              _binancePayIdController.text = binance['binancePayId'] ?? binance['accountNumber'] ?? '';
              _binanceNicknameController.text = binance['nickname'] ?? binance['accountHolder'] ?? '';
            } else if (details['binance_usdt'] != null) {
              final binance = details['binance_usdt'];
              _binancePayIdController.text = binance['binancePayId'] ?? binance['accountNumber'] ?? '';
              _binanceNicknameController.text = binance['nickname'] ?? binance['accountHolder'] ?? '';
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to load saved withdrawal details: $e');
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _binancePayIdController.dispose();
    _binanceNicknameController.dispose();
    super.dispose();
  }

  // Quick Chips representing 7 USDT, 15 USDT, 25 USDT, 50 USDT, 100 USDT
  List<double> get _quickAmounts {
    final rate = _exchangeRate;
    final usdtPresets = [7.0, 15.0, 25.0, 50.0, 100.0];
    return usdtPresets.map((usdt) {
      final val = usdt * rate;
      if (rate >= 50) {
        return (val / 10).round() * 10.0;
      } else if (rate >= 1) {
        return val.roundToDouble();
      } else {
        return double.parse(val.toStringAsFixed(2));
      }
    }).toList();
  }

  Future<void> _submitWithdrawal() async {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'Please enter a valid withdrawal amount');
      return;
    }

    if (amount > widget.currentBalance) {
      setState(() => _errorMessage =
          'Insufficient funds! Your balance is ${widget.currency.symbol}${widget.currentBalance.toStringAsFixed(2)}');
      return;
    }

    // Minimum 7 USDT validation
    final usdtAmount = amount / _exchangeRate;
    if (usdtAmount < 6.99) {
      setState(() => _errorMessage =
          'Minimum withdrawal is 7.00 USDT (approx ${widget.currency.symbol}${_minAmountInUserCurrency.toStringAsFixed(_minAmountInUserCurrency >= 50 ? 0 : 2)})');
      return;
    }

    // Validate Binance input
    final payId = _binancePayIdController.text.trim();
    final nickname = _binanceNicknameController.text.trim();

    if (payId.isEmpty) {
      setState(() => _errorMessage =
          'Please enter your Binance Pay ID or USDT (BEP20/TRC20) Wallet Address');
      return;
    }

    final Map<String, dynamic> payoutDetails = {
      'binancePayId': payId,
      'accountNumber': payId,
      'nickname': nickname.isNotEmpty ? nickname : 'Binance User',
      'accountHolder': nickname.isNotEmpty ? nickname : 'Binance User',
      'usdtAmount': usdtAmount.toStringAsFixed(2),
      'exchangeRate': _exchangeRate,
      'network': 'BINANCE_PAY / USDT',
    };

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('${widget.serverBaseUrl}/admin/withdrawal-request');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': widget.authToken,
          'amount': amount,
          'currency': widget.currency.code,
          'method': _selectedMethod,
          'payoutDetails': payoutDetails,
          'saveDetails': _saveDetailsCheckbox,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (!mounted) return;
        Navigator.of(context).pop();

        widget.onWithdrawalSubmitted?.call();

        // Show confirmation dialog with live USDT equivalent
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
                SizedBox(width: 10),
                Text(
                  'Request Submitted!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Amount Debited:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '${widget.currency.symbol}${amount.toStringAsFixed(2)}',
                      style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Expected Payout:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '≈ ${usdtAmount.toStringAsFixed(2)} USDT',
                      style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Destination:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      payId.length > 16 ? '${payId.substring(0, 14)}...' : payId,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    '🔒 Funds are placed in secure escrow. SkyRush Admin will verify and dispatch your USDT transfer within 15–30 minutes.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'OK, Got It',
                  style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Failed to submit withdrawal request';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final usdtEquiv = _currentUsdtEquivalent;
    final isBelowMin = usdtEquiv < 6.99 && _amountController.text.isNotEmpty;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grab handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title and Balance
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.arrow_upward_rounded, color: Color(0xFFF43F5E), size: 26),
                      SizedBox(width: 8),
                      Text(
                        'Withdraw Credits',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      'Avail: ${widget.currency.symbol}${widget.currentBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Active Payout Method Banner: Binance
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFF59E0B),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.currency_bitcoin, color: Color(0xFFFBBF24), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Binance / USDT (Crypto)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Fast Instant Payout • Min: 7 USDT',
                            style: TextStyle(color: Color(0xFFFBBF24), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle, color: Color(0xFFFBBF24), size: 20),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Amount Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Withdrawal Amount',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Min: 7 USDT (≈ ${widget.currency.symbol}${_minAmountInUserCurrency.toStringAsFixed(_minAmountInUserCurrency >= 50 ? 0 : 2)})',
                    style: TextStyle(
                      color: isBelowMin ? const Color(0xFFF87171) : const Color(0xFFFBBF24),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Amount Input Field
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBelowMin ? const Color(0xFFEF4444) : Colors.white12,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F172A),
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(11)),
                      ),
                      child: Text(
                        widget.currency.symbol,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          hintText: '0.00',
                          hintStyle: TextStyle(color: Colors.white24),
                          contentPadding: EdgeInsets.symmetric(horizontal: 14),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    // Max Button
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _amountController.text = widget.currentBalance >= 50
                              ? widget.currentBalance.toStringAsFixed(0)
                              : widget.currentBalance.toStringAsFixed(2);
                        });
                      },
                      child: const Text(
                        'MAX',
                        style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Real-Time Live USDT Conversion Display Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isBelowMin
                        ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.currency_exchange, color: Color(0xFFFBBF24), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'You will receive: ',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                '≈ ${usdtEquiv.toStringAsFixed(2)} USDT',
                                style: TextStyle(
                                  color: isBelowMin ? const Color(0xFFF87171) : const Color(0xFFFBBF24),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Platform Rate: 1 USDT = ${widget.currency.symbol}${_exchangeRate.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Quick Amount Preset Pills (Calibrated to 7, 15, 25, 50, 100 USDT)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ..._quickAmounts.map((amt) {
                    final isSelected = (double.tryParse(_amountController.text.trim()) ?? 0.0) == amt;
                    final usdtChipVal = (amt / _exchangeRate).round();
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _amountController.text = amt >= 50
                              ? amt.toStringAsFixed(0)
                              : amt.toStringAsFixed(2);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFF59E0B) : Colors.white12,
                          ),
                        ),
                        child: Text(
                          '${widget.currency.symbol}${amt >= 50 ? amt.toStringAsFixed(0) : amt.toStringAsFixed(2)} (~$usdtChipVal USDT)',
                          style: TextStyle(
                            color: isSelected ? const Color(0xFFFBBF24) : Colors.white70,
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 18),

              // Binance Payout Destination Form
              const Text(
                'Binance / USDT Payout Details',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              // Binance Pay ID or USDT Address Field
              _buildTextField(
                controller: _binancePayIdController,
                hint: 'Binance Pay ID (e.g. 548934240) or USDT BEP20/TRC20 Address',
                icon: Icons.account_balance_wallet,
              ),
              const SizedBox(height: 10),

              // Binance Nickname / Account Name (Optional)
              _buildTextField(
                controller: _binanceNicknameController,
                hint: 'Binance Nickname / Account Name (Optional)',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 10),

              // Fast Payout Notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.flash_on, color: Color(0xFFFBBF24), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Direct Crypto Transfer: Funds will be sent directly to your Binance Pay ID or USDT address within 15–30 minutes upon admin verification.',
                        style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Save Details Checkbox
              Material(
                color: Colors.transparent,
                child: Theme(
                  data: ThemeData(unselectedWidgetColor: Colors.white54),
                  child: CheckboxListTile(
                    value: _saveDetailsCheckbox,
                    activeColor: const Color(0xFFF59E0B),
                    checkColor: Colors.black,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Save Binance details for future withdrawals',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _saveDetailsCheckbox = val;
                        });
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Escrow notice banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.shield_outlined, color: Color(0xFF38BDF8), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Escrow Security: Balance is reserved upon submission. You can cancel pending withdrawals anytime in "My Transactions" to restore funds and continue playing.',
                        style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
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
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
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

              const SizedBox(height: 20),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitWithdrawal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF43F5E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Submit Withdrawal Request',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
          prefixIcon: Icon(icon, color: const Color(0xFFFBBF24), size: 18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
