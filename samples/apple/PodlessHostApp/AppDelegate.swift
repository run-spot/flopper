import UIKit
import FlopperKitKmp

private func jsonString(_ value: Any) -> String? {
  guard JSONSerialization.isValidJSONObject(value) else {
    return nil
  }
  guard let data = try? JSONSerialization.data(withJSONObject: value, options: []) else {
    return nil
  }
  return String(data: data, encoding: .utf8)
}

private func headersArray(_ headers: [AnyHashable: Any]?) -> [[String: String]] {
  guard let headers else {
    return []
  }
  return headers.compactMap { key, value in
    guard let valueString = value as? CustomStringConvertible else {
      return nil
    }
    return [
      "key": key.description,
      "value": valueString.description,
    ]
  }
}

final class RuntimePlugin: NSObject, FlopperPlugin {
  let id = "podless-runtime"
  let runInBackground = false

  func onConnect(connection: FlopperConnection) {
    connection.send(method: "ping", payload: #"{"source":"podless-runtime"}"#)
  }

  func onDisconnect() {}
}

final class NetworkProbePlugin: NSObject, FlopperPlugin {
  let id = "Network"
  let runInBackground = false

  private var connection: FlopperConnection?

  func onConnect(connection: FlopperConnection) {
    self.connection = connection
    sendProbeRequest()
  }

  func onDisconnect() {
    connection = nil
  }

  private func sendProbeRequest() {
    guard let connection,
          let url = URL(string: "https://jsonplaceholder.typicode.com/todos/1") else {
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("application/json", forHTTPHeaderField: "Accept")

    let requestId = UUID().uuidString
    let requestPayload: [String: Any] = [
      "id": requestId,
      "timestamp": Date().timeIntervalSince1970 * 1000,
      "method": request.httpMethod ?? "GET",
      "url": request.url?.absoluteString ?? url.absoluteString,
      "headers": headersArray(request.allHTTPHeaderFields),
      "data": NSNull(),
    ]
    connection.send(method: "newRequest", payload: jsonString(requestPayload))

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self, let connection = self.connection else {
        return
      }

      let httpResponse = response as? HTTPURLResponse
      let bodyText: Any
      if let data, let utf8 = String(data: data, encoding: .utf8) {
        bodyText = utf8
      } else if let error {
        bodyText = error.localizedDescription
      } else {
        bodyText = NSNull()
      }

      let responsePayload: [String: Any] = [
        "id": requestId,
        "timestamp": Date().timeIntervalSince1970 * 1000,
        "status": httpResponse?.statusCode ?? 0,
        "reason": HTTPURLResponse.localizedString(forStatusCode: httpResponse?.statusCode ?? 0),
        "headers": headersArray(httpResponse?.allHeaderFields),
        "data": bodyText,
        "isMock": false,
      ]
      connection.send(method: "newResponse", payload: jsonString(responsePayload))
    }.resume()
  }
}

final class RuntimeViewController: UIViewController {
  private let statusLabel = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .systemBackground
    statusLabel.numberOfLines = 0
    statusLabel.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
    statusLabel.textColor = .label
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(statusLabel)
    NSLayoutConstraint.activate([
      statusLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      statusLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  func updateStatus(_ payload: String) {
    statusLabel.text = payload
  }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private let runtimeViewController = RuntimeViewController()

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
    client.addPlugin(plugin: NetworkProbePlugin())
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
    runtimeViewController.updateStatus(payload)
    window?.rootViewController = runtimeViewController
    window?.makeKeyAndVisible()

    if ProcessInfo.processInfo.environment["FLOPPER_EXIT_AFTER_LAUNCH"] == "1" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        client.stop()
        exit(0)
      }
    }

    return true
  }
}
