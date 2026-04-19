package com.facebook.flopper.kmp

interface FlopperPlugin {
  val id: String

  fun onConnect(connection: FlopperConnection) {}

  fun onDisconnect() {}

  val runInBackground: Boolean
    get() = false
}
