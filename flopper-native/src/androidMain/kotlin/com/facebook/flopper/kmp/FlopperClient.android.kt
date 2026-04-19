package com.facebook.flopper.kmp

import com.facebook.flopper.kmp.android.AndroidFlopperRuntime

actual class FlopperClient private constructor(
    private val runtime: AndroidFlopperRuntime,
) {
  actual companion object {
    actual fun create(config: FlopperConfig): FlopperClient = FlopperClient(
        AndroidFlopperRuntime.create(config),
    )
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
