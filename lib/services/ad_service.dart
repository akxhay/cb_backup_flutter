import 'package:flutter/foundation.dart';
import 'package:facebook_audience_network/facebook_audience_network.dart';

class AdService {
  // Placement IDs (Use test IDs in development)
  static String get bannerPlacementId {
    if (kDebugMode) {
      return 'IMG_16_9_APP_INSTALL#YOUR_PLACEMENT_ID';
    }
    return 'YOUR_REAL_BANNER_PLACEMENT_ID';
  }

  static String get interstitialPlacementId {
    if (kDebugMode) {
      return 'IMG_16_9_APP_INSTALL#YOUR_PLACEMENT_ID';
    }
    return 'YOUR_REAL_INTERSTITIAL_PLACEMENT_ID';
  }

  static bool _isInterstitialAdLoaded = false;

  static Future<void> init() async {
    try {
      await FacebookAudienceNetwork.init(
        iOSAdvertiserTrackingEnabled: true,
      );
      // Pre-load interstitial ad
      loadInterstitialAd();
    } catch (e) {
      debugPrint('AdService initialization failed: $e');
    }
  }

  static void loadInterstitialAd() {
    try {
      FacebookInterstitialAd.loadInterstitialAd(
        placementId: interstitialPlacementId,
        listener: (result, value) {
          debugPrint('Interstitial Ad: $result -> $value');
          if (result == InterstitialAdResult.LOADED) {
            _isInterstitialAdLoaded = true;
          } else if (result == InterstitialAdResult.DISMISSED ||
              result == InterstitialAdResult.ERROR) {
            _isInterstitialAdLoaded = false;
            // Re-load on dismiss/error
            if (result == InterstitialAdResult.DISMISSED) {
              loadInterstitialAd();
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Error loading interstitial: $e');
    }
  }

  static Future<bool> showInterstitialAd() async {
    if (_isInterstitialAdLoaded) {
      try {
        await FacebookInterstitialAd.showInterstitialAd();
        _isInterstitialAdLoaded = false;
        return true;
      } catch (e) {
        debugPrint('Error showing interstitial: $e');
      }
    } else {
      debugPrint('Interstitial ad not loaded yet, requesting load...');
      loadInterstitialAd();
    }
    return false;
  }
}
