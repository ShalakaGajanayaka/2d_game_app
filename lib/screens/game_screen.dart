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
  
  late AnimationController _controller;
  int _countdown = 15;
  
  late IO.Socket socket;
  double _serverStartTime = 0;
  
  @override
  void initState() {
    super.initState();
    
    // The controller is just used to trigger build frames smoothly for the animation.
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
    
    socket.connect();
    
    socket.onConnect((_) {
      debugPrint('Connected to server!');
    });

    socket.on('gameState', (data) {
      if (!mounted) return;
      
      setState(() {
        final serverStatus = data['status'];
        _countdown = data['countdown'];
        
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
    
    setState(() {
      _balance += currentBet * _currentMultiplier;
      if (betIndex == 1) {
        _hasCashedOut1 = true;
        _cashedOutMultiplier1 = _currentMultiplier;
      } else {
        _hasCashedOut2 = true;
        _cashedOutMultiplier2 = _currentMultiplier;
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
    
    Color btnColor = Colors.grey[700]!;
    String btnText = 'WAITING';
    
    if (isWaiting) {
      btnColor = isPlaced ? Colors.red : Colors.green;
      btnText = isPlaced ? 'CANCEL BET' : 'BET';
    } else if (isPlaying) {
      if (isPlaced && !hasCashedOut) {
        btnColor = Colors.orange;
        btnText = 'CASH OUT\n${(betAmount * _currentMultiplier).toStringAsFixed(2)}';
      } else if (hasCashedOut) {
        btnColor = Colors.green.withOpacity(0.5);
        btnText = 'CASHED OUT\n${(betAmount * cashedOutMult).toStringAsFixed(2)}';
      } else {
        btnColor = Colors.grey[700]!;
        btnText = 'WAITING';
      }
    } else {
      if (isPlaced && !hasCashedOut) {
        btnColor = Colors.red.withOpacity(0.5);
        btnText = 'LOST';
      } else if (hasCashedOut) {
        btnColor = Colors.green.withOpacity(0.5);
        btnText = 'WON\n${(betAmount * cashedOutMult).toStringAsFixed(2)}';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
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
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.white),
                      iconSize: 20,
                      onPressed: isWaiting && !isPlaced
                          ? () {
                              setState(() {
                                if (betAmount > 1.0) {
                                  if (betIndex == 1) { _betAmount1 -= 1.0; _betController1.text = _betAmount1.toStringAsFixed(2); }
                                  else { _betAmount2 -= 1.0; _betController2.text = _betAmount2.toStringAsFixed(2); }
                                }
                              });
                            }
                          : null,
                    ),
                    const Text('\$', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(
                      width: 60,
                      child: TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.white),
                      iconSize: 20,
                      onPressed: isWaiting && !isPlaced
                          ? () {
                              setState(() {
                                if (betIndex == 1) { _betAmount1 += 1.0; _betController1.text = _betAmount1.toStringAsFixed(2); }
                                else { _betAmount2 += 1.0; _betController2.text = _betAmount2.toStringAsFixed(2); }
                              });
                            }
                          : null,
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [20, 50, 100, 200, 500].map((amount) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.0),
                        child: InkWell(
                          onTap: isWaiting && !isPlaced
                              ? () {
                                  setState(() {
                                    if (betIndex == 1) { _betAmount1 = amount.toDouble(); _betController1.text = _betAmount1.toStringAsFixed(2); }
                                    else { _betAmount2 = amount.toDouble(); _betController2.text = _betAmount2.toStringAsFixed(2); }
                                  });
                                }
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(4)),
                            child: Text('\$$amount', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(width: 8),
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
              child: Container(
                height: 56,
                decoration: BoxDecoration(color: btnColor, borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Text(
                    btnText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
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
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Balance: \$${_balance.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 52,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                direction: Axis.vertical,
                spacing: 6.0,
                runSpacing: 6.0,
                children: _history.map((mult) {
                  Color color;
                  if (mult < 2.0) {
                    color = Colors.red;
                  } else if (mult < 5.0) {
                    color = const Color(0xFF9b59b6); // Purple
                  } else if (mult < 10.0) {
                    color = Colors.blue;
                  } else if (mult < 20.0) {
                    color = Colors.green;
                  } else if (mult < 50.0) {
                    color = Colors.orange;
                  } else {
                    color = const Color(0xFFFFD700); // Gold
                  }
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color, width: 1.0)
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${mult.toStringAsFixed(2)}x',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
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
                              style: TextStyle(color: Colors.grey, fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '$_countdown s',
                              style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    else
                      Center(
                        child: Text(
                          '${_currentMultiplier.toStringAsFixed(2)}x',
                          style: TextStyle(
                            color: _status == GameStatus.crashed ? Colors.red : Colors.white,
                            fontSize: 64,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (_status == GameStatus.crashed)
                      const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: 150),
                            Text(
                              'FLEW AWAY!',
                              style: TextStyle(color: Colors.red, fontSize: 28, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Expanded(child: _buildBetPanel(1)),
                  Expanded(child: _buildBetPanel(2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

