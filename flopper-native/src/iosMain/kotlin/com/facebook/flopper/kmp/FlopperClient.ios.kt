@file:OptIn(ExperimentalForeignApi::class)

package com.facebook.flopper.kmp

import com.facebook.flopper.kmp.apple.shim.flopper_apple_client_add_plugin
import com.facebook.flopper.kmp.apple.shim.flopper_apple_client_copy_state
import com.facebook.flopper.kmp.apple.shim.flopper_apple_client_copy_state_summary_json
import com.facebook.flopper.kmp.apple.shim.flopper_apple_client_is_available
import com.facebook.flopper.kmp.apple.shim.flopper_apple_client_is_connected
import com.facebook.flopper.kmp.apple.shim.flopper_apple_client_remove_plugin
import com.facebook.flopper.kmp.apple.shim.flopper_apple_client_start
import com.facebook.flopper.kmp.apple.shim.flopper_apple_client_stop
import com.facebook.flopper.kmp.apple.shim.flopper_apple_connection_receive
import com.facebook.flopper.kmp.apple.shim.flopper_apple_connection_report_error
import com.facebook.flopper.kmp.apple.shim.flopper_apple_connection_send
import com.facebook.flopper.kmp.apple.shim.flopper_apple_plugin_create
import com.facebook.flopper.kmp.apple.shim.flopper_apple_release
import com.facebook.flopper.kmp.apple.shim.flopper_apple_buffer_free
import com.facebook.flopper.kmp.apple.shim.flopper_apple_responder_error
import com.facebook.flopper.kmp.apple.shim.flopper_apple_responder_success
import com.facebook.flopper.kmp.apple.shim.flopper_apple_shared_client
import com.facebook.flopper.kmp.apple.shim.FlopperKmpDidConnectCallback
import com.facebook.flopper.kmp.apple.shim.FlopperKmpDidDisconnectCallback
import com.facebook.flopper.kmp.apple.shim.FlopperKmpReceiverCallback
import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.COpaquePointer
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.StableRef
import kotlinx.cinterop.asStableRef
import kotlinx.cinterop.staticCFunction
import kotlinx.cinterop.toKString
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
  private val pluginAdapters = LinkedHashMap<String, ApplePluginAdapter>()
  private val clientHandle: COpaquePointer? = if (flopper_apple_client_is_available()) {
    flopper_apple_shared_client()
  } else {
    null
  }

  fun addPlugin(plugin: FlopperPlugin) {
    pluginsById[plugin.id] = plugin
    if (clientHandle != null) {
      val adapter = ApplePluginAdapter(plugin)
      pluginAdapters[plugin.id] = adapter
      flopper_apple_client_add_plugin(clientHandle, adapter.pluginHandle)
    }
  }

  fun getPlugin(id: String): FlopperPlugin? = pluginsById[id]

  fun removePlugin(plugin: FlopperPlugin) {
    pluginsById.remove(plugin.id)
    pluginAdapters.remove(plugin.id)?.let { adapter ->
      if (clientHandle != null) {
        flopper_apple_client_remove_plugin(clientHandle, adapter.pluginHandle)
      }
      adapter.dispose()
    }
  }

  fun start() {
    if (config.enabled && clientHandle != null) {
      flopper_apple_client_start(clientHandle)
    }
  }

  fun stop() {
    if (clientHandle != null) {
      flopper_apple_client_stop(clientHandle)
    }
  }

  fun isConnected(): Boolean = clientHandle != null && flopper_apple_client_is_connected(clientHandle)

  fun getState(): String {
    if (clientHandle == null) {
      return "UNAVAILABLE"
    }
    val value = flopper_apple_client_copy_state(clientHandle) ?: return "UNKNOWN"
    return try {
      value.toKString()
    } finally {
      flopper_apple_buffer_free(value)
    }
  }

  fun getStateSummary(): FlopperStateSummary {
    if (clientHandle == null) {
      return FlopperStateSummary()
    }
    val summaryJson = flopper_apple_client_copy_state_summary_json(clientHandle) ?: return FlopperStateSummary()
    return try {
      val raw = summaryJson.toKString()
      parseStateSummary(raw)
    } finally {
      flopper_apple_buffer_free(summaryJson)
    }
  }
}

