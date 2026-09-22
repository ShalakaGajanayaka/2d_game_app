import 'dart:async';
import 'dart:math';

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/game_state.dart';
import '../widgets/plane_graph.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  GameStatus _status = GameStatus.waiting;
  
  double _balance = 1000.0;
  
  // Bet 1
  double _betAmount1 = 10.0;
  final TextEditingController _betController1 = TextEditingController(text: '10.00');
  bool _isBetPlaced1 = false;
  double _cashedOutMultiplier1 = 0.0;
  bool _hasCashedOut1 = false;

  // Bet 2
  double _betAmount2 = 10.0;
  final TextEditingController _betController2 = TextEditingController(text: '10.00');
  bool _isBetPlaced2 = false;
  double _cashedOutMultiplier2 = 0.0;
  bool _hasCashedOut2 = false;
  
  double _currentMultiplier = 1.0;
  final List<double> _history = [];
  final bool _showHistoryBar = false; // Set to true to show history bar again
  List<Map<String, dynamic>> _liveBets = [];
  final Set<String> _recentlyCashedOut = {};
  bool _isConnected = false;
  
  late AnimationController _controller;
  int _countdown = 15;
  
  bool _showWinMessage = false;
  double _winAmount = 0.0;
  double _winMultiplier = 0.0;
  Timer? _winMessageTimer;
  
  late IO.Socket socket;
  double _serverStartTime = 0;
  
  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 100), 
    )..addListener(() {
        if (_status == GameStatus.playing || _status == GameStatus.spectating) {
          setState(() {
            double elapsedSeconds = (DateTime.now().millisecondsSinceEpoch - _serverStartTime) / 1000;
            if (elapsedSeconds > 0) {
               _currentMultiplier = 1.0 + pow(elapsedSeconds, 2.5) / 10;
            }
          });
        }
    });

    _initSocket();
  }

  void _initSocket() {
    String serverUrl = dotenv.env['SERVER_API_URL']!;
    if (!kIsWeb && Platform.isAndroid) {
      serverUrl = serverUrl.replaceFirst('localhost', '10.0.2.2');
      serverUrl = serverUrl.replaceFirst('127.0.0.1', '10.0.2.2');
    }

    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    
    socket.onConnect((_) {
      if (mounted) setState(() => _isConnected = true);
    });

    socket.onDisconnect((_) {
      if (mounted) setState(() => _isConnected = false);
    });
    
    socket.connect();
    
    socket.on('gameState', (data) {
      if (!mounted) return;
      
      setState(() {
        final serverStatus = data['status'];
        _countdown = data['countdown'];
        
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
              _serverStartTime = data['startTime'].toDouble();
              _controller.repeat(); 
           } 
           else if (newStatus == GameStatus.crashed) {
              _controller.stop();
              _currentMultiplier = data['currentMultiplier'].toDouble();
              _history.insert(0, _currentMultiplier);
              if (_history.length > 20) {
                 _history.removeLast();
              }
              _isBetPlaced1 = false;
              _isBetPlaced2 = false;
              _hasCashedOut1 = false;
              _hasCashedOut2 = false;
           }
           else if (newStatus == GameStatus.waiting) {
              _controller.stop();
              _currentMultiplier = 1.0;
              _hasCashedOut1 = false;
              _hasCashedOut2 = false;
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
  }

  void _toggleBet(int betIndex) {
    FocusManager.instance.primaryFocus?.unfocus();
    
    if (_status == GameStatus.waiting) {
      double currentBet = betIndex == 1 ? _betAmount1 : _betAmount2;
      bool isPlaced = betIndex == 1 ? _isBetPlaced1 : _isBetPlaced2;
      TextEditingController controller = betIndex == 1 ? _betController1 : _betController2;
      
      final parsed = double.tryParse(controller.text);
      if (parsed != null && parsed > 0) {
        currentBet = parsed;
      }

      setState(() {
        if (isPlaced) {
          // Cancel bet
          _balance += currentBet;
          if (betIndex == 1) { _isBetPlaced1 = false; _betAmount1 = currentBet; }
          else { _isBetPlaced2 = false; _betAmount2 = currentBet; }
        } else {
          // Place bet
          if (_balance >= currentBet) {
            _balance -= currentBet;
            if (betIndex == 1) { _isBetPlaced1 = true; _betAmount1 = currentBet; _hasCashedOut1 = false; }
            else { _isBetPlaced2 = true; _betAmount2 = currentBet; _hasCashedOut2 = false; }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Insufficient balance!'), backgroundColor: Colors.red, duration: Duration(seconds: 2)),
            );
          }
        }
      });
    }
  }

  void _cashOut(int betIndex) {
    if (_status != GameStatus.playing) return;
    bool isPlaced = betIndex == 1 ? _isBetPlaced1 : _isBetPlaced2;
    bool hasCashedOut = betIndex == 1 ? _hasCashedOut1 : _hasCashedOut2;
    double currentBet = betIndex == 1 ? _betAmount1 : _betAmount2;
    
    if (!isPlaced || hasCashedOut) return;
    
    double winAmount = currentBet * _currentMultiplier;
    final myId = betIndex == 1 ? 'my_bet_1' : 'my_bet_2';
    
    setState(() {
      _balance += winAmount;
      _recentlyCashedOut.add(myId);
      if (betIndex == 1) {
        _hasCashedOut1 = true;
        _cashedOutMultiplier1 = _currentMultiplier;
      } else {
        _hasCashedOut2 = true;
        _cashedOutMultiplier2 = _currentMultiplier;
      }
      
      _showWinMessage = true;
      _winAmount = winAmount;
      _winMultiplier = _currentMultiplier;
    });

    Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() {
          _recentlyCashedOut.remove(myId);
        });
      }
    });
    
    _winMessageTimer?.cancel();
    _winMessageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showWinMessage = false;
        });
      }
    });
  }

  @override
  void dispose() {
    socket.dispose();
    _controller.dispose();
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
    
    Gradient btnGradient = const LinearGradient(colors: [Color(0xFF334155), Color(0xFF1E293B)]);
    String btnText = 'WAITING';
    List<BoxShadow> btnShadow = [];
    
    if (isWaiting) {
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
        btnGradient = LinearGradient(colors: [const Color(0xFF10B981).withOpacity(0.6), const Color(0xFF059669).withOpacity(0.6)]);
        btnText = 'CASHED OUT\n${(betAmount * cashedOutMult).toStringAsFixed(2)}';
      }
    } else {
      if (isPlaced && !hasCashedOut) {
        btnGradient = LinearGradient(colors: [const Color(0xFFEF4444).withOpacity(0.6), const Color(0xFFB91C1C).withOpacity(0.6)]);
        btnText = 'LOST';
      } else if (hasCashedOut) {
        btnGradient = LinearGradient(colors: [const Color(0xFF10B981).withOpacity(0.6), const Color(0xFF059669).withOpacity(0.6)]);
        btnText = 'WON\n${(betAmount * cashedOutMult).toStringAsFixed(2)}';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155), width: 1.5),
        boxShadow: [
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
                    InkWell(
                      onTap: isWaiting && !isPlaced
                          ? () {
                              setState(() {
                                if (betAmount > 1.0) {
                                  if (betIndex == 1) { _betAmount1 -= 1.0; _betController1.text = _betAmount1.toStringAsFixed(2); }
                                  else { _betAmount2 -= 1.0; _betController2.text = _betAmount2.toStringAsFixed(2); }
                                }
                              });
                            }
                          : null,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Color(0xFF334155), shape: BoxShape.circle),
                        child: const Icon(Icons.remove, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('\$', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(
                      width: 50,
                      child: TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                        enabled: isWaiting && !isPlaced,
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null && parsed > 0) {
                            if (betIndex == 1) _betAmount1 = parsed;
                            else _betAmount2 = parsed;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: isWaiting && !isPlaced
                          ? () {
                              setState(() {
                                if (betIndex == 1) { _betAmount1 += 1.0; _betController1.text = _betAmount1.toStringAsFixed(2); }
                                else { _betAmount2 += 1.0; _betController2.text = _betAmount2.toStringAsFixed(2); }
                              });
                            }
                          : null,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Color(0xFF334155), shape: BoxShape.circle),
                        child: const Icon(Icons.add, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [20, 50, 100, 200, 500].map((amount) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: InkWell(
                          onTap: isWaiting && !isPlaced
                              ? () {
                                  setState(() {
                                    if (betIndex == 1) { _betAmount1 = amount.toDouble(); _betController1.text = _betAmount1.toStringAsFixed(2); }
                                    else { _betAmount2 = amount.toDouble(); _betController2.text = _betAmount2.toStringAsFixed(2); }
                                  });
                                }
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A), 
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF334155))
                            ),
                            child: Text('\$$amount', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () {
                if (isWaiting) {
                  _toggleBet(betIndex);
                } else if (isPlaying && isPlaced && !hasCashedOut) {
                  _cashOut(betIndex);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 56,
                decoration: BoxDecoration(
                  gradient: btnGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: btnShadow,
                ),
                child: Center(
                  child: Text(
                    btnText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.0),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBetsPanel() {
    bool isCrashed = _status == GameStatus.crashed;
    bool isPlaying = _status == GameStatus.playing || _status == GameStatus.spectating;

    // Combine player's own bets with community live bets
    final List<Map<String, dynamic>> displayBets = [];
    if (_isBetPlaced1) {
      displayBets.add({
        'id': 'my_bet_1',
        'isMe': true,
        'name': 'YOU (Bet 1)',
        'bet': _betAmount1,
        'cashedOut': _hasCashedOut1,
        'cashedOutMultiplier': _hasCashedOut1 ? _cashedOutMultiplier1 : null,
        'winAmount': _hasCashedOut1 ? _betAmount1 * _cashedOutMultiplier1 : null,
      });
    }
    if (_isBetPlaced2) {
      displayBets.add({
        'id': 'my_bet_2',
        'isMe': true,
        'name': 'YOU (Bet 2)',
        'bet': _betAmount2,
        'cashedOut': _hasCashedOut2,
        'cashedOutMultiplier': _hasCashedOut2 ? _cashedOutMultiplier2 : null,
        'winAmount': _hasCashedOut2 ? _betAmount2 * _cashedOutMultiplier2 : null,
      });
    }

    displayBets.addAll(_liveBets);

    // Dynamic Rank & Sort:
    // 1. Player's bets (isMe) always stay at the very top (#1).
    // 2. If flight started (PLAYING or CRASHED): Cashed-out winners rank top by highest multiplier.
    // 3. If in pre-game countdown (WAITING): High-Rollers rank top by Highest Bet Amount ($1000, $500, $200...).
    final bool isWaiting = _status == GameStatus.waiting;

    displayBets.sort((a, b) {
      if (a['isMe'] == true && b['isMe'] != true) return -1;
      if (b['isMe'] == true && a['isMe'] != true) return 1;

      if (!isWaiting) {
        final aWon = a['cashedOut'] == true;
        final bWon = b['cashedOut'] == true;
        if (aWon && !bWon) return -1;
        if (!aWon && bWon) return 1;

        if (aWon && bWon) {
          final aMult = ((a['cashedOutMultiplier'] ?? a['mult'] ?? 0) as num).toDouble();
          final bMult = ((b['cashedOutMultiplier'] ?? b['mult'] ?? 0) as num).toDouble();
          return bMult.compareTo(aMult);
        }
      }

      // During Pre-Game (WAITING): Sort by Highest Bet Amount descending
      final double aBet = ((a['bet'] ?? 0) as num).toDouble();
      final double bBet = ((b['bet'] ?? 0) as num).toDouble();
      return bBet.compareTo(aBet);
    });

    // Calculate total round bets pool
    final double totalPool = displayBets.fold(0.0, (sum, b) => sum + (((b['bet'] ?? 0) as num).toDouble()));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1.5)),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      const Text('POOL: ', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text(
                        '\$${totalPool.toStringAsFixed(2)}',
                        style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: displayBets.isEmpty
                ? const Center(
                    child: Text('Waiting for bets...', style: TextStyle(color: Colors.white38, fontSize: 13)),
                  )
                : ListView.builder(
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
                          border: rowBorder ?? Border(bottom: BorderSide(color: const Color(0xFF334155).withOpacity(0.4), width: 0.5)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              flex: 3,
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
                            Expanded(
                              flex: 2,
                              child: Text(
                                '\$${betAmt.toStringAsFixed(2)}',
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
                            Expanded(
                              flex: 3,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: isCashedOut
                                    ? AnimatedScale(
                                        duration: const Duration(milliseconds: 300),
                                        scale: isRecent ? 1.08 : 1.0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.greenAccent.withOpacity(isRecent ? 0.35 : 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.greenAccent.withOpacity(isRecent ? 0.9 : 0.5),
                                              width: isRecent ? 1.5 : 1.0,
                                            ),
                                            boxShadow: isRecent
                                                ? [BoxShadow(color: Colors.greenAccent.withOpacity(0.4), blurRadius: 8, spreadRadius: 1)]
                                                : null,
                                          ),
                                          child: Text(
                                            winAmt != null 
                                                ? '${mult != null ? "${(mult as num).toStringAsFixed(2)}x " : ""}+\$${winAmt.toStringAsFixed(2)}'
                                                : '${mult ?? ""}x',
                                            style: const TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
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
                            )
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium Dark Slate
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16.0,
        title: Row(
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
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
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16.0),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))
                ]
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    '\$${_balance.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          if (_showHistoryBar) _buildHistoryBar(),
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF334155), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))
                ]
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    if (_status != GameStatus.waiting)
                      PlaneGraph(
                        multiplier: _currentMultiplier,
                        isCrashed: _status == GameStatus.crashed,
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
                            Text(
                              '$_countdown',
                              style: const TextStyle(
                                color: Colors.white, 
                                fontSize: 80, 
                                fontWeight: FontWeight.w900,
                                shadows: [Shadow(color: Colors.white24, blurRadius: 20)]
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Center(
                        child: Text(
                          '${_currentMultiplier.toStringAsFixed(2)}x',
                          style: TextStyle(
                            color: _status == GameStatus.crashed ? Colors.redAccent : Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: (_status == GameStatus.crashed ? Colors.redAccent : Colors.lightBlueAccent).withOpacity(0.6),
                                blurRadius: 25,
                              )
                            ]
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
                    if (_showWinMessage)
                      Center(
                        child: TweenAnimationBuilder(
                          duration: const Duration(milliseconds: 600),
                          tween: Tween<double>(begin: 0.0, end: 1.0),
                          curve: Curves.elasticOut,
                          builder: (context, double val, child) {
                            return Transform.scale(
                              scale: val,
                              child: Opacity(
                                opacity: val.clamp(0.0, 1.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                                    borderRadius: BorderRadius.circular(30),
                                    boxShadow: [
                                      BoxShadow(color: const Color(0xFF10B981).withOpacity(0.5), blurRadius: 25, spreadRadius: 5)
                                    ],
                                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 2)
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'YOU WIN!',
                                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '\$${_winAmount.toStringAsFixed(2)}',
                                        style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900),
                                      ),
                                      Container(
                                        margin: const EdgeInsets.only(top: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(12)
                                        ),
                                        child: Text(
                                          '${_winMultiplier.toStringAsFixed(2)}x',
                                          style: const TextStyle(color: Colors.yellowAccent, fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
    );
  }
}

