package com.facebook.flopper.kmp

sealed interface FlopperConfig {
  val enabled: Boolean

  data class Android(
      val contextHandle: Any,
      val clientId: String? = null,
      val deviceName: String? = null,
      val processName: String? = null,
      val packageName: String? = null,
      override val enabled: Boolean = true,
  ) : FlopperConfig

  data class Ios(
      val appName: String? = null,
      val deviceModel: String? = null,
      val osVersion: String? = null,
      override val enabled: Boolean = true,
  ) : FlopperConfig
}
