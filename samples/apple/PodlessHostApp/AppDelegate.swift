import UIKit
import FlopperKitKmp
import Foundation

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
  private let triggerButton = UIButton(type: .system)
  var onTriggerRequest: (() -> Void)?

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .systemBackground
    statusLabel.numberOfLines = 0
    statusLabel.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
    statusLabel.textColor = .label
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    triggerButton.translatesAutoresizingMaskIntoConstraints = false
    triggerButton.setTitle("Send API Request", for: .normal)
    triggerButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    triggerButton.backgroundColor = .systemBlue
    triggerButton.setTitleColor(.white, for: .normal)
    triggerButton.layer.cornerRadius = 12
    triggerButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
    triggerButton.addTarget(self, action: #selector(handleTriggerTap), for: .touchUpInside)

    let stackView = UIStackView(arrangedSubviews: [triggerButton, statusLabel])
    stackView.axis = .vertical
    stackView.spacing = 24
    stackView.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(stackView)
    NSLayoutConstraint.activate([
      stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      triggerButton.heightAnchor.constraint(equalToConstant: 50),
    ])
  }

  func updateStatus(_ payload: String) {
    statusLabel.text = payload
  }

  @objc
  private func handleTriggerTap() {
    onTriggerRequest?()
  }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private let runtimeViewController = RuntimeViewController()
  private var flopperClient: FlopperClient?
  private let networkProbePlugin = IosNetworkProbePlugin(
    urlString: "https://jsonplaceholder.typicode.com/todos/1",
    requestHeaderName: "Accept",
    requestHeaderValue: "application/json"
  )

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
    client.addPlugin(plugin: networkProbePlugin)
    client.start()
    NSLog("FLOPPER-APP launched state=%@", client.getState())

    window = UIWindow(frame: UIScreen.main.bounds)
    runtimeViewController.onTriggerRequest = { [weak self] in
      NSLog("FLOPPER-APP send API request tapped")
      self?.networkProbePlugin.triggerRequest()
      self?.renderStatus()
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.renderStatus()
      }
    }
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
