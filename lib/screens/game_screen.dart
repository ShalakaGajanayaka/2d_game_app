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
  double _betAmount = 10.0;
  
  double _currentMultiplier = 1.0;
  
  late AnimationController _controller;
  int _countdown = 15;
  bool _isBetPlaced = false;
  
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
        if (_status == GameStatus.playing || _status == GameStatus.spectating || _status == GameStatus.cashedOut) {
          setState(() {
            double elapsedSeconds = (DateTime.now().millisecondsSinceEpoch - _serverStartTime) / 1000;
            if (elapsedSeconds > 0) {
               // Calculate multiplier locally exactly like the server to ensure 60fps smooth animation
               _currentMultiplier = 1.0 + pow(elapsedSeconds, 2.5) / 10;
            }
          });
        }
    });

    _initSocket();
  }

  void _initSocket() {
    // Connect to the NestJS server using API from .env
    String serverUrl = dotenv.env['SERVER_API_URL']!;
    
    // Automatically patch localhost to 10.0.2.2 for Android emulators
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
           // Keep cashedOut state if they already cashed out this round
           if (_status == GameStatus.cashedOut) {
              newStatus = GameStatus.cashedOut;
           } else {
              newStatus = _isBetPlaced ? GameStatus.playing : GameStatus.spectating;
           }
        } else {
           newStatus = GameStatus.crashed;
        }

        // Handle State Transitions
        if (_status != newStatus) {
           if (serverStatus == 'playing' && _status == GameStatus.waiting) {
              // Game just started!
              _serverStartTime = data['startTime'].toDouble();
              _controller.repeat(); 
           } 
           else if (newStatus == GameStatus.crashed) {
              _controller.stop();
              _currentMultiplier = data['currentMultiplier'].toDouble();
              _isBetPlaced = false;
           }
           else if (newStatus == GameStatus.waiting) {
              _controller.stop();
              _currentMultiplier = 1.0;
           }
           _status = newStatus;
        }
      });
    });
  }

  void _toggleBet() {
    if (_status == GameStatus.waiting) {
      setState(() {
        if (_isBetPlaced) {
          // Cancel bet
          _balance += _betAmount;
          _isBetPlaced = false;
        } else {
          // Place bet
          if (_balance >= _betAmount) {
            _balance -= _betAmount;
            _isBetPlaced = true;
          }
        }
      });
    }
  }

  void _cashOut() {
    if (_status != GameStatus.playing) return;
    
    setState(() {
      _status = GameStatus.cashedOut;
      _balance += _betAmount * _currentMultiplier;
      _isBetPlaced = false;
    });
  }

  @override
  void dispose() {
    socket.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Aviator Crash'),
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
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
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
                    if (_status == GameStatus.cashedOut)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 150),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.green, width: 2)
                              ),
                              child: Text(
                                'WON \$${(_betAmount * _currentMultiplier).toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.green, fontSize: 24, fontWeight: FontWeight.bold),
                              ),
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
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Bet Amount', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.white),
                                onPressed: _status == GameStatus.waiting && !_isBetPlaced
                                    ? () {
                                        setState(() {
                                          if (_betAmount > 1.0) _betAmount -= 1.0;
                                        });
                                      }
                                    : null,
                              ),
                              Text('\$${_betAmount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 24)),
                              IconButton(
                                icon: const Icon(Icons.add_circle, color: Colors.white),
                                onPressed: _status == GameStatus.waiting && !_isBetPlaced
                                    ? () {
                                        setState(() {
                                          _betAmount += 1.0;
                                        });
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_status == GameStatus.waiting) {
                          _toggleBet();
                        } else if (_status == GameStatus.playing) {
                          _cashOut();
                        }
                      },
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: _status == GameStatus.playing
                              ? Colors.orange
                              : (_status == GameStatus.waiting
                                  ? (_isBetPlaced ? Colors.red : Colors.green)
                                  : Colors.grey),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            _status == GameStatus.playing
                                ? 'CASH OUT'
                                : (_status == GameStatus.waiting
                                    ? (_isBetPlaced ? 'CANCEL BET' : 'BET')
                                    : 'WAITING'),
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