private class ApplePluginAdapter(
    private val plugin: FlopperPlugin,
) {
  private val pluginRef = StableRef.create(this)
  val pluginHandle: COpaquePointer? = flopper_apple_plugin_create(
      plugin.id,
      plugin.runInBackground,
      pluginRef.asCPointer(),
      didConnectCallback,
      didDisconnectCallback,
  )

  fun onConnect(connectionHandle: COpaquePointer?) {
    plugin.onConnect(AppleFlopperConnection(connectionHandle))
  }

  fun onDisconnect() {
    plugin.onDisconnect()
  }

  fun dispose() {
    pluginHandle?.let { flopper_apple_release(it) }
    pluginRef.dispose()
  }
}

private class AppleFlopperConnection(
    private val connectionHandle: COpaquePointer?,
) : FlopperConnection {
  private val receiverRefs = mutableListOf<StableRef<AppleReceiverCallback>>()

  override fun send(method: String, payload: String?) {
    connectionHandle?.let { flopper_apple_connection_send(it, method, payload) }
  }

  override fun receive(
      method: String,
      receiver: (payload: String?, responder: FlopperResponder) -> Unit,
  ) {
    val callbackRef = StableRef.create(AppleReceiverCallback(receiver))
    receiverRefs += callbackRef
    connectionHandle?.let {
      flopper_apple_connection_receive(
          it,
          method,
          callbackRef.asCPointer(),
          receiverCallback,
      )
    }
  }

  override fun reportError(reason: String, stackTrace: String?) {
    connectionHandle?.let { flopper_apple_connection_report_error(it, reason, stackTrace) }
  }
}

private class AppleResponder(
    private val responderHandle: COpaquePointer?,
) : FlopperResponder {
  override fun success(response: String?) {
    responderHandle?.let { flopper_apple_responder_success(it, response) }
  }

  override fun error(response: String?) {
    responderHandle?.let { flopper_apple_responder_error(it, response) }
  }
}

private class AppleReceiverCallback(
    val block: (payload: String?, responder: FlopperResponder) -> Unit,
)

private fun parseStateSummary(raw: String): FlopperStateSummary {
  if (raw.isBlank()) {
    return FlopperStateSummary()
  }

  val entries = "\"name\"\\s*:\\s*\"([^\"]+)\".*?\"state\"\\s*:\\s*\"([^\"]+)\""
      .toRegex()
      .findAll(raw)
      .map { match ->
        FlopperStateSummary.Entry(
            name = match.groupValues[1],
            state = match.groupValues[2],
        )
      }
      .toList()
  return FlopperStateSummary(entries)
}

private val didConnectCallback: FlopperKmpDidConnectCallback = staticCFunction { pluginRef: COpaquePointer?, connectionRef: COpaquePointer? ->
  pluginRef?.asStableRef<ApplePluginAdapter>()?.get()?.onConnect(connectionRef)
}

private val didDisconnectCallback: FlopperKmpDidDisconnectCallback = staticCFunction { pluginRef: COpaquePointer? ->
  pluginRef?.asStableRef<ApplePluginAdapter>()?.get()?.onDisconnect()
}

private val receiverCallback: FlopperKmpReceiverCallback = staticCFunction { receiverRef: COpaquePointer?, paramsJson: CPointer<ByteVar>?, responderRef: COpaquePointer? ->
  val callback = receiverRef?.asStableRef<AppleReceiverCallback>()?.get() ?: return@staticCFunction
  callback.block(
      paramsJson?.toKString(),
      AppleResponder(responderRef),
  )
}
