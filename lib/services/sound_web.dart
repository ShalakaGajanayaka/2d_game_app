import 'dart:js' as js;

void startFlightSoundImpl() {
  try {
    final skyrushAudio = js.context['SkyRushAudio'];
    if (skyrushAudio != null) {
      skyrushAudio.callMethod('startFlight');
    }
  } catch (_) {}
}

void updateFlightSoundImpl(double mult) {
  try {
    final skyrushAudio = js.context['SkyRushAudio'];
    if (skyrushAudio != null) {
      skyrushAudio.callMethod('updateFlight', [mult]);
    }
  } catch (_) {}
}

void stopFlightSoundImpl(bool crashed) {
  try {
    final skyrushAudio = js.context['SkyRushAudio'];
    if (skyrushAudio != null) {
      skyrushAudio.callMethod('stopFlight', [crashed]);
    }
  } catch (_) {}
}

void playCashoutSoundImpl() {
  try {
    final skyrushAudio = js.context['SkyRushAudio'];
    if (skyrushAudio != null) {
      skyrushAudio.callMethod('playCashout');
    }
  } catch (_) {}
}

void playCrashSoundImpl() {
  try {
    final skyrushAudio = js.context['SkyRushAudio'];
    if (skyrushAudio != null) {
      skyrushAudio.callMethod('playCrash');
    }
  } catch (_) {}
}

void setSoundMutedImpl(bool muted) {
  try {
    final skyrushAudio = js.context['SkyRushAudio'];
    if (skyrushAudio != null) {
      skyrushAudio.callMethod('setMuted', [muted]);
    }
  } catch (_) {}
}

bool isSoundMutedImpl() {
  try {
    final skyrushAudio = js.context['SkyRushAudio'];
    if (skyrushAudio != null) {
      return skyrushAudio.callMethod('isMuted') == true;
    }
  } catch (_) {}
  return false;
}

void startMusicImpl() {
  try {
    final skyrushAudio = js.context['SkyRushAudio'];
    if (skyrushAudio != null) {
      skyrushAudio.callMethod('startMusic');
    }
  } catch (_) {}
}

void stopMusicImpl() {
  try {
    final skyrushAudio = js.context['SkyRushAudio'];
    if (skyrushAudio != null) {
      skyrushAudio.callMethod('stopMusic');
    }
  } catch (_) {}
}

