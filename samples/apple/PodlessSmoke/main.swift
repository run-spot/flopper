import Foundation
import FlopperKitKmp

final class SmokePlugin: NSObject, FlopperPlugin {
  let id = "podless-smoke"
  let runInBackground = false

  func onConnect(connection: FlopperConnection) {
    connection.send(method: "ping", payload: #"{"source":"podless-smoke"}"#)
  }

  func onDisconnect() {}
}

let config = FlopperConfigIos(
    appName: "PodlessSmoke",
    deviceModel: "iOS Simulator",
    osVersion: "0",
    enabled: true
)
let client = FlopperClient.companion.create(config: config)
let plugin = SmokePlugin()

client.addPlugin(plugin: plugin)
_ = client.getState()
_ = client.getStateSummary()
client.start()
client.stop()
