package com.facebook.flopper.kmp

interface FlopperConnection {
  fun send(method: String, payload: String? = null)

  fun receive(method: String, receiver: (payload: String?, responder: FlopperResponder) -> Unit)

  fun reportError(reason: String, stackTrace: String? = null)
}
