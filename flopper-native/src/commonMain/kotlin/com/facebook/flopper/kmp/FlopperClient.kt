package com.facebook.flopper.kmp

expect class FlopperClient {
  companion object {
    fun create(config: FlopperConfig): FlopperClient
  }

  fun addPlugin(plugin: FlopperPlugin)

  fun getPlugin(id: String): FlopperPlugin?

  fun removePlugin(plugin: FlopperPlugin)

  fun start()

  fun stop()

  fun isConnected(): Boolean

  fun getState(): String

  fun getStateSummary(): FlopperStateSummary
}
