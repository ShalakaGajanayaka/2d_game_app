import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/game_state.dart';
import '../models/currency.dart';
import '../widgets/plane_graph.dart';
import '../widgets/sky_clouds_background.dart';
import '../widgets/currency_picker_sheet.dart';
import '../models/country_code.dart';
import '../widgets/country_code_picker_sheet.dart';
import '../widgets/deposit_sheet.dart';
import '../widgets/withdrawal_sheet.dart';
import '../widgets/transaction_history_sheet.dart';
import '../widgets/bet_history_sheet.dart';
import '../models/live_bets_adapter.dart';
import '../services/fullscreen_service.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  GameStatus _status = GameStatus.waiting;
  
  double _balance = 1000.0;
  Currency _userCurrency = (DateTime.now().timeZoneOffset.inMinutes == 330 ||
          DateTime.now().timeZoneName.toUpperCase().contains('COLOMBO'))
      ? Currency.getByCode('LKR')
      : Currency.defaultCurrency;
  bool _isLoggedIn = false;
  Map<String, dynamic>? _currentUser;
  String? _authToken;
  
  // Bet 1
  double _betAmount1 = 50.0;
  final TextEditingController _betController1 = TextEditingController(text: '50.00');
  bool _isBetPlaced1 = false;
  double _cashedOutMultiplier1 = 0.0;
  bool _hasCashedOut1 = false;
  bool _isSubmittingBet1 = false;
  bool _isPressedBet1 = false;

  // Bet 2
  double _betAmount2 = 50.0;
  final TextEditingController _betController2 = TextEditingController(text: '50.00');
  bool _isBetPlaced2 = false;
  double _cashedOutMultiplier2 = 0.0;
  bool _hasCashedOut2 = false;
  bool _isSubmittingBet2 = false;
  bool _isPressedBet2 = false;
  
  double _currentMultiplier = 1.0;
  final ValueNotifier<double> _multiplierNotifier = ValueNotifier<double>(1.0);
  final List<double> _history = [];
  final bool _showHistoryBar = false; // Set to true to show history bar again
  List<Map<String, dynamic>> _liveBets = [];
  final Set<String> _recentlyCashedOut = {};
  bool _isConnected = false;
  
  late AnimationController _controller;
  int _countdown = 10;
  final ValueNotifier<int> _countdownNotifier = ValueNotifier<int>(10);
  double _serverClockOffset = 0.0;
  double _targetStartTime = 0.0;
  Timer? _localCountdownTimer;
  Timer? _clockSyncTimer;
  
  bool _showFloatingWin = false;
  double _floatingWinAmount = 0.0;
  double _floatingWinMultiplier = 0.0;
  int _floatingWinKey = 0;
  Timer? _floatingWinTimer;
  
  late IO.Socket socket;
  double _serverStartTime = 0;
  
  bool _showZeroBalanceDeposit = false;
  Timer? _zeroBalanceToggleTimer;

  void _startLocalCountdownTimer(double targetStartEpoch) {
    _targetStartTime = targetStartEpoch;
    _localCountdownTimer?.cancel();
    
    // Smoothly tick every 100ms to calculate exact remaining whole seconds
    _localCountdownTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _status != GameStatus.waiting) {
        timer.cancel();
        return;
      }
      final double syncedNow = DateTime.now().millisecondsSinceEpoch + _serverClockOffset;
      final double remainingMs = _targetStartTime - syncedNow;
      final int newCountdown = max(0, (remainingMs / 1000.0).ceil());
      if (_countdownNotifier.value != newCountdown) {
        _countdownNotifier.value = newCountdown;
        _countdown = newCountdown;
      }
      if (remainingMs <= 0) {
        timer.cancel();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    
    _zeroBalanceToggleTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && _isLoggedIn && _balance == 0) {
        setState(() {
          _showZeroBalanceDeposit = !_showZeroBalanceDeposit;
        });
      } else if (mounted && _showZeroBalanceDeposit) {
        setState(() {
          _showZeroBalanceDeposit = false;
        });
      }
    });
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 100), 
    )..addListener(() {
        if (_status == GameStatus.playing || _status == GameStatus.spectating) {
          final double syncedServerEpoch = DateTime.now().millisecondsSinceEpoch + _serverClockOffset;
          final double elapsedSeconds = max(0.0, (syncedServerEpoch - _serverStartTime) / 1000.0);
          // Industry standard smooth exponential progression: e^(0.095 * t) (~7.3s to reach 2.00x)
          final double nextMultiplier = max(1.0, exp(0.095 * elapsedSeconds));
          _currentMultiplier = nextMultiplier;
          _multiplierNotifier.value = nextMultiplier;
        }
    });

    _initSocket();
    _detectGeoCurrency();
    _tryAutoLogin();
  }

  String _getServerBaseUrl() {
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.contains('skyrush.cc')) {
        return '${Uri.base.scheme}://engine.skyrush.cc';
      }
      if (host != 'localhost' && host != '127.0.0.1' && host.isNotEmpty) {
        return Uri.base.origin;
      }
    }
    String serverUrl = dotenv.env['SERVER_API_URL'] ?? 'http://localhost:3000';
    if (!kIsWeb && Platform.isAndroid) {
      serverUrl = serverUrl.replaceFirst('localhost', '10.0.2.2');
      serverUrl = serverUrl.replaceFirst('127.0.0.1', '10.0.2.2');
    }
    return serverUrl;
  }

  Future<void> _detectGeoCurrency() async {
    try {
      // Tier 1: Instant zero-latency Timezone detection (no network delay)
      try {
        final tzName = DateTime.now().timeZoneName.toUpperCase();
        final tzOffsetMin = DateTime.now().timeZoneOffset.inMinutes;

        // Sri Lanka is UTC+05:30 (offset = 330 minutes)
        if (tzOffsetMin == 330 || tzName.contains('COLOMBO') || tzName.contains('LK') || tzName.contains('+05:30')) {
          if (mounted && !_isLoggedIn) {
            setState(() {
              _userCurrency = Currency.getByCode('LKR');
            });
          }
        }
      } catch (_) {}

      // Tier 2: Query NestJS Backend Geo-IP endpoint with timezone context
      bool backendResolved = false;
      try {
        final tzName = DateTime.now().timeZoneName;
        final tzOffsetMin = DateTime.now().timeZoneOffset.inMinutes;
        final url = Uri.parse(
          '${_getServerBaseUrl()}/auth/detect-currency?tz=${Uri.encodeComponent(tzName)}&offset=$tzOffsetMin',
        );
        final res = await http.get(url).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final isLocal = data['isLocal'] == true;
          final currencyCode = data['currency'] as String?;

          if (currencyCode != null && currencyCode.isNotEmpty) {
            if (mounted && !_isLoggedIn) {
              setState(() {
                _userCurrency = Currency.getByCode(currencyCode);
              });
            }
            if (!isLocal) {
              backendResolved = true;
            }
          }
        }
      } catch (e) {
        debugPrint('Backend detect-currency notice: $e');
      }

      // Tier 3: Edge fallback for Web / localhost dev where backend only sees loopback IP
      if (!backendResolved) {
        try {
          final edgeRes = await http.get(Uri.parse('https://api.country.is')).timeout(const Duration(seconds: 3));
          if (edgeRes.statusCode == 200) {
            final data = jsonDecode(edgeRes.body);
            final country = data['country'] as String?;
            if (country != null && country.isNotEmpty) {
              final mappedCurCode = CountryCode.fromCountryCode(country).currencyCode;
              if (mounted && !_isLoggedIn) {
                setState(() {
                  _userCurrency = Currency.getByCode(mappedCurCode);
                });
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Geo-currency overall detection notice: $e');
    }
  }

  Future<void> _syncBalanceToServer({double? winDelta, double? mult}) async {
    // Deprecated: Betting, payouts, and balances are 100% server-authoritative
  }

  Future<void> _tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('skyrush_auth_token');
      if (savedToken == null || savedToken.isEmpty) return;

      final url = Uri.parse('${_getServerBaseUrl()}/auth/profile');
      final res = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $savedToken',
        },
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        final userProfile = jsonDecode(res.body);
        setState(() {
          _isLoggedIn = true;
          _authToken = savedToken;
          _currentUser = Map<String, dynamic>.from(userProfile);
          _balance = (_currentUser!['balance'] as num).toDouble();
          if (_currentUser!['currency'] != null) {
            _userCurrency = Currency.getByCode(_currentUser!['currency']);
          }

          // Restore any active bets in case user reloaded while countdown or flight was active
          if (userProfile['activeBets'] != null) {
            final slot1 = userProfile['activeBets']['slot1'];
            if (slot1 != null) {
              _isBetPlaced1 = true;
              _betAmount1 = (slot1['amount'] as num).toDouble();
              _betController1.text = _betAmount1 % 1 == 0 ? _betAmount1.toInt().toString() : _betAmount1.toStringAsFixed(2);
            }
            final slot2 = userProfile['activeBets']['slot2'];
            if (slot2 != null) {
              _isBetPlaced2 = true;
              _betAmount2 = (slot2['amount'] as num).toDouble();
              _betController2.text = _betAmount2 % 1 == 0 ? _betAmount2.toInt().toString() : _betAmount2.toStringAsFixed(2);
            }
          }
        });
        debugPrint('[Auth] Auto-login successfully restored session for ${_currentUser?['username']} (Balance: $_balance)');
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        debugPrint('[Auth] Saved token expired or invalid. Clearing session.');
        await prefs.remove('skyrush_auth_token');
      }
    } catch (e) {
      debugPrint('[Auth] Auto-login error: $e');
    }
  }

  Future<Map<String, dynamic>> _loginUser(String identifier, String password) async {
    try {
      final url = Uri.parse('${_getServerBaseUrl()}/auth/login');
      final isEmail = identifier.contains('@');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (isEmail) 'email': identifier.trim() else 'username': identifier.trim(),
          'password': password,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final token = data['token']?.toString();
        if (token != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('skyrush_auth_token', token);
          } catch (e) {
            debugPrint('[Auth] Error persisting token: $e');
          }
        }
        setState(() {
          _isLoggedIn = true;
          _authToken = token;
          _currentUser = Map<String, dynamic>.from(data['user']);
          _balance = (_currentUser!['balance'] as num).toDouble();
          _userCurrency = Currency.getByCode(_currentUser!['currency']);
        });
        return {'success': true, 'user': data['user']};
      } else {
        final msg = data['message'] is List ? (data['message'] as List).join(', ') : data['message'].toString();
        return {'success': false, 'message': msg};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> _registerUser(String identifier, String password, [String? currency]) async {
    try {
      final url = Uri.parse('${_getServerBaseUrl()}/auth/register');
      final isEmail = identifier.contains('@');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (isEmail) 'email': identifier.trim() else 'username': identifier.trim(),
          'password': password,
          'currency': currency ?? 'LKR',
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final token = data['token']?.toString();
        if (token != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('skyrush_auth_token', token);
          } catch (e) {
            debugPrint('[Auth] Error persisting token: $e');
          }
        }
        setState(() {
          _isLoggedIn = true;
          _authToken = token;
          _currentUser = Map<String, dynamic>.from(data['user']);
          _balance = (_currentUser!['balance'] as num).toDouble();
          _userCurrency = Currency.getByCode(_currentUser!['currency']);
        });
        return {'success': true, 'user': data['user']};
      } else {
        final msg = data['message'] is List ? (data['message'] as List).join(', ') : data['message'].toString();
        return {'success': false, 'message': msg};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> _requestResetOtp(String identifier) async {
    try {
      final url = Uri.parse('${_getServerBaseUrl()}/auth/forgot-password/request-otp');
      final isEmail = identifier.contains('@');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (isEmail) 'email': identifier.trim() else 'phoneNumber': identifier.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return {'success': true, 'devOtp': data['devOtp'], 'message': data['message']};
      } else {
        final msg = data['message'] is List ? (data['message'] as List).join(', ') : data['message'].toString();
        return {'success': false, 'message': msg};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> _resetPassword(String identifier, String otp, String newPassword) async {
    try {
      final url = Uri.parse('${_getServerBaseUrl()}/auth/forgot-password/reset');
      final isEmail = identifier.contains('@');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (isEmail) 'email': identifier.trim() else 'phoneNumber': identifier.trim(),
          'otp': otp,
          'newPassword': newPassword,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        final token = data['token']?.toString();
        if (token != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('skyrush_auth_token', token);
          } catch (e) {
            debugPrint('[Auth] Error persisting token: $e');
          }
        }
        setState(() {
          _isLoggedIn = true;
          _authToken = token;
          _currentUser = Map<String, dynamic>.from(data['user']);
          _balance = (_currentUser!['balance'] as num).toDouble();
          _userCurrency = Currency.getByCode(_currentUser!['currency']);
        });
        return {'success': true, 'message': data['message'], 'user': data['user']};
      } else {
        final msg = data['message'] is List ? (data['message'] as List).join(', ') : data['message'].toString();
        return {'success': false, 'message': msg};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  void _logoutUser() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('skyrush_auth_token');
    }).catchError((_) {});

    setState(() {
      _isLoggedIn = false;
      _authToken = null;
      _currentUser = null;
      _balance = 1000.0;
    });
    _detectGeoCurrency();
  }

  void _initSocket() {
    String serverUrl = _getServerBaseUrl();

    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    
    socket.onConnect((_) {
      if (mounted) setState(() => _isConnected = true);
      // Immediately perform Clock Synchronization Handshake with Server
      socket.emit('pingSync', {'clientSendTime': DateTime.now().millisecondsSinceEpoch});
    });

    socket.onDisconnect((_) {
      if (mounted) setState(() => _isConnected = false);
    });

    socket.on('pongSync', (data) {
      final int t1 = DateTime.now().millisecondsSinceEpoch;
      final int t0 = (data['clientSendTime'] as num?)?.toInt() ?? t1;
      final int serverReceive = (data['serverReceiveTime'] as num?)?.toInt() ?? t1;
      final int rtt = t1 - t0;
      final double estimatedServerTime = serverReceive + (rtt / 2.0);
      final double newOffset = estimatedServerTime - t1;

      if (_serverClockOffset == 0.0) {
        _serverClockOffset = newOffset;
      } else {
        _serverClockOffset = (_serverClockOffset * 0.7) + (newOffset * 0.3);
      }
    });

    _clockSyncTimer?.cancel();
    _clockSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isConnected) {
        socket.emit('pingSync', {'clientSendTime': DateTime.now().millisecondsSinceEpoch});
      }
    });

    socket.on('flightSync', (data) {
      if (!mounted) return;
      final double serverMultiplier = (data['multiplier'] as num?)?.toDouble() ?? 1.0;
      final double? serverStartTime = (data['startTime'] as num?)?.toDouble();
      if (serverStartTime != null) {
        _serverStartTime = serverStartTime;
      }

      // If client was still stuck in waiting due to a dropped/delayed start packet, immediately transition!
      if (_status == GameStatus.waiting) {
        _localCountdownTimer?.cancel();
        setState(() {
          _status = (_isBetPlaced1 || _isBetPlaced2) ? GameStatus.playing : GameStatus.spectating;
          _controller.repeat();
        });
      }

      // Soft convergence towards authoritative server multiplier
      if (_status == GameStatus.playing || _status == GameStatus.spectating) {
        final diff = serverMultiplier - _currentMultiplier;
        if (diff.abs() > 0.12) {
          final nudged = _currentMultiplier + (diff * 0.4);
          _currentMultiplier = nudged;
          _multiplierNotifier.value = nudged;
        }
      }
    });
    
    socket.connect();
    
    socket.on('gameState', (data) {
      if (!mounted) return;
      
      final serverStatus = data['status'];
      final serverCountdown = (data['countdown'] as num?)?.toInt() ?? 10;
      final serverTargetStartTime = (data['targetStartTime'] as num?)?.toDouble();

      if (serverStatus == 'waiting') {
        if (serverTargetStartTime != null && serverTargetStartTime > 0) {
          _startLocalCountdownTimer(serverTargetStartTime);
        } else {
          final double syncedNow = DateTime.now().millisecondsSinceEpoch + _serverClockOffset;
          _startLocalCountdownTimer(syncedNow + (serverCountdown * 1000));
        }
      }

      setState(() {
        _countdown = _countdownNotifier.value;
        
        if (data['bets'] != null) {
          final incomingBets = List<Map<String, dynamic>>.from(
            (data['bets'] as List).map((b) => Map<String, dynamic>.from(b)),
          );
          if (serverStatus == 'waiting' && _status != GameStatus.waiting) {
            _liveBets = incomingBets;
            _recentlyCashedOut.clear();
          } else if (_liveBets.isEmpty) {
            _liveBets = incomingBets;
          } else {
            for (var b in incomingBets) {
              final idx = _liveBets.indexWhere((existing) => existing['id'] == b['id']);
              if (idx != -1) {
                _liveBets[idx]['cashedOut'] = b['cashedOut'];
                if (b['cashedOutMultiplier'] != null) {
                  _liveBets[idx]['cashedOutMultiplier'] = b['cashedOutMultiplier'];
                }
              } else {
                _liveBets.add(b);
              }
            }
          }
        }
        
        GameStatus newStatus;
        if (serverStatus == 'waiting') {
           newStatus = GameStatus.waiting;
        } else if (serverStatus == 'playing') {
           newStatus = (_isBetPlaced1 || _isBetPlaced2) ? GameStatus.playing : GameStatus.spectating;
        } else {
           newStatus = GameStatus.crashed;
        }

        if (_status != newStatus) {
           if (serverStatus == 'playing' && _status == GameStatus.waiting) {
              _localCountdownTimer?.cancel();
              _serverStartTime = (data['startTime'] as num?)?.toDouble() ?? 
                  (DateTime.now().millisecondsSinceEpoch + _serverClockOffset);
              _currentMultiplier = 1.0;
              _multiplierNotifier.value = 1.0;
              _controller.repeat();
           } 
           else if (newStatus == GameStatus.crashed) {
              _localCountdownTimer?.cancel();
              _controller.stop();
              _floatingWinTimer?.cancel();
              _showFloatingWin = false;
              _currentMultiplier = (data['crashPoint'] ?? data['currentMultiplier'])?.toDouble() ?? 1.0;
              _multiplierNotifier.value = _currentMultiplier;
              _history.insert(0, _currentMultiplier);
              if (_history.length > 20) {
                 _history.removeLast();
              }

              if (_isBetPlaced1) {
                double winAmt = _hasCashedOut1 ? (_betAmount1 * _cashedOutMultiplier1) : 0.0;
                _saveBetHistory(_betAmount1, _hasCashedOut1 ? _cashedOutMultiplier1 : null, _currentMultiplier, winAmt);
              }
              if (_isBetPlaced2) {
                double winAmt = _hasCashedOut2 ? (_betAmount2 * _cashedOutMultiplier2) : 0.0;
                _saveBetHistory(_betAmount2, _hasCashedOut2 ? _cashedOutMultiplier2 : null, _currentMultiplier, winAmt);
              }

              _isBetPlaced1 = false;
              _isBetPlaced2 = false;
              _hasCashedOut1 = false;
              _hasCashedOut2 = false;
              _isSubmittingBet1 = false;
              _isSubmittingBet2 = false;
              _isPressedBet1 = false;
              _isPressedBet2 = false;
           }
           else if (newStatus == GameStatus.waiting) {
              _controller.stop();
              _currentMultiplier = 1.0;
              _multiplierNotifier.value = 1.0;
              _hasCashedOut1 = false;
              _hasCashedOut2 = false;
              _isSubmittingBet1 = false;
              _isSubmittingBet2 = false;
              _isPressedBet1 = false;
              _isPressedBet2 = false;
           }
           _status = newStatus;
        }
      });
    });

    socket.on('newLiveBet', (data) {
      if (!mounted) return;
      final newBet = Map<String, dynamic>.from(data as Map);
      setState(() {
        final exists = _liveBets.any((b) => b['id'] == newBet['id']);
        if (!exists) {
          _liveBets.add(newBet);
        }
      });
    });

    socket.on('newLiveBetsBatch', (data) {
      if (!mounted) return;
      final rawList = data as List;
      final batch = rawList.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      setState(() {
        for (var newBet in batch) {
          final exists = _liveBets.any((b) => b['id'] == newBet['id']);
          if (!exists) {
            _liveBets.add(newBet);
          }
        }
      });
    });

    socket.on('betCashedOut', (data) {
      if (!mounted) return;
      final botId = data['id']?.toString();
      final mult = (data['multiplier'] as num?)?.toDouble() ?? 1.0;
      final win = (data['winAmount'] as num?)?.toDouble() ?? 0.0;
      
      if (botId != null) {
        setState(() {
          final index = _liveBets.indexWhere((b) => b['id'] == botId);
          if (index != -1) {
            _liveBets[index]['cashedOut'] = true;
            _liveBets[index]['cashedOutMultiplier'] = mult;
            _liveBets[index]['winAmount'] = win;
            _recentlyCashedOut.add(botId);
          }
        });

        Timer(const Duration(milliseconds: 1800), () {
          if (mounted) {
            setState(() {
              _recentlyCashedOut.remove(botId);
            });
          }
        });
      }
    });

    socket.on('userBalanceUpdated', (data) {
      if (!mounted) return;
      final targetUser = data['username']?.toString()?.toLowerCase();
      final myUser = _currentUser?['username']?.toString()?.toLowerCase() ??
          _currentUser?['email']?.toString()?.toLowerCase();

      if (myUser != null && targetUser != null && targetUser == myUser) {
        final newBal = (data['balance'] as num?)?.toDouble();
        final msg = data['message'] as String? ?? 'Wallet balance updated! 💰';
        if (newBal != null) {
          setState(() {
            _balance = newBal;
            if (_currentUser != null) {
              _currentUser!['balance'] = newBal;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      msg,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });
  }

  Future<void> _toggleBet(int betIndex) async {
    FocusManager.instance.primaryFocus?.unfocus();
    
    if (!_isLoggedIn || _authToken == null) {
      _showAuthDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in or register to place bets! ✈️'),
          backgroundColor: Color(0xFF38BDF8),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_status == GameStatus.waiting) {
      // Guard against rapid multi-click debounce while request in flight
      if ((betIndex == 1 && _isSubmittingBet1) || (betIndex == 2 && _isSubmittingBet2)) {
        return;
      }

      double currentBet = betIndex == 1 ? _betAmount1 : _betAmount2;
      bool isPlaced = betIndex == 1 ? _isBetPlaced1 : _isBetPlaced2;
      TextEditingController controller = betIndex == 1 ? _betController1 : _betController2;
      
      final parsed = double.tryParse(controller.text);
      if (parsed != null && parsed > 0) {
        currentBet = parsed;
      }

      if (isPlaced) {
        // --- 0ms OPTIMISTIC CANCEL BET ---
        final double previousBalance = _balance;
        setState(() {
          if (betIndex == 1) {
            _isSubmittingBet1 = true;
            _isBetPlaced1 = false;
            _betAmount1 = currentBet;
          } else {
            _isSubmittingBet2 = true;
            _isBetPlaced2 = false;
            _betAmount2 = currentBet;
          }
          _balance += currentBet; // Instant optimistic refund
        });

        try {
          final url = Uri.parse('${_getServerBaseUrl()}/auth/game-cancel-bet');
          final res = await http.post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_authToken',
            },
            body: jsonEncode({'betIndex': betIndex}),
          );
          if (!mounted) return;
          final data = jsonDecode(res.body);
          if (res.statusCode == 200 || res.statusCode == 201) {
            setState(() {
              _balance = (data['balance'] as num).toDouble();
              if (betIndex == 1) _isSubmittingBet1 = false;
              else _isSubmittingBet2 = false;
            });
          } else {
            // Revert on error
            final msg = data['message'] ?? 'Could not cancel bet';
            setState(() {
              _balance = previousBalance;
              if (betIndex == 1) {
                _isBetPlaced1 = true;
                _isSubmittingBet1 = false;
              } else {
                _isBetPlaced2 = true;
                _isSubmittingBet2 = false;
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg.toString()), backgroundColor: Colors.red, duration: const Duration(seconds: 2)),
            );
          }
        } catch (e) {
          debugPrint('Error cancelling bet: $e');
          if (mounted) {
            setState(() {
              _balance = previousBalance;
              if (betIndex == 1) {
                _isBetPlaced1 = true;
                _isSubmittingBet1 = false;
              } else {
                _isBetPlaced2 = true;
                _isSubmittingBet2 = false;
              }
            });
          }
        }
      } else {
        // --- 0ms OPTIMISTIC PLACE BET ---
        if (currentBet < 50) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Minimum bet is 50!'), backgroundColor: Colors.red, duration: Duration(seconds: 2)),
          );
          return;
        }
        if (currentBet > 20000) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum bet is 20,000!'), backgroundColor: Colors.red, duration: Duration(seconds: 2)),
          );
          return;
        }
        if (_balance < currentBet) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Insufficient balance!'), backgroundColor: Colors.red, duration: Duration(seconds: 2)),
          );
          return;
        }

        final double previousBalance = _balance;
        setState(() {
          if (betIndex == 1) {
            _isSubmittingBet1 = true;
            _isBetPlaced1 = true;
            _betAmount1 = currentBet;
            _hasCashedOut1 = false;
          } else {
            _isSubmittingBet2 = true;
            _isBetPlaced2 = true;
            _betAmount2 = currentBet;
            _hasCashedOut2 = false;
          }
          _balance = (_balance - currentBet).clamp(0.0, double.infinity); // Instant optimistic deduction
        });

        try {
          final url = Uri.parse('${_getServerBaseUrl()}/auth/game-bet');
          final res = await http.post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_authToken',
            },
            body: jsonEncode({
              'betIndex': betIndex,
              'amount': currentBet,
            }),
          );
          if (!mounted) return;
          final data = jsonDecode(res.body);
          if (res.statusCode == 200 || res.statusCode == 201) {
            setState(() {
              _balance = (data['balance'] as num).toDouble();
              if (betIndex == 1) _isSubmittingBet1 = false;
              else _isSubmittingBet2 = false;
            });
          } else {
            // Revert on error
            final msg = data['message'] ?? 'Could not place bet';
            setState(() {
              _balance = previousBalance;
              if (betIndex == 1) {
                _isBetPlaced1 = false;
                _isSubmittingBet1 = false;
              } else {
                _isBetPlaced2 = false;
                _isSubmittingBet2 = false;
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg.toString()), backgroundColor: Colors.red, duration: const Duration(seconds: 2)),
            );
          }
        } catch (e) {
          debugPrint('Error placing bet: $e');
          if (mounted) {
            setState(() {
              _balance = previousBalance;
              if (betIndex == 1) {
                _isBetPlaced1 = false;
                _isSubmittingBet1 = false;
              } else {
                _isBetPlaced2 = false;
                _isSubmittingBet2 = false;
              }
            });
          }
        }
      }
    }
  }

  Future<void> _cashOut(int betIndex) async {
    if (_status != GameStatus.playing) return;
    bool isPlaced = betIndex == 1 ? _isBetPlaced1 : _isBetPlaced2;
    bool hasCashedOut = betIndex == 1 ? _hasCashedOut1 : _hasCashedOut2;
    
    if (!isPlaced || hasCashedOut || _authToken == null) return;

    // Immediately mark locally to prevent duplicate clicks
    if (betIndex == 1) {
      _hasCashedOut1 = true;
    } else {
      _hasCashedOut2 = true;
    }

    try {
      final url = Uri.parse('${_getServerBaseUrl()}/auth/game-cashout');
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_authToken',
        },
        body: jsonEncode({'betIndex': betIndex}),
      );
      if (!mounted) return;
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        final double winAmount = (data['winAmount'] as num).toDouble();
        final double mult = (data['multiplier'] as num).toDouble();
        final double newBal = (data['balance'] as num).toDouble();
        final myId = betIndex == 1 ? 'my_bet_1' : 'my_bet_2';

        setState(() {
          _balance = newBal;
          _recentlyCashedOut.add(myId);
          if (betIndex == 1) {
            _hasCashedOut1 = true;
            _cashedOutMultiplier1 = mult;
          } else {
            _hasCashedOut2 = true;
            _cashedOutMultiplier2 = mult;
          }
          _floatingWinAmount = winAmount;
          _floatingWinMultiplier = mult;
          _showFloatingWin = true;
          _floatingWinKey++;
        });

        _floatingWinTimer?.cancel();
        _floatingWinTimer = Timer(const Duration(milliseconds: 1600), () {
          if (mounted) {
            setState(() {
              _showFloatingWin = false;
            });
          }
        });

        Timer(const Duration(milliseconds: 1800), () {
          if (mounted) {
            setState(() {
              _recentlyCashedOut.remove(myId);
            });
          }
        });
      } else {
        // Cashout was rejected (e.g. crashed in flight)
        final msg = data['message'] ?? 'Cash out failed';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg.toString()), backgroundColor: Colors.red, duration: const Duration(seconds: 2)),
          );
        }
      }
    } catch (e) {
      debugPrint('Error during cashout: $e');
    }
  }

  Future<void> _saveBetHistory(double betAmount, double? cashedOutMultiplier, double crashPoint, double winAmount) async {
    if (_authToken == null) return;
    try {
      final url = Uri.parse('${_getServerBaseUrl()}/auth/bet-history');
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_authToken',
        },
        body: jsonEncode({
          'betAmount': betAmount,
          'cashOutMultiplier': cashedOutMultiplier,
          'crashPoint': crashPoint,
          'winAmount': winAmount,
          'currency': _userCurrency.code,
        }),
      );
    } catch (e) {
      debugPrint('Failed to save bet history: $e');
    }
  }

  @override
  void dispose() {
    _zeroBalanceToggleTimer?.cancel();
    _localCountdownTimer?.cancel();
    _clockSyncTimer?.cancel();
    _countdownNotifier.dispose();
    socket.dispose();
    _controller.dispose();
    _multiplierNotifier.dispose();
    _betController1.dispose();
    _betController2.dispose();
    super.dispose();
  }

  Widget _buildBetPanel(int betIndex) {
    double betAmount = betIndex == 1 ? _betAmount1 : _betAmount2;
    TextEditingController controller = betIndex == 1 ? _betController1 : _betController2;
    bool isPlaced = betIndex == 1 ? _isBetPlaced1 : _isBetPlaced2;
    bool hasCashedOut = betIndex == 1 ? _hasCashedOut1 : _hasCashedOut2;
    double cashedOutMult = betIndex == 1 ? _cashedOutMultiplier1 : _cashedOutMultiplier2;

    bool isWaiting = _status == GameStatus.waiting;
    bool isPlaying = _status == GameStatus.playing || _status == GameStatus.spectating;
    
    // Check if this specific bet is currently active & flying in the air (cannot modify in-flight bet)
    final bool isBetActiveInFlight = isPlaced && !hasCashedOut && !isWaiting;

    // During waiting countdown, if bet is already committed, user must cancel bet before altering price
    final bool isWaitingBetCommitted = isWaiting && isPlaced;

    // Player can freely adjust price for current or next round whenever their money is not in flight or committed
    final bool canChangeAmount = !isBetActiveInFlight && !isWaitingBetCommitted;
    
    Gradient btnGradient = const LinearGradient(colors: [Color(0xFF334155), Color(0xFF1E293B)]);
    String btnText = 'WAITING';
    List<BoxShadow> btnShadow = [];
    
    if (!_isLoggedIn) {
      btnGradient = const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF0369A1)]);
      btnText = 'LOGIN\nTO BET';
      btnShadow = [BoxShadow(color: const Color(0xFF0284C7).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))];
    } else if (isWaiting) {
      if (isPlaced) {
        btnGradient = const LinearGradient(colors: [Color(0xFFEF4444), Color(0xFFB91C1C)]);
        btnText = 'CANCEL BET';
        btnShadow = [BoxShadow(color: const Color(0xFFEF4444).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))];
      } else {
        btnGradient = const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]);
        btnText = 'BET';
        btnShadow = [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))];
      }
    } else if (isPlaying) {
      if (isPlaced && !hasCashedOut) {
        btnGradient = const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]);
        btnText = 'CASH OUT\n${(betAmount * _currentMultiplier).toStringAsFixed(2)}';
        btnShadow = [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))];
      } else if (hasCashedOut) {
        btnGradient = const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF047857)]);
        btnShadow = [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.5), blurRadius: 12, offset: const Offset(0, 3))];
      }
    } else {
      if (isPlaced && !hasCashedOut) {
        btnGradient = LinearGradient(colors: [const Color(0xFFEF4444).withOpacity(0.6), const Color(0xFFB91C1C).withOpacity(0.6)]);
        btnText = 'LOST';
      } else if (hasCashedOut) {
        btnGradient = const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF047857)]);
        btnShadow = [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3))];
      }
    }

    final bool isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isMobile ? 6 : 8),
      margin: EdgeInsets.only(bottom: isMobile ? 6 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasCashedOut ? const Color(0xFF10B981).withOpacity(0.8) : const Color(0xFF334155),
          width: hasCashedOut ? 1.8 : 1.5,
        ),
        boxShadow: [
          if (hasCashedOut)
            BoxShadow(color: const Color(0xFF10B981).withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 2))
          else
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
        ]
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: canChangeAmount
                          ? () {
                              setState(() {
                                if (betAmount > 50.0) {
                                  final double step = betAmount >= 1000 ? 100.0 : (betAmount >= 200 ? 50.0 : 10.0);
                                  if (betIndex == 1) {
                                    _betAmount1 = (_betAmount1 - step).clamp(50.0, 20000.0);
                                    _betController1.text = _betAmount1 % 1 == 0 ? _betAmount1.toInt().toString() : _betAmount1.toStringAsFixed(2);
                                  } else {
                                    _betAmount2 = (_betAmount2 - step).clamp(50.0, 20000.0);
                                    _betController2.text = _betAmount2 % 1 == 0 ? _betAmount2.toInt().toString() : _betAmount2.toStringAsFixed(2);
                                  }
                                }
                              });
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: canChangeAmount ? const Color(0xFF334155) : const Color(0xFF1E293B),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.remove, color: canChangeAmount ? Colors.white : Colors.white38, size: 20),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 76,
                      child: TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: canChangeAmount ? Colors.white : Colors.white54,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                        enabled: canChangeAmount,
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null && parsed > 0) {
                            if (betIndex == 1) _betAmount1 = parsed.clamp(1.0, 20000.0);
                            else _betAmount2 = parsed.clamp(1.0, 20000.0);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: canChangeAmount
                          ? () {
                              setState(() {
                                final double step = betAmount >= 1000 ? 100.0 : (betAmount >= 200 ? 50.0 : 10.0);
                                if (betIndex == 1) {
                                  _betAmount1 = (_betAmount1 + step).clamp(50.0, 20000.0);
                                  _betController1.text = _betAmount1 % 1 == 0 ? _betAmount1.toInt().toString() : _betAmount1.toStringAsFixed(2);
                                } else {
                                  _betAmount2 = (_betAmount2 + step).clamp(50.0, 20000.0);
                                  _betController2.text = _betAmount2 % 1 == 0 ? _betAmount2.toInt().toString() : _betAmount2.toStringAsFixed(2);
                                }
                              });
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: canChangeAmount ? const Color(0xFF334155) : const Color(0xFF1E293B),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.add, color: canChangeAmount ? Colors.white : Colors.white38, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: (_userCurrency.code == 'LKR'
                            ? [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
                            : (_userCurrency.code == 'INR'
                                ? [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
                                : [1, 2, 5, 10, 20, 50, 100]))
                        .map((amount) {
                      final bool isSelected = (betAmount == amount.toDouble());
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3.5),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: canChangeAmount
                              ? () {
                                  setState(() {
                                    if (betIndex == 1) {
                                      _betAmount1 = amount.toDouble();
                                      _betController1.text = _betAmount1 % 1 == 0 ? _betAmount1.toInt().toString() : _betAmount1.toStringAsFixed(2);
                                    } else {
                                      _betAmount2 = amount.toDouble();
                                      _betController2.text = _betAmount2 % 1 == 0 ? _betAmount2.toInt().toString() : _betAmount2.toStringAsFixed(2);
                                    }
                                  });
                                }
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF0284C7).withOpacity(canChangeAmount ? 0.35 : 0.15)
                                  : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF38BDF8).withOpacity(canChangeAmount ? 1.0 : 0.4)
                                    : const Color(0xFF334155).withOpacity(canChangeAmount ? 1.0 : 0.4),
                                width: isSelected ? 1.4 : 1.0,
                              ),
                            ),
                            child: Text(
                              '$amount',
                              style: TextStyle(
                                color: isSelected
                                    ? (canChangeAmount ? Colors.white : Colors.white60)
                                    : (canChangeAmount ? Colors.white70 : Colors.white38),
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) {
                setState(() {
                  if (betIndex == 1) _isPressedBet1 = true;
                  else _isPressedBet2 = true;
                });
                if (isPlaying && isPlaced && !hasCashedOut) {
                  _cashOut(betIndex);
                }
              },
              onTapUp: (_) {
                if (mounted) {
                  setState(() {
                    if (betIndex == 1) _isPressedBet1 = false;
                    else _isPressedBet2 = false;
                  });
                }
              },
              onTapCancel: () {
                if (mounted) {
                  setState(() {
                    if (betIndex == 1) _isPressedBet1 = false;
                    else _isPressedBet2 = false;
                  });
                }
              },
              onTap: () {
                if (!_isLoggedIn) {
                  _showAuthDialog();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please sign in or register to place bets! ✈️'),
                      backgroundColor: Color(0xFF38BDF8),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                if (isWaiting) {
                  _toggleBet(betIndex);
                } else if (isPlaying && isPlaced && !hasCashedOut) {
                  _cashOut(betIndex);
                }
              },
              child: AnimatedScale(
                scale: (betIndex == 1 ? _isPressedBet1 : _isPressedBet2) ? 0.94 : 1.0,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
                child: RepaintBoundary(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: btnGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: btnShadow,
                      border: hasCashedOut ? Border.all(color: const Color(0xFF34D399), width: 1.5) : null,
                    ),
                    child: Center(
                      child: hasCashedOut
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 12),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'CASHED OUT',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.35),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${cashedOutMult.toStringAsFixed(2)}x',
                                        style: const TextStyle(
                                          color: Color(0xFFFDE047),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '+${_userCurrency.symbol}${(betAmount * cashedOutMult).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            )
                          : (isPlaying && isPlaced && !hasCashedOut)
                              ? ValueListenableBuilder<double>(
                                  valueListenable: _multiplierNotifier,
                                  builder: (context, mult, child) {
                                    return Text(
                                      'CASH OUT\n${(betAmount * mult).toStringAsFixed(2)}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                                    );
                                  },
                                )
                              : Text(
                                  btnText,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                                ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBetsPanel({bool isSidebar = false}) {
    bool isCrashed = _status == GameStatus.crashed;
    bool isPlaying = _status == GameStatus.playing || _status == GameStatus.spectating;

    // Localize community bets according to currently active _userCurrency
    final List<Map<String, dynamic>> displayBets = [];
    for (var rawBet in _liveBets) {
      displayBets.add(LiveBetsAdapter.localize(rawBet, _userCurrency.code));
    }

    // Stable Rank & Sort: Fixed order by Highest Bet Amount descending
    displayBets.sort((a, b) {
      final double aBet = ((a['bet'] ?? 0) as num).toDouble();
      final double bBet = ((b['bet'] ?? 0) as num).toDouble();
      if (bBet != aBet) {
        return bBet.compareTo(aBet);
      }
      return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
    });

    // Calculate total round bets pool
    final double totalPool = displayBets.fold(0.0, (sum, b) => sum + (((b['bet'] ?? 0) as num).toDouble()));

    final bool isMobile = MediaQuery.of(context).size.width < 600;
    return RepaintBoundary(
      child: Container(
      margin: isSidebar
          ? const EdgeInsets.fromLTRB(14, 6, 8, 14)
          : EdgeInsets.fromLTRB(14, 0, 14, isMobile ? 8 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            width: double.infinity,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              color: Color(0xFF0F172A),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPlaying ? Colors.greenAccent : (isCrashed ? Colors.redAccent : Colors.orangeAccent),
                        boxShadow: [
                          BoxShadow(
                            color: (isPlaying ? Colors.greenAccent : (isCrashed ? Colors.redAccent : Colors.orangeAccent)).withOpacity(0.6),
                            blurRadius: 6,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ALL BETS (${displayBets.length})',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                    ),
                  ],
                ),

              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFF334155)),
          Expanded(
            child: displayBets.isEmpty
                ? const Center(
                    child: Text('Waiting for bets...', style: TextStyle(color: Colors.white38, fontSize: 13)),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: displayBets.length,
                    itemBuilder: (context, index) {
                      final bet = displayBets[index];
                      final isMe = bet['isMe'] == true;
                      final isCashedOut = bet['cashedOut'] == true;
                      final isRecent = _recentlyCashedOut.contains(bet['id']);
                      final mult = bet['cashedOutMultiplier'] ?? bet['mult'];
                      final double betAmt = ((bet['bet'] ?? 0) as num).toDouble();
                      final double? winAmt = bet['winAmount'] != null
                          ? ((bet['winAmount']) as num).toDouble()
                          : (mult != null ? betAmt * (mult as num).toDouble() : null);

                      Color rowBg = Colors.transparent;
                      Border? rowBorder;
                      
                      if (isRecent) {
                        rowBg = Colors.greenAccent.withOpacity(0.22);
                        rowBorder = Border.all(color: Colors.greenAccent.withOpacity(0.85), width: 1.2);
                      } else if (isMe) {
                        rowBg = Colors.lightBlueAccent.withOpacity(0.08);
                        rowBorder = Border.all(color: Colors.lightBlueAccent.withOpacity(0.5), width: 1.0);
                      } else if (isCashedOut) {
                        rowBg = Colors.greenAccent.withOpacity(0.06);
                      } else if (isCrashed) {
                        rowBg = Colors.redAccent.withOpacity(0.04);
                      }

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: rowBg,
                          borderRadius: BorderRadius.circular(10),
                          border: rowBorder ?? Border.all(color: const Color(0xFF334155).withOpacity(0.3), width: 0.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Left: Player Avatar & Name (flex: 4)
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundColor: isMe
                                        ? Colors.orangeAccent.withOpacity(0.25)
                                        : (isCashedOut 
                                            ? Colors.greenAccent.withOpacity(0.2) 
                                            : (isCrashed ? Colors.redAccent.withOpacity(0.2) : const Color(0xFF334155))),
                                    child: Icon(
                                      isMe 
                                          ? Icons.star 
                                          : (isCashedOut ? Icons.check : (isCrashed ? Icons.close : Icons.person)),
                                      size: 14,
                                      color: isMe
                                          ? Colors.orangeAccent
                                          : (isCashedOut 
                                              ? Colors.greenAccent 
                                              : (isCrashed ? Colors.redAccent : Colors.white70)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: isMe
                                        ? Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.orangeAccent.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.orangeAccent.withOpacity(0.6)),
                                                ),
                                                child: Text(
                                                  bet['name']?.toString() ?? 'YOU',
                                                  style: const TextStyle(
                                                    color: Colors.orangeAccent,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            bet['name']?.toString() ?? 'player',
                                            style: TextStyle(
                                              color: isCashedOut ? Colors.white : (isCrashed ? Colors.white38 : Colors.white70),
                                              fontSize: 13,
                                              fontWeight: isCashedOut ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            // Middle: Bet Amount (flex: 3, protected by FittedBox)
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${LiveBetsAdapter.formatAmount(betAmt)}',
                                    style: TextStyle(
                                      color: isMe 
                                          ? Colors.white 
                                          : (isCashedOut ? Colors.white : (isCrashed ? Colors.white38 : Colors.white)),
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      decoration: isCrashed && !isCashedOut ? TextDecoration.lineThrough : null,
                                      decorationColor: Colors.redAccent,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                            // Right: Cashout Multiplier & Profit Badge (flex: 4, protected by FittedBox)
                            Expanded(
                              flex: 4,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: isCashedOut
                                      ? AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isRecent 
                                                ? const Color(0xFF10B981).withOpacity(0.35) 
                                                : const Color(0xFF10B981).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isRecent ? Colors.greenAccent : const Color(0xFF10B981).withOpacity(0.6),
                                              width: isRecent ? 1.5 : 1.0,
                                            ),
                                            boxShadow: isRecent
                                                ? [BoxShadow(color: Colors.greenAccent.withOpacity(0.4), blurRadius: 8, spreadRadius: 1)]
                                                : null,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                mult != null ? '${(mult as num).toStringAsFixed(2)}x' : '',
                                                style: const TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              if (winAmt != null) ...[
                                                const SizedBox(width: 4),
                                                Text(
                                                  '+${LiveBetsAdapter.formatAmount(winAmt)}',
                                                  style: TextStyle(
                                                    color: Colors.greenAccent.shade100,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        )
                                      : (isCrashed
                                          ? Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.redAccent.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                                              ),
                                              child: const Text(
                                                'LOST',
                                                style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w900),
                                              ),
                                            )
                                          : (isPlaying
                                              ? Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orangeAccent.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text(
                                                    'FLYING',
                                                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                )
                                              : const Text(
                                                  'WAITING',
                                                  style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                                                ))),
                                ),
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ));
  }

  Widget _buildHistoryBar() {
    return Container(
      height: 30,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _history.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final mult = _history[index];
          Color color;
          if (mult < 2.0) {
            color = Colors.redAccent;
          } else if (mult < 5.0) {
            color = const Color(0xFFC084FC); // Purple
          } else if (mult < 10.0) {
            color = Colors.lightBlueAccent;
          } else if (mult < 20.0) {
            color = Colors.greenAccent;
          } else if (mult < 50.0) {
            color = Colors.orangeAccent;
          } else {
            color = const Color(0xFFFFD700); // Gold
          }
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.8), width: 1.0),
            ),
            alignment: Alignment.center,
            child: Text(
              '${mult.toStringAsFixed(2)}x',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  void _showAuthDialog() {
    final userController = TextEditingController();
    final emailController = TextEditingController();
    final passController = TextEditingController();
    final resetEmailController = TextEditingController();
    final otpController = TextEditingController();
    final newPassController = TextEditingController();

    bool isLoginTab = true;
    bool isForgotPasswordMode = false;
    bool isOtpSent = false;
    bool isLoading = false;
    String? errorMessage;
    String? successMessage;
    String? devOtpCode;
    Currency regCurrency = _userCurrency.code.isNotEmpty ? _userCurrency : Currency.getByCode('LKR');

    // Feature Flags:
    const bool showWelcomeBanner = false;
    const bool showCurrencyPicker = true; // Currency selector is now visible!

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final mediaQuery = MediaQuery.of(context);
          final bool isKeyboardOpen = mediaQuery.viewInsets.bottom > 50;

          return Dialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0xFF334155), width: 1.5),
            ),
            insetPadding: EdgeInsets.symmetric(
              horizontal: 20,
              vertical: isKeyboardOpen ? 16 : 24,
            ),
            clipBehavior: Clip.antiAlias,
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  maxHeight: mediaQuery.size.height * 0.88,
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: isKeyboardOpen ? 18 : 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  // Modal Top Header
                  if (isForgotPasswordMode) ...[
                    Row(
                      children: [
                        InkWell(
                          onTap: () {
                            setDialogState(() {
                              isForgotPasswordMode = false;
                              isOtpSent = false;
                              errorMessage = null;
                              successMessage = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: const Icon(Icons.arrow_back, color: Color(0xFF38BDF8), size: 18),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isOtpSent ? 'Create New Password' : 'Reset Password',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isOtpSent
                          ? 'Enter the 6-digit verification code sent to your email and choose a new password.'
                          : 'Enter your registered email address to receive a verification code.',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.flight_takeoff, color: Color(0xFF38BDF8), size: 28),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'SkyRush Account',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Sign In / Register Tab Switcher
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  isLoginTab = true;
                                  errorMessage = null;
                                  successMessage = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isLoginTab ? const Color(0xFF38BDF8) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Sign In',
                                  style: TextStyle(
                                    color: isLoginTab ? const Color(0xFF0F172A) : Colors.white60,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  isLoginTab = false;
                                  errorMessage = null;
                                  successMessage = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: !isLoginTab ? const Color(0xFF38BDF8) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Register',
                                  style: TextStyle(
                                    color: !isLoginTab ? const Color(0xFF0F172A) : Colors.white60,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Security Banner for Registration
                  if (!isForgotPasswordMode && !isLoginTab)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.35)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_user_outlined, color: Color(0xFF38BDF8), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Create your secure account to start playing!',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ==================== FORGOT PASSWORD FORM ====================
                  if (isForgotPasswordMode) ...[
                    if (!isOtpSent) ...[
                      // Step 1: Email Input
                      TextField(
                        controller: resetEmailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Registered Email Address',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF38BDF8), size: 20),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Step 2: 6-Digit OTP and New Password Fields
                      if (devOtpCode != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.key, color: Color(0xFF38BDF8), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Dev Verification Code: $devOtpCode (Auto-filled)',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      TextField(
                        controller: otpController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 2.0, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: '6-digit code',
                          hintStyle: const TextStyle(color: Colors.white38, letterSpacing: 0),
                          prefixIcon: const Icon(Icons.mark_email_read_outlined, color: Color(0xFF38BDF8), size: 20),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: newPassController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'New Password',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.lock_reset, color: Color(0xFF38BDF8), size: 20),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ] else ...[
                    // ==================== NORMAL AUTH FORM ====================
                    if (!isLoginTab) ...[
                      // Register Tab: Email Input
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Email',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF38BDF8), size: 20),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: (errorMessage != null && errorMessage!.toLowerCase().contains('already registered'))
                                  ? Colors.redAccent
                                  : const Color(0xFF334155),
                              width: (errorMessage != null && errorMessage!.toLowerCase().contains('already registered')) ? 1.5 : 1.0,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Password Input
                      TextField(
                        controller: passController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Password',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.lock, color: Color(0xFF38BDF8), size: 20),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Visible Currency Selector Card
                      if (showCurrencyPicker) ...[
                        InkWell(
                          onTap: () async {
                            final picked = await CurrencyPickerSheet.show(context, regCurrency);
                            if (picked != null) {
                              setDialogState(() {
                                regCurrency = picked;
                              });
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5), width: 1.2),
                            ),
                            child: Row(
                              children: [
                                Text(regCurrency.flag, style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Currency: ${regCurrency.code}',
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF38BDF8).withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              regCurrency.symbol,
                                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        regCurrency.name,
                                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down, color: Color(0xFF38BDF8), size: 22),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ] else ...[
                      // Sign In Tab: Email or Username
                      TextField(
                        controller: userController,
                        keyboardType: TextInputType.text,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Email or Username',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.person, color: Color(0xFF38BDF8), size: 20),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: passController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Password',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.lock, color: Color(0xFF38BDF8), size: 20),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                          ),
                        ),
                      ),

                      // Forgot Password link in Sign In mode
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: () {
                            setDialogState(() {
                              isForgotPasswordMode = true;
                              isOtpSent = false;
                              errorMessage = null;
                              successMessage = null;
                              if (userController.text.trim().isNotEmpty) {
                                resetEmailController.text = userController.text.trim();
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),
                  ],

                  // Success message container
                  if (successMessage != null) ...[
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              successMessage!,
                              style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Error message container
                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          if (!isForgotPasswordMode && !isLoginTab && errorMessage!.toLowerCase().contains('already registered')) ...[
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: () {
                                setDialogState(() {
                                  isLoginTab = true;
                                  errorMessage = null;
                                  userController.text = emailController.text.trim();
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF38BDF8).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF38BDF8)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Already have an account? Sign In',
                                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(width: 6),
                                    Icon(Icons.arrow_forward, color: Color(0xFF38BDF8), size: 14),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ==================== SUBMIT BUTTON ====================
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF38BDF8),
                        foregroundColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                      onPressed: isLoading
                          ? null
                          : () async {
                              // ================= FORGOT PASSWORD ACTIONS =================
                              if (isForgotPasswordMode) {
                                if (!isOtpSent) {
                                  // Request OTP
                                  final email = resetEmailController.text.trim();
                                  if (email.isEmpty) {
                                    setDialogState(() => errorMessage = 'Please enter your registered email address');
                                    return;
                                  }
                                  if (!email.contains('@') || !email.contains('.')) {
                                    setDialogState(() => errorMessage = 'Please enter a valid email address');
                                    return;
                                  }

                                  setDialogState(() {
                                    isLoading = true;
                                    errorMessage = null;
                                    successMessage = null;
                                  });

                                  final result = await _requestResetOtp(email);
                                  if (!mounted) return;

                                  if (result['success'] == true) {
                                    setDialogState(() {
                                      isLoading = false;
                                      isOtpSent = true;
                                      devOtpCode = result['devOtp'];
                                      otpController.text = devOtpCode ?? '';
                                      successMessage = 'Verification code sent to $email!';
                                    });
                                  } else {
                                    setDialogState(() {
                                      isLoading = false;
                                      errorMessage = result['message'] ?? 'Failed to send code';
                                    });
                                  }
                                } else {
                                  // Submit Reset OTP + New Password
                                  final otp = otpController.text.trim();
                                  final newPass = newPassController.text.trim();
                                  if (otp.isEmpty || newPass.isEmpty) {
                                    setDialogState(() => errorMessage = 'Please enter the verification code and new password');
                                    return;
                                  }
                                  if (newPass.length < 4) {
                                    setDialogState(() => errorMessage = 'New password must be at least 4 characters long');
                                    return;
                                  }

                                  final email = resetEmailController.text.trim();

                                  setDialogState(() {
                                    isLoading = true;
                                    errorMessage = null;
                                    successMessage = null;
                                  });

                                  final result = await _resetPassword(email, otp, newPass);
                                  if (!mounted) return;

                                  if (result['success'] == true) {
                                    if (ctx.mounted) Navigator.of(ctx).pop();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Password reset successfully! Welcome back 🎉'),
                                          backgroundColor: Color(0xFF10B981),
                                          duration: Duration(seconds: 3),
                                        ),
                                      );
                                    }
                                  } else {
                                    setDialogState(() {
                                      isLoading = false;
                                      errorMessage = result['message'] ?? 'Failed to reset password';
                                    });
                                  }
                                }
                                return;
                              }

                              // ================= NORMAL AUTH ACTIONS =================
                              if (isLoginTab) {
                                final u = userController.text.trim();
                                final p = passController.text.trim();
                                if (u.isEmpty || p.isEmpty) {
                                  setDialogState(() => errorMessage = 'Please fill in both fields');
                                  return;
                                }

                                setDialogState(() {
                                  isLoading = true;
                                  errorMessage = null;
                                });

                                final result = await _loginUser(u, p);
                                if (!mounted) return;
                                if (result['success'] == true) {
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                  if (mounted) {
                                    final username = result['user']?['username'] ?? u;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Welcome back, $username! (${_userCurrency.code}) 🎉'),
                                        backgroundColor: const Color(0xFF10B981),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } else {
                                  setDialogState(() {
                                    isLoading = false;
                                    errorMessage = result['message'] ?? 'Authentication failed';
                                  });
                                }
                              } else {
                                // Register Tab: Email + Password + Currency
                                final email = emailController.text.trim().toLowerCase();
                                final p = passController.text.trim();
                                if (email.isEmpty || p.isEmpty) {
                                  setDialogState(() => errorMessage = 'Please enter your email and password');
                                  return;
                                }
                                if (!email.contains('@') || !email.contains('.')) {
                                  setDialogState(() => errorMessage = 'Please enter a valid email address');
                                  return;
                                }
                                if (p.length < 4) {
                                  setDialogState(() => errorMessage = 'Password must be at least 4 characters long');
                                  return;
                                }

                                setDialogState(() {
                                  isLoading = true;
                                  errorMessage = null;
                                });

                                final result = await _registerUser(email, p, regCurrency.code);
                                if (!mounted) return;
                                if (result['success'] == true) {
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                  if (mounted) {
                                    final username = result['user']?['username'] ?? email;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Welcome, $username! (${regCurrency.code}) 🎉'),
                                        backgroundColor: const Color(0xFF10B981),
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                } else {
                                  setDialogState(() {
                                    isLoading = false;
                                    errorMessage = result['message'] ?? 'Registration failed';
                                  });
                                }
                              }
                            },
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Color(0xFF0F172A), strokeWidth: 2.5),
                            )
                          : Text(
                              isForgotPasswordMode
                                  ? (!isOtpSent ? 'Send Verification Code' : 'Reset Password & Sign In')
                                  : (isLoginTab ? 'Sign In' : 'Create Account & Play'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  if (isForgotPasswordMode)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isOtpSent) ...[
                          TextButton(
                            onPressed: () {
                              setDialogState(() {
                                isOtpSent = false;
                                devOtpCode = null;
                                otpController.clear();
                                errorMessage = null;
                                successMessage = null;
                              });
                            },
                            child: const Text('← Change Email', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              isForgotPasswordMode = false;
                              isOtpSent = false;
                              devOtpCode = null;
                              errorMessage = null;
                              successMessage = null;
                            });
                          },
                          child: const Text('Back to Sign In', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    )
                  else
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Continue as Guest', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        },
      ),
    );
  }

  void _showDepositSheet() {
    if (!_isLoggedIn || _authToken == null) {
      _showAuthDialog();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DepositSheet(
        currency: _userCurrency,
        authToken: _authToken!,
        serverBaseUrl: _getServerBaseUrl(),
        onDepositSubmitted: () {},
      ),
    );
  }

  void _showWithdrawalSheet() {
    if (!_isLoggedIn || _authToken == null) {
      _showAuthDialog();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WithdrawalSheet(
        currency: _userCurrency,
        currentBalance: _balance,
        authToken: _authToken!,
        serverBaseUrl: _getServerBaseUrl(),
        onWithdrawalSubmitted: () {},
      ),
    );
  }

  void _showBetHistorySheet() {
    if (!_isLoggedIn || _authToken == null) {
      _showAuthDialog();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BetHistorySheet(
        currency: _userCurrency,
        authToken: _authToken!,
        serverBaseUrl: _getServerBaseUrl(),
      ),
    );
  }

  void _showTransactionHistorySheet() {
    if (!_isLoggedIn || _authToken == null) {
      _showAuthDialog();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TransactionHistorySheet(
        currency: _userCurrency,
        authToken: _authToken!,
        serverBaseUrl: _getServerBaseUrl(),
      ),
    );
  }

  void _showEditUsernameDialog() {
    final TextEditingController nameController = TextEditingController(text: _currentUser?['username'] ?? '');
    bool isSaving = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Edit Username', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'New Username',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF38BDF8))),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
                onPressed: isSaving
                    ? null
                    : () async {
                        final newName = nameController.text.trim();
                        if (newName.length < 3) {
                          setDialogState(() => errorMessage = 'Username must be at least 3 characters');
                          return;
                        }
                        setDialogState(() {
                          isSaving = true;
                          errorMessage = null;
                        });
                        try {
                          final res = await http.post(
                            Uri.parse('${_getServerBaseUrl()}/auth/rename'),
                            headers: {
                              'Content-Type': 'application/json',
                              'Authorization': 'Bearer $_authToken'
                            },
                            body: jsonEncode({'newUsername': newName}),
                          );
                          final data = jsonDecode(res.body);
                          if (res.statusCode == 200 || res.statusCode == 201) {
                            setState(() {
                              _currentUser = data;
                            });
                            if (!mounted) return;
                            Navigator.of(context).pop();
                            _showProfileSheet();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Username updated successfully!'), backgroundColor: Colors.green),
                            );
                          } else {
                            setDialogState(() => errorMessage = data['message'] ?? 'Failed to update username');
                          }
                        } catch (e) {
                          setDialogState(() => errorMessage = 'Network error');
                        } finally {
                          if (mounted) {
                            setDialogState(() => isSaving = false);
                          }
                        }
                      },
                child: isSaving 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) 
                  : const Text('SAVE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final username = _currentUser?['username'] ?? 'SkyRush Pilot';
        final gamesPlayed = _currentUser?['gamesPlayed'] ?? 0;
        final totalWon = ((_currentUser?['totalWon'] as num?)?.toDouble() ?? 0.0);
        final bestMult = ((_currentUser?['bestMultiplier'] as num?)?.toDouble() ?? 1.0);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFF6366F1)]),
                          ),
                          child: CircleAvatar(
                            radius: 28,
                            backgroundColor: const Color(0xFF1E293B),
                            child: username.startsWith('+') || RegExp(r'^\d').hasMatch(username)
                                ? const Icon(Icons.phone_android, color: Color(0xFF38BDF8), size: 26)
                                : Text(
                                    username.isNotEmpty ? username[0].toUpperCase() : 'U',
                                    style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 22),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      username,
                                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      _showEditUsernameDialog();
                                    },
                                    child: const Icon(Icons.edit, color: Colors.white54, size: 18),
                                  ),
                                ],
                              ),
                              if (_currentUser?['email'] != null && (_currentUser!['email'] as String).isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _currentUser!['email'],
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.star, color: Colors.amber, size: 14),
                                        SizedBox(width: 4),
                                        Text(
                                          'VIP SKY PILOT',
                                          style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                                    ),
                                    child: Text(
                                      '${_userCurrency.flag} ${_userCurrency.code} (${_userCurrency.symbol})',
                                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: _buildProfileStatCard('Wallet Balance', '${_userCurrency.symbol}${_balance.toStringAsFixed(2)}', Icons.account_balance_wallet, const Color(0xFF10B981)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildProfileStatCard('Games Played', '$gamesPlayed', Icons.sports_esports, const Color(0xFF38BDF8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildProfileStatCard('Total Won', '${_userCurrency.symbol}${totalWon.toStringAsFixed(2)}', Icons.emoji_events, const Color(0xFFF59E0B)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildProfileStatCard('Best Multiplier', '${bestMult.toStringAsFixed(2)}x', Icons.rocket_launch, const Color(0xFFA855F7)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Deposit & Withdraw side-by-side
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
                              label: const Text(
                                'Deposit',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 3,
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _showDepositSheet();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
                              label: const Text(
                                'Withdraw',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF43F5E),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 3,
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _showWithdrawalSheet();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Transaction History Button
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.receipt_long, color: Color(0xFF38BDF8), size: 18),
                        label: const Text(
                          'Transaction History (Deposits & Payouts)',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                          ),
                          elevation: 1,
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showTransactionHistorySheet();
                        },
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Bet History Button
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.history, color: Color(0xFF38BDF8), size: 18),
                        label: const Text(
                          'My Bet History',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                          ),
                          elevation: 1,
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showBetHistorySheet();
                        },
                      ),
                    ),
                    const SizedBox(height: 10),

                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: TextButton.icon(
                        icon: const Icon(Icons.logout, color: Colors.redAccent, size: 18),
                        label: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _logoutUser();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Logged out. Reverted to Guest Mode.'),
                              backgroundColor: Colors.blueGrey,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProfileStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final bool isDesktop = screenWidth >= 900 && screenHeight >= 500;
    final bool isShort = screenHeight < 750;
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium Dark Slate
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16.0,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flight_takeoff, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 24, 
                    fontWeight: FontWeight.w900, 
                    fontStyle: FontStyle.italic, 
                    letterSpacing: 1.2
                  ),
                  children: [
                    TextSpan(text: 'Sky', style: TextStyle(color: Colors.lightBlueAccent)),
                    TextSpan(text: 'Rush', style: TextStyle(color: Colors.orangeAccent)),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Builder(
            builder: (ctx) {
              if (MediaQuery.of(ctx).size.width < 50) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(right: 8.0),
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: _isConnected ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _isConnected ? Colors.greenAccent.withOpacity(0.4) : Colors.redAccent.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isConnected ? 'LIVE' : 'OFFLINE',
                            style: TextStyle(
                              color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: _isLoggedIn
                        ? (_balance > 0
                            ? InkWell(
                                onTap: _showProfileSheet,
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 6.0),
                                  padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 6.0),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.account_balance_wallet, size: 16, color: Colors.white),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${_userCurrency.symbol}${_balance.toStringAsFixed(2)}',
                                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                transitionBuilder: (Widget child, Animation<double> animation) {
                                  return FadeTransition(opacity: animation, child: child);
                                },
                                child: _showZeroBalanceDeposit
                                    ? InkWell(
                                        key: const ValueKey('deposit'),
                                        onTap: _showDepositSheet,
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 6.0),
                                          padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 6.0),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: [
                                              BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 2))
                                            ],
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.add, size: 15, color: Colors.white),
                                              SizedBox(width: 4),
                                              Text(
                                                'Deposit',
                                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : InkWell(
                                        key: const ValueKey('balance'),
                                        onTap: _showProfileSheet,
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 6.0),
                                          padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 6.0),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                                            borderRadius: BorderRadius.circular(20),
                                            boxShadow: [
                                              BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.account_balance_wallet, size: 16, color: Colors.white),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${_userCurrency.symbol}${_balance.toStringAsFixed(2)}',
                                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ))
                        : InkWell(
                            onTap: _showAuthDialog,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8.0),
                              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 2))
                                ],
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.add_circle_outline, size: 16, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text(
                                    'Deposit',
                                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  // Profile Avatar Icon (Tap to Login / View Profile)
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Center(
                      child: InkWell(
                        onTap: () {
                          if (_isLoggedIn) {
                            _showProfileSheet();
                          } else {
                            _showAuthDialog();
                          }
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _isLoggedIn
                                ? const LinearGradient(
                                    colors: [Color(0xFF38BDF8), Color(0xFF6366F1)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : const LinearGradient(
                                    colors: [Colors.white38, Colors.white12],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                            boxShadow: [
                              BoxShadow(
                                color: _isLoggedIn
                                    ? const Color(0xFF38BDF8).withOpacity(0.5)
                                    : Colors.black26,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF1E293B),
                            child: _isLoggedIn
                                ? (((_currentUser?['username'] ?? '') as String).startsWith('+') ||
                                        RegExp(r'^\d').hasMatch((_currentUser?['username'] ?? '') as String)
                                    ? const Icon(Icons.phone_android, size: 16, color: Color(0xFF38BDF8))
                                    : Text(
                                        ((_currentUser?['username'] ?? 'U') as String).substring(0, 1).toUpperCase(),
                                        style: const TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ))
                                : const Icon(Icons.person_outline, size: 18, color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // PWA Install App Button (Visible on mobile/web browsers when not already standalone)
                  if (kIsWeb && !FullscreenService.isPwaStandalone())
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Center(
                        child: InkWell(
                          onTap: _handleInstallApp,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5)),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF38BDF8).withOpacity(0.3),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _InstallMobileIcon(color: Colors.white, size: 14),
                                SizedBox(width: 4.5),
                                Text(
                                  'APP',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            if (_showHistoryBar) _buildHistoryBar(),
            Expanded(
              child: isDesktop
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final double sidebarWidth = (constraints.maxWidth * 0.28).clamp(280.0, 340.0);
                        final double rightAreaWidth = constraints.maxWidth - sidebarWidth;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: sidebarWidth,
                              child: _buildBottomBetsPanel(isSidebar: true),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _buildArena(isDesktop: true, isShort: isShort),
                                  ),
                                  _buildDesktopBetControls(rightAreaWidth),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    )
                  : Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildArena(isDesktop: false, isShort: isShort),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Column(
                            children: [
                              _buildBetPanel(1),
                              _buildBetPanel(2),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _buildBottomBetsPanel(),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopBetControls(double rightWidth) {
    final bool sideBySide = rightWidth >= 680;
    if (sideBySide) {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 0, 14, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildBetPanel(1)),
            const SizedBox(width: 10),
            Expanded(child: _buildBetPanel(2)),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 0, 14, 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBetPanel(1),
            _buildBetPanel(2),
          ],
        ),
      );
    }
  }

  Widget _buildArena({required bool isDesktop, required bool isShort}) {
    return RepaintBoundary(
      child: Container(
      margin: isDesktop
          ? const EdgeInsets.fromLTRB(8, 6, 14, 8)
          : EdgeInsets.fromLTRB(14, isShort ? 6 : 14, 14, isShort ? 4 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: _multiplierNotifier,
                builder: (context, mult, _) => SkyCloudsBackground(
                  isPlaying: _status == GameStatus.playing || _status == GameStatus.spectating,
                  multiplier: mult,
                ),
              ),
            ),
            if (_status != GameStatus.waiting)
              ValueListenableBuilder<double>(
                valueListenable: _multiplierNotifier,
                builder: (context, mult, _) => RepaintBoundary(
                  child: PlaneGraph(
                    multiplier: mult,
                    isCrashed: _status == GameStatus.crashed,
                  ),
                ),
              ),
            if (_status == GameStatus.waiting)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'NEXT ROUND IN',
                      style: TextStyle(color: Colors.white54, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<int>(
                      valueListenable: _countdownNotifier,
                      builder: (context, count, _) => Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 80,
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(color: Colors.white24, blurRadius: 20)],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Center(
                child: ValueListenableBuilder<double>(
                  valueListenable: _multiplierNotifier,
                  builder: (context, mult, _) => Text(
                    '${mult.toStringAsFixed(2)}x',
                    style: TextStyle(
                      color: _status == GameStatus.crashed ? Colors.redAccent : Colors.white,
                      fontSize: 72,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color: (_status == GameStatus.crashed ? Colors.redAccent : Colors.lightBlueAccent).withOpacity(0.6),
                          blurRadius: 25,
                        )
                      ],
                    ),
                  ),
                ),
              ),
            if (_status == GameStatus.crashed)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 180),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.redAccent, Colors.orangeAccent],
                      ).createShader(bounds),
                      child: const Text(
                        'FLEW AWAY!',
                        style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 2.0),
                      ),
                    ),
                  ],
                ),
              ),
            if (_showFloatingWin && _status != GameStatus.crashed)
              IgnorePointer(
                child: Center(
                  key: ValueKey('floating_win_$_floatingWinKey'),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 1500),
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    curve: Curves.easeOutCubic,
                    builder: (context, progress, child) {
                      final double translateY = -75.0 * progress;
                      final double opacity = (1.0 - progress).clamp(0.0, 1.0);
                      final double scale = 0.88 + 0.12 * (1.0 - (progress - 0.3).abs() * 2).clamp(0.0, 1.0);
                      return Transform.translate(
                        offset: Offset(0, translateY),
                        child: Transform.scale(
                          scale: scale,
                          child: Opacity(
                            opacity: opacity,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('✨', style: TextStyle(fontSize: 18)),
                                    const SizedBox(width: 4),
                                    ShaderMask(
                                      shaderCallback: (bounds) => const LinearGradient(
                                        colors: [Color(0xFFFFF9C4), Color(0xFFFBBF24), Color(0xFFD97706)],
                                        stops: [0.0, 0.5, 1.0],
                                      ).createShader(bounds),
                                      child: const Text(
                                        'YOU WIN!',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 2.5,
                                          shadows: [
                                            Shadow(color: Color(0xFFF59E0B), blurRadius: 18),
                                            Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text('✨', style: TextStyle(fontSize: 18)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.4),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.6), width: 1.2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF10B981).withOpacity(0.25),
                                        blurRadius: 16,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '+${_userCurrency.symbol}${_floatingWinAmount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.8,
                                          shadows: [
                                            Shadow(color: Color(0xFF10B981), blurRadius: 14),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFDE047).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFFDE047).withOpacity(0.6), width: 1),
                                        ),
                                        child: Text(
                                          '${_floatingWinMultiplier.toStringAsFixed(2)}x',
                                          style: const TextStyle(
                                            color: Color(0xFFFDE047),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    ));
  }

  void _handleInstallApp() {
    if (kIsWeb) {
      if (FullscreenService.isPwaInstallAvailable()) {
        final triggered = FullscreenService.triggerPwaPrompt();
        if (triggered) return;
      }
      if (FullscreenService.isIosWeb()) {
        _showIosPwaGuide();
      } else {
        _showAndroidInstallGuide();
      }
    }
  }

  void _showAndroidInstallGuide() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0xFF38BDF8), width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const _InstallMobileIcon(color: Color(0xFF38BDF8), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Install SkyRush Web App',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Play in full screen without browser bars',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildIosGuideStep(
              number: '1',
              icon: Icons.more_vert,
              text: "Tap the Chrome menu (⋮) in the top-right corner",
            ),
            const SizedBox(height: 12),
            _buildIosGuideStep(
              number: '2',
              icon: Icons.add_to_home_screen,
              text: "Tap 'Install app' or 'Add to Home screen'",
            ),
            const SizedBox(height: 12),
            _buildIosGuideStep(
              number: '3',
              icon: Icons.rocket_launch,
              text: 'Launch SkyRush directly from your Home screen!',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.download, color: Colors.white, size: 20),
                      label: const Text('INSTALL NOW', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (!FullscreenService.triggerPwaPrompt()) {
                          FullscreenService.toggleFullscreen();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  void _showIosPwaGuide() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0xFF38BDF8), width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.fullscreen, color: Colors.orangeAccent, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Play in 100% Fullscreen on iPhone',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildIosGuideStep(
              number: '1',
              icon: Icons.ios_share,
              text: "Tap the 'Share' button at the bottom of Safari (⎋)",
            ),
            const SizedBox(height: 12),
            _buildIosGuideStep(
              number: '2',
              icon: Icons.add_box_outlined,
              text: "Scroll down and tap 'Add to Home Screen' (➕)",
            ),
            const SizedBox(height: 12),
            _buildIosGuideStep(
              number: '3',
              icon: Icons.touch_app,
              text: 'Launch SkyRush from your Home Screen with zero browser bars!',
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('GOT IT!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIosGuideStep({required String number, required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFF0284C7),
              shape: BoxShape.circle,
            ),
            child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _InstallMobileIcon extends StatelessWidget {
  final Color color;
  final double size;

  const _InstallMobileIcon({
    this.color = Colors.white,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    final width = size * 0.82;
    final height = size;
    return CustomPaint(
      size: Size(width, height),
      painter: _InstallMobileIconPainter(color: color),
    );
  }
}

class _InstallMobileIconPainter extends CustomPainter {
  final Color color;
  const _InstallMobileIconPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height / 14.0) * 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Phone body rounded rect
    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.8, 0.8, w - 1.6, h - 1.6),
      Radius.circular(size.height * 0.16),
    );
    canvas.drawRRect(phoneRect, strokePaint);

    // Arrow Stem
    canvas.drawLine(
      Offset(w * 0.5, h * 0.28),
      Offset(w * 0.5, h * 0.65),
      strokePaint..strokeWidth = (size.height / 14.0) * 1.4,
    );

    // Arrow Head
    final arrowPath = Path();
    arrowPath.moveTo(w * 0.28, h * 0.48);
    arrowPath.lineTo(w * 0.5, h * 0.68);
    arrowPath.lineTo(w * 0.72, h * 0.48);
    canvas.drawPath(arrowPath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _InstallMobileIconPainter oldDelegate) => oldDelegate.color != color;
}

