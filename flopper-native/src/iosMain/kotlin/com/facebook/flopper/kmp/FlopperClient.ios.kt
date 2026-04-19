package com.facebook.flopper.kmp

import kotlin.collections.LinkedHashMap

actual class FlopperClient private constructor(
    private val runtime: IosFlopperRuntime,
) {
  actual companion object {
    actual fun create(config: FlopperConfig): FlopperClient {
      val iosConfig = config as? FlopperConfig.Ios
          ?: error("FlopperClient.create on iOS requires FlopperConfig.Ios")
      return FlopperClient(IosFlopperRuntime(iosConfig))
    }
  }

  actual fun addPlugin(plugin: FlopperPlugin) = runtime.addPlugin(plugin)

  actual fun getPlugin(id: String): FlopperPlugin? = runtime.getPlugin(id)

  actual fun removePlugin(plugin: FlopperPlugin) = runtime.removePlugin(plugin)

  actual fun start() = runtime.start()

  actual fun stop() = runtime.stop()

  actual fun isConnected(): Boolean = runtime.isConnected()

  actual fun getState(): String = runtime.getState()

  actual fun getStateSummary(): FlopperStateSummary = runtime.getStateSummary()
}

private class IosFlopperRuntime(
    private val config: FlopperConfig.Ios,
) {
  private val pluginsById = LinkedHashMap<String, FlopperPlugin>()
  private var connection: InMemoryFlopperConnection? = null
  private var connected = false

  fun addPlugin(plugin: FlopperPlugin) {
    pluginsById[plugin.id] = plugin
    if (connected) {
      plugin.onConnect(connection ?: InMemoryFlopperConnection())
    }
  }

  fun getPlugin(id: String): FlopperPlugin? = pluginsById[id]

  fun removePlugin(plugin: FlopperPlugin) {
    pluginsById.remove(plugin.id)
    if (connected) {
      plugin.onDisconnect()
    }
  }

  fun start() {
    if (!config.enabled || connected) {
      return
    }
    val activeConnection = InMemoryFlopperConnection()
    connection = activeConnection
    connected = true
    pluginsById.values.forEach { it.onConnect(activeConnection) }
  }

  fun stop() {
    if (!connected) {
      return
    }
    pluginsById.values.forEach { it.onDisconnect() }
    connected = false
    connection = null
  }

  fun isConnected(): Boolean = connected

  fun getState(): String = if (connected) "CONNECTED" else "DISCONNECTED"

  fun getStateSummary(): FlopperStateSummary = FlopperStateSummary(
      entries = listOf(
          FlopperStateSummary.Entry("transport", if (connected) "SUCCESS" else "UNKNOWN"),
          FlopperStateSummary.Entry("plugins", pluginsById.size.toString()),
      ),
  )
}

private class InMemoryFlopperConnection : FlopperConnection {
  private val receivers = LinkedHashMap<String, (String?, FlopperResponder) -> Unit>()

  override fun send(method: String, payload: String?) {
    receivers[method]?.invoke(payload, InMemoryFlopperResponder())
  }

  override fun receive(
      method: String,
      receiver: (payload: String?, responder: FlopperResponder) -> Unit,
  ) {
    receivers[method] = receiver
  }

  override fun reportError(reason: String, stackTrace: String?) {
    // The Apple-side native bridge is introduced as a separate packaging artifact.
    // The KMP runtime keeps plugin lifecycle valid even before native transport is linked.
  }
}

private class InMemoryFlopperResponder : FlopperResponder {
  override fun success(response: String?) {}

  override fun error(response: String?) {}
}
