package com.facebook.flopper.kmp

interface FlopperResponder {
  fun success(response: String? = null)

  fun error(response: String? = null)
}
