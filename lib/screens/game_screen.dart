import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
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
  double _crashPoint = 1.0;
  
  late AnimationController _controller;
  Timer? _countdownTimer;
  int _countdown = 15;
  bool _isBetPlaced = false;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20), // Max duration for maximum crash point
    )..addListener(() {
        setState(() {
          // Calculate exponential multiplier growth based on time
          double time = _controller.value * 20; // 0 to 20 seconds
          _currentMultiplier = 1.0 + pow(time, 2.5) / 10;
          
          if (_currentMultiplier >= _crashPoint) {
            _crash();
          }
        });
    });
    
    // Start initial countdown when screen loads
    _startCountdown();
  }

  void _startCountdown() {
    setState(() {
      _status = GameStatus.waiting;
      _countdown = 15;
      _currentMultiplier = 1.0;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          timer.cancel();
          _startGame();
        }
      });
    });
  }

  void _startGame() {
    setState(() {
      if (_isBetPlaced) {
        _status = GameStatus.playing;
      } else {
        _status = GameStatus.spectating;
      }
      
      _currentMultiplier = 1.0;
      
      // Generate a crash point with heavy bias towards lower numbers
      _crashPoint = _generateCrashPoint();
      
      _controller.reset();
      _controller.forward();
    });
  }

  double _generateCrashPoint() {
    final random = Random();
    // E = 100 / X (where X is a random uniform number between 1 and 100)
    // This gives a classic house-edge curve where lower numbers are very common
    double e = 100 / (random.nextDouble() * 100 + 1); 
    if (e < 1.01) e = 1.01;
    return double.parse((e).toStringAsFixed(2));
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
      // Do NOT stop the controller; let the plane keep flying for spectators!
    });
  }

  void _crash() {
    setState(() {
      _status = GameStatus.crashed;
      _currentMultiplier = _crashPoint;
      _controller.stop();
      _isBetPlaced = false;
    });
    
    // Wait 3 seconds to show "Crashed" before starting the next 15s timer
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _startCountdown();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
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
              child: Stack(
                children: [
                  if (_status != GameStatus.waiting)
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: PlaneGraph(
                        multiplier: _currentMultiplier,
                        isCrashed: _status == GameStatus.crashed,
                      ),
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
