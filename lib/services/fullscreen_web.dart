import 'dart:js' as js;

void toggleFullscreenImpl() {
  try {
    js.context.callMethod('toggleGameFullscreen');
  } catch (_) {}
}

bool isFullscreenImpl() {
  try {
    return js.context.callMethod('isGameFullscreen') == true;
  } catch (_) {
    return false;
  }
}

bool isIosWebImpl() {
  try {
    return js.context.callMethod('isIosDevice') == true;
  } catch (_) {
    return false;
  }
}

bool isAndroidWebImpl() {
  try {
    return js.context.callMethod('isAndroidDevice') == true;
  } catch (_) {
    return false;
  }
}

bool isPwaStandaloneImpl() {
  try {
    return js.context.callMethod('isPwaStandalone') == true;
  } catch (_) {
    return false;
  }
}

bool isPwaInstallAvailableImpl() {
  try {
    return js.context.callMethod('isPwaInstallAvailable') == true;
  } catch (_) {
    return false;
  }
}

bool triggerPwaPromptImpl() {
  try {
    return js.context.callMethod('triggerPwaPrompt') == true;
  } catch (_) {
    return false;
  }
}
