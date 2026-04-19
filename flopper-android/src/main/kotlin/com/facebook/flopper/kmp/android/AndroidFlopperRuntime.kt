package com.facebook.flopper.kmp.android

import android.content.Context
import android.os.Build
import com.facebook.flipper.android.AndroidFlipperClient
import com.facebook.flipper.core.FlipperArray
import com.facebook.flipper.core.FlipperClient as NativeFlipperClient
import com.facebook.flipper.core.FlipperConnection as NativeFlipperConnection
import com.facebook.flipper.core.FlipperObject
import com.facebook.flipper.core.FlipperPlugin as NativeFlipperPlugin
import com.facebook.flipper.core.FlipperReceiver
import com.facebook.flipper.core.FlipperResponder as NativeFlipperResponder
import com.facebook.flipper.core.StateSummary
import com.facebook.flopper.kmp.FlopperConfig
import com.facebook.flopper.kmp.FlopperConnection
import com.facebook.flopper.kmp.FlopperPlugin
import com.facebook.flopper.kmp.FlopperResponder
import com.facebook.flopper.kmp.FlopperStateSummary
import java.util.LinkedHashMap

class AndroidFlopperRuntime private constructor(
    private val delegate: NativeFlipperClient,
) {
  private val adaptersByPlugin = LinkedHashMap<FlopperPlugin, AndroidPluginAdapter>()
  private val pluginsById = LinkedHashMap<String, FlopperPlugin>()

  companion object {
    fun create(config: FlopperConfig): AndroidFlopperRuntime {
      val androidConfig = config as? FlopperConfig.Android
          ?: error("Android runtime requires FlopperConfig.Android")
      val context = androidConfig.contextHandle as? Context
          ?: error("FlopperConfig.Android.contextHandle must be an android.content.Context")

      val delegate = if (androidConfig.enabled) {
        if (androidConfig.clientId != null ||
            androidConfig.deviceName != null ||
            androidConfig.processName != null ||
            androidConfig.packageName != null
        ) {
          AndroidFlipperClient.getInstance(
              context,
              androidConfig.clientId ?: defaultClientId(),
              androidConfig.deviceName ?: defaultDeviceName(),
              androidConfig.processName ?: defaultProcessName(context),
              androidConfig.packageName ?: context.packageName,
          )
        } else {
          AndroidFlipperClient.getInstance(context)
        }
      } else {
        NoOpDelegateFlipperClient()
      }

      return AndroidFlopperRuntime(delegate)
    }
  }

  fun addPlugin(plugin: FlopperPlugin) {
    val adapter = AndroidPluginAdapter(plugin)
    adaptersByPlugin[plugin] = adapter
    pluginsById[plugin.id] = plugin
    delegate.addPlugin(adapter)
  }

  fun getPlugin(id: String): FlopperPlugin? = pluginsById[id]

  fun removePlugin(plugin: FlopperPlugin) {
    adaptersByPlugin.remove(plugin)?.let(delegate::removePlugin)
    pluginsById.remove(plugin.id)
  }

  fun start() = delegate.start()

  fun stop() = delegate.stop()

  fun isConnected(): Boolean = delegate.isConnected

  fun getState(): String = delegate.state

  fun getStateSummary(): FlopperStateSummary {
    val summary = delegate.stateSummary
    val entries = summary?.mList?.map { FlopperStateSummary.Entry(it.name, it.state.name) }.orEmpty()
    return FlopperStateSummary(entries)
  }
}

private fun defaultClientId(): String = Build.SERIAL ?: "unknown-android-device"

private fun defaultDeviceName(): String = buildString {
  append(Build.MODEL ?: "Android")
  append(" - ")
  append(Build.VERSION.RELEASE ?: "unknown")
  append(" - API ")
  append(Build.VERSION.SDK_INT)
}

private fun defaultProcessName(context: Context): String =
    context.applicationInfo.loadLabel(context.packageManager).toString()

private class AndroidPluginAdapter(
    private val plugin: FlopperPlugin,
) : NativeFlipperPlugin {
  override fun getId(): String = plugin.id

  override fun onConnect(connection: NativeFlipperConnection) {
    plugin.onConnect(AndroidConnectionAdapter(connection))
  }

  override fun onDisconnect() {
    plugin.onDisconnect()
  }

  override fun runInBackground(): Boolean = plugin.runInBackground
}

private class AndroidConnectionAdapter(
    private val delegate: NativeFlipperConnection,
) : FlopperConnection {
  override fun send(method: String, payload: String?) {
    when {
      payload == null -> delegate.send(method, "")
      payload.trim().startsWith("{") -> delegate.send(method, FlipperObject(payload))
      payload.trim().startsWith("[") -> delegate.send(method, FlipperArray(payload))
      else -> delegate.send(method, payload)
    }
  }

  override fun receive(
      method: String,
      receiver: (payload: String?, responder: FlopperResponder) -> Unit,
  ) {
    delegate.receive(method, FlipperReceiver { params, responder ->
      receiver(params?.toJsonString(), AndroidResponderAdapter(responder))
    })
  }

  override fun reportError(reason: String, stackTrace: String?) {
    delegate.reportErrorWithMetadata(reason, stackTrace ?: "")
  }
}

private class AndroidResponderAdapter(
    private val delegate: NativeFlipperResponder,
) : FlopperResponder {
  override fun success(response: String?) {
    when {
      response == null -> delegate.success()
      response.trim().startsWith("{") -> delegate.success(FlipperObject(response))
      response.trim().startsWith("[") -> delegate.success(FlipperArray(response))
      else -> delegate.success(FlipperObject.Builder().put("message", response).build())
    }
  }

  override fun error(response: String?) {
    val body = if (response.isNullOrBlank()) {
      FlipperObject.Builder().put("message", "Unknown error").build()
    } else if (response.trim().startsWith("{")) {
      FlipperObject(response)
    } else {
      FlipperObject.Builder().put("message", response).build()
    }
    delegate.error(body)
  }
}

private class NoOpDelegateFlipperClient : NativeFlipperClient {
  override fun addPlugin(plugin: NativeFlipperPlugin) {}

  override fun <T : NativeFlipperPlugin?> getPlugin(id: String?): T? = null

  override fun <T : NativeFlipperPlugin?> getPluginByClass(cls: Class<T>?): T? = null

  override fun removePlugin(plugin: NativeFlipperPlugin) {}

  override fun start() {}

  override fun stop() {}

  override fun isConnected(): Boolean = false

  override fun subscribeForUpdates(stateListener: com.facebook.flipper.core.FlipperStateUpdateListener?) {}

  override fun unsubscribe() {}

  override fun getState(): String = "DISABLED"

  override fun getStateSummary(): StateSummary = StateSummary()
}
