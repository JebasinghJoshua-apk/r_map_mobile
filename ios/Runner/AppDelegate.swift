import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyCY-mEvaGFsjSCLSNruAE2jNtfEKOYmgTU")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeepLinkPlugin") {
      DeepLinkPlugin.register(with: registrar)
    }
  }
}

/// iOS counterpart of the deep-link handling in Android's MainActivity.
/// Receives Universal Links (https://rmap.in/s/..., /property/..., etc.) and
/// forwards them to Dart over the `com.rmap.mobile/deeplink` channel.
final class DeepLinkPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private let channel: FlutterMethodChannel
  private var initialLink: String?
  private var dartReady = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.rmap.mobile/deeplink", binaryMessenger: registrar.messenger())
    let instance = DeepLinkPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    if #available(iOS 13.0, *) {
      registrar.addSceneDelegate(instance)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getInitialLink":
      dartReady = true
      result(initialLink)
      initialLink = nil
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // Cold start (scene-based lifecycle): link arrives in the connection options.
  @available(iOS 13.0, *)
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let options = connectionOptions else { return false }
    for activity in options.userActivities where deliver(activity) {
      return true
    }
    return false
  }

  // Warm start (app running or suspended).
  @available(iOS 13.0, *)
  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
    return deliver(userActivity)
  }

  // Fallback for non-scene lifecycle.
  func application(
    _ application: UIApplication, continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([Any]) -> Void
  ) -> Bool {
    return deliver(userActivity)
  }

  private func deliver(_ activity: NSUserActivity) -> Bool {
    guard activity.activityType == NSUserActivityTypeBrowsingWeb,
      let url = activity.webpageURL?.absoluteString
    else { return false }
    if dartReady {
      channel.invokeMethod("onNewLink", arguments: url)
    } else {
      // Dart hasn't asked yet – stash for getInitialLink.
      initialLink = url
    }
    return true
  }
}
