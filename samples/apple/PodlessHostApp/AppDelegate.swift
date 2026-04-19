import UIKit
import FlopperKitKmp

final class RuntimePlugin: NSObject, FlopperPlugin {
  let id = "podless-runtime"
  let runInBackground = false

  func onConnect(connection: FlopperConnection) {
    connection.send(method: "ping", payload: #"{"source":"podless-runtime"}"#)
  }

  func onDisconnect() {}
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let config = FlopperConfigIos(
        appName: "PodlessHostApp",
        deviceModel: UIDevice.current.model,
        osVersion: UIDevice.current.systemVersion,
        enabled: true
    )
    let client = FlopperClient.companion.create(config: config)
    client.addPlugin(plugin: RuntimePlugin())
    client.start()

    let summary = client.getStateSummary().entries
        .map { "\($0.name)=\($0.state)" }
        .joined(separator: ",")
    let payload = [
      "state=\(client.getState())",
      "connected=\(client.isConnected() ? "true" : "false")",
      "summary=\(summary)",
    ].joined(separator: "\n")

    let outputURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("flopper-runtime.txt")
    try? payload.write(to: outputURL, atomically: true, encoding: String.Encoding.utf8)

    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = UIViewController()
    window?.makeKeyAndVisible()

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      client.stop()
      exit(0)
    }

    return true
  }
}
