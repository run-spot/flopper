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
  private var flopperClient: FlopperClient?

  private func renderStatus() {
    guard let client = flopperClient else {
      return
    }

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
    runtimeViewController.updateStatus(payload)
  }

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
    flopperClient = client
    client.addPlugin(plugin: RuntimePlugin())
    client.addPlugin(plugin: IosNetworkProbePlugin(
      urlString: "https://jsonplaceholder.typicode.com/todos/1",
      requestHeaderName: "Accept",
      requestHeaderValue: "application/json"
    ))
    client.start()

    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = runtimeViewController
    window?.makeKeyAndVisible()
    renderStatus()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.renderStatus()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
      self?.renderStatus()
    }

    if ProcessInfo.processInfo.environment["FLOPPER_EXIT_AFTER_LAUNCH"] == "1" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
        self?.renderStatus()
        client.stop()
        exit(0)
      }
    }

    return true
  }
}
