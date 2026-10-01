import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sound_stub.dart'
    if (dart.library.js) 'sound_web.dart' as impl;

class SoundService {
  static bool _isMuted = true;
  static bool _initialized = false;

  static bool get isMuted => _isMuted;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isMuted = prefs.getBool('skyrush_sound_muted') ?? true;
      impl.setSoundMutedImpl(_isMuted);
    } catch (_) {}
  }

  static Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    impl.setSoundMutedImpl(muted);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('skyrush_sound_muted', muted);
    } catch (_) {}
  }

  static void startFlight() {
    impl.startFlightSoundImpl();
  }

  static void updateMultiplier(double mult) {
    impl.updateFlightSoundImpl(mult);
  }

  static void stopFlight({bool crashed = false}) {
    impl.stopFlightSoundImpl(crashed);
  }

  static void playCashout() {
    impl.playCashoutSoundImpl();
  }

  static void playCrash() {
    impl.playCrashSoundImpl();
  }

  // UPGRADE_TODO: Background ambient music temporarily disabled for upcoming studio soundtrack upgrade.
  static void startMusic() {
    // impl.startMusicImpl();
  }

  static void stopMusic() {
    impl.stopMusicImpl();
  }
}
