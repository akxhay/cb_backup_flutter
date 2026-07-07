import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let channelName = "com.xharma.cbbackup/thumbnail"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: engineBridge.applicationRegistrar.messenger())
    
    channel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "getVideoThumbnail" {
        guard let args = call.arguments as? [String: Any],
              let videoPath = args["videoPath"] as? String,
              let thumbnailPath = args["thumbnailPath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing videoPath or thumbnailPath", details: nil))
          return
        }
        
        let fileURL = URL(fileURLWithPath: videoPath)
        let asset = AVAsset(url: fileURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let time = CMTimeMake(value: 1, timescale: 60)
        do {
          let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
          let uiImage = UIImage(cgImage: cgImage)
          
          if let data = uiImage.jpegData(compressionQuality: 0.75) {
            let thumbURL = URL(fileURLWithPath: thumbnailPath)
            try data.write(to: thumbURL)
            result(thumbnailPath)
          } else {
            result(FlutterError(code: "GEN_ERROR", message: "Failed to compress image data", details: nil))
          }
        } catch {
          result(FlutterError(code: "EXCEPTION", message: error.localizedDescription, details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
  }
}
