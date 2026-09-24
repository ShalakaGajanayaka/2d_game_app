import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _branchNameController = TextEditingController();
  final TextEditingController _bankAccNumController = TextEditingController();
  final TextEditingController _bankAccHolderController = TextEditingController();
  
  final TextEditingController _ipayMobileController = TextEditingController();
  final TextEditingController _ipayHolderController = TextEditingController();
  
  final TextEditingController _upayMobileController = TextEditingController();
  final TextEditingController _upayHolderController = TextEditingController();

  String _selectedMethod = 'BANK'; // 'BANK', 'IPAY', 'UPAY'
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _saveDetailsCheckbox = true;

  final List<String> _sriLankaBanks = [
    'Commercial Bank of Ceylon',
    'Bank of Ceylon (BOC)',
    'People\'s Bank',
    'Hatton National Bank (HNB)',
    'Sampath Bank',
    'Seylan Bank',
    'Nations Trust Bank (NTB)',
    'DFCC Bank',
    'National Development Bank (NDB)',
    'Pan Asia Bank',
  ];

  @override
  void initState() {
    super.initState();
    _bankNameController.text = _sriLankaBanks[0];
    if (widget.currentBalance > 0) {
      _amountController.text = (widget.currentBalance >= 2500 ? 2500 : widget.currentBalance).toStringAsFixed(0);
    }
    _loadSavedDetails();
  }

  Future<void> _loadSavedDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          final savedMethod = prefs.getString('saved_withdrawal_method');
          if (savedMethod != null) _selectedMethod = savedMethod;

          final savedBank = prefs.getString('saved_bank_name');
          if (savedBank != null && _sriLankaBanks.contains(savedBank)) {
            _bankNameController.text = savedBank;
          }

          _bankAccNumController.text = prefs.getString('saved_bank_acc_num') ?? '';
          _bankAccHolderController.text = prefs.getString('saved_bank_acc_holder') ?? '';
          _branchNameController.text = prefs.getString('saved_bank_branch') ?? '';

          _ipayMobileController.text = prefs.getString('saved_ipay_mobile') ?? '';
          _ipayHolderController.text = prefs.getString('saved_ipay_holder') ?? '';

          _upayMobileController.text = prefs.getString('saved_upay_mobile') ?? '';
          _upayHolderController.text = prefs.getString('saved_upay_holder') ?? '';
        });
      }
    } catch (e) {
      debugPrint('Failed to load saved withdrawal details: $e');
    }
  }

  Future<void> _saveDetails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_withdrawal_method', _selectedMethod);
      await prefs.setString('saved_bank_name', _bankNameController.text);
      await prefs.setString('saved_bank_acc_num', _bankAccNumController.text);
      await prefs.setString('saved_bank_acc_holder', _bankAccHolderController.text);
      await prefs.setString('saved_bank_branch', _branchNameController.text);

      await prefs.setString('saved_ipay_mobile', _ipayMobileController.text);
      await prefs.setString('saved_ipay_holder', _ipayHolderController.text);

      await prefs.setString('saved_upay_mobile', _upayMobileController.text);
      await prefs.setString('saved_upay_holder', _upayHolderController.text);
    } catch (e) {
      debugPrint('Failed to save withdrawal details: $e');
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _bankNameController.dispose();
    _branchNameController.dispose();
    _bankAccNumController.dispose();
    _bankAccHolderController.dispose();
    _ipayMobileController.dispose();
    _ipayHolderController.dispose();
    _upayMobileController.dispose();
    _upayHolderController.dispose();
    super.dispose();
  }

  List<double> get _quickAmounts {
    if (widget.currency.code == 'USD') {
      return [25.0, 50.0, 100.0, 250.0];
    }
    return [2500.0, 5000.0, 10000.0, 25000.0];
  }

  Future<void> _submitWithdrawal() async {
    final amountText = _amountController.text.trim();
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'Please enter a valid withdrawal amount');
      return;
    }

    if (amount > widget.currentBalance) {
      setState(() => _errorMessage = 'Insufficient funds! Your balance is ${widget.currency.symbol}${widget.currentBalance.toStringAsFixed(2)}');
      return;
    }

    if (widget.currency.code == 'LKR' && amount < 2500) {
      setState(() => _errorMessage = 'Minimum withdrawal amount is LKR 2500.00');
      return;
    }

    Map<String, dynamic> payoutDetails = {};

    if (_selectedMethod == 'BANK') {
      final bank = _bankNameController.text.trim();
      final accNum = _bankAccNumController.text.trim();
      final holder = _bankAccHolderController.text.trim();
      final branch = _branchNameController.text.trim();

      if (bank.isEmpty || accNum.isEmpty || holder.isEmpty) {
        setState(() => _errorMessage = 'Please fill in Bank Name, Account Number and Account Holder');
        return;
      }

      payoutDetails = {
        'bankName': bank,
        'accountNumber': accNum,
        'accountHolder': holder,
        'branchName': branch,
      };
    } else if (_selectedMethod == 'IPAY') {
      final mobile = _ipayMobileController.text.trim();
      final holder = _ipayHolderController.text.trim();

      if (mobile.isEmpty || mobile.length < 9) {
        setState(() => _errorMessage = 'Please enter a valid IPAY mobile number');
        return;
      }

      payoutDetails = {
        'mobileNumber': mobile,
        'accountNumber': mobile,
        'accountHolder': holder.isNotEmpty ? holder : 'Wallet User',
      };
    } else {
      final mobile = _upayMobileController.text.trim();
      final holder = _upayHolderController.text.trim();

      if (mobile.isEmpty || mobile.length < 9) {
        setState(() => _errorMessage = 'Please enter a valid UPAY mobile number');
        return;
      }

      payoutDetails = {
        'mobileNumber': mobile,
        'accountNumber': mobile,
        'accountHolder': holder.isNotEmpty ? holder : 'Wallet User',
      };
    }

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
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (!mounted) return;
        if (_saveDetailsCheckbox) {
          await _saveDetails();
        }
        Navigator.of(context).pop(); // close sheet

        widget.onWithdrawalSubmitted?.call();

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
                Text('Request Submitted!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Withdrawn Amount: ${widget.currency.symbol}${amount.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Payout Method: ${_selectedMethod.toUpperCase()}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Text(
                    '🔒 Funds are currently held in escrow. Admin will process and transfer the funds to your account shortly. You will be notified live on screen.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK, Got It', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
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
        _errorMessage = 'Network error: Please check your connection';
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B132B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title and balance info
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
                      color: const Color(0xFF10B981).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
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

              // Method Tabs (Bank, iPay, UPay)
              Row(
                children: [
                  _buildMethodTab('BANK', 'Bank Transfer', Icons.account_balance, const Color(0xFF3B82F6)),
                  const SizedBox(width: 8),
                  _buildMethodTab('IPAY', 'iPay LK', Icons.qr_code_scanner, const Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  _buildMethodTab('UPAY', 'UPay LK', Icons.phone_android, const Color(0xFF8B5CF6)),
                ],
              ),
              const SizedBox(height: 16),

              // Amount Section
              const Text(
                'Withdrawal Amount',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
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
                          _amountController.text = widget.currentBalance.toStringAsFixed(2);
                        });
                      },
                      child: const Text('MAX', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Quick amount pills
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ..._quickAmounts.map((amt) {
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _amountController.text = amt.toStringAsFixed(0);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          '+${widget.currency.symbol}${amt.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 18),

              // Payout Destination Form
              if (_selectedMethod == 'BANK') ...[
                const Text(
                  'Bank Account Details',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                // Bank Picker Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sriLankaBanks.contains(_bankNameController.text)
                          ? _bankNameController.text
                          : _sriLankaBanks[0],
                      dropdownColor: const Color(0xFF1E293B),
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: _sriLankaBanks.map((b) {
                        return DropdownMenuItem<String>(
                          value: b,
                          child: Text(b),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _bankNameController.text = val);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Account Number
                _buildTextField(
                  controller: _bankAccNumController,
                  hint: 'Bank Account Number',
                  icon: Icons.numbers,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 10),

                // Account Holder Name
                _buildTextField(
                  controller: _bankAccHolderController,
                  hint: 'Account Holder Full Name',
                  icon: Icons.person,
                ),
                const SizedBox(height: 10),

                // Branch Name
                _buildTextField(
                  controller: _branchNameController,
                  hint: 'Branch Name (e.g. Kollupitiya, Kandy)',
                  icon: Icons.location_on,
                ),
              ] else ...[
                // iPay or UPay details
                Text(
                  '${_selectedMethod.toUpperCase()} Account Details',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _selectedMethod == 'IPAY' ? _ipayMobileController : _upayMobileController,
                  hint: 'Registered Mobile Number (e.g. 0771234567)',
                  icon: Icons.phone_android,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 10),
                _buildTextField(
                  controller: _selectedMethod == 'IPAY' ? _ipayHolderController : _upayHolderController,
                  hint: 'Wallet Account Holder Name',
                  icon: Icons.person,
                ),
              ],

              const SizedBox(height: 4),

              // Save Details Checkbox
              Theme(
                data: ThemeData(
                  unselectedWidgetColor: Colors.white54,
                ),
                child: CheckboxListTile(
                  value: _saveDetailsCheckbox,
                  activeColor: const Color(0xFF38BDF8),
                  checkColor: Colors.black,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'Save these details for future withdrawals',
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

              const SizedBox(height: 6),

              // Escrow notice banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.shield_outlined, color: Color(0xFF38BDF8), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Escrow Security: Balance is reserved upon submission. Once verified by admin, payment will be transferred. If rejected, your credits are refunded immediately.',
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
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.4)),
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

  Widget _buildMethodTab(String method, String label, IconData icon, Color color) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedMethod = method;
            _errorMessage = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.white10,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? color : Colors.white54, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
          prefixIcon: Icon(icon, color: Colors.white54, size: 18),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
