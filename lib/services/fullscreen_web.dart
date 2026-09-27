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
