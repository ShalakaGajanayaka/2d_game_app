import 'fullscreen_stub.dart'
    if (dart.library.js) 'fullscreen_web.dart' as impl;

class FullscreenService {
  static void toggleFullscreen() {
    impl.toggleFullscreenImpl();
  }

  static bool isFullscreen() {
    return impl.isFullscreenImpl();
  }

  static bool isIosWeb() {
    return impl.isIosWebImpl();
  }

  static bool isAndroidWeb() {
    return impl.isAndroidWebImpl();
  }

  static bool isPwaStandalone() {
    return impl.isPwaStandaloneImpl();
  }

  static bool isPwaInstallAvailable() {
    return impl.isPwaInstallAvailableImpl();
  }

  static bool triggerPwaPrompt() {
    return impl.triggerPwaPromptImpl();
  }
}

