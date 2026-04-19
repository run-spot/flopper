package com.facebook.flopper.kmp

import platform.Foundation.NSData
import platform.Foundation.NSError
import platform.Foundation.NSHTTPURLResponse
import platform.Foundation.NSLog
import platform.Foundation.NSMutableURLRequest
import platform.Foundation.NSURL
import platform.Foundation.NSURLSession
import platform.Foundation.dataTaskWithRequest
import platform.Foundation.setValue
import platform.Foundation.timeIntervalSince1970
import kotlin.random.Random

class IosNetworkProbePlugin(
    private val urlString: String = "https://jsonplaceholder.typicode.com/todos/1",
    private val requestHeaderName: String = "Accept",
    private val requestHeaderValue: String = "application/json",
) : FlopperPlugin {
  override val id: String = "Network"

  private var connection: FlopperConnection? = null

  override fun onConnect(connection: FlopperConnection) {
    this.connection = connection
  }

  override fun onDisconnect() {
    connection = null
  }

  fun triggerRequest() {
    val connection = connection ?: return
    val url = NSURL.URLWithString(urlString) ?: return
    val request = NSMutableURLRequest.requestWithURL(url)
    request.setValue(requestHeaderValue, forHTTPHeaderField = requestHeaderName)
    val requestHeaders = listOf(
        mapOf(
            "key" to requestHeaderName,
            "value" to requestHeaderValue,
        ),
    )

    val requestId = "${platform.Foundation.NSDate().timeIntervalSince1970}-${Random.nextInt(1000, 9999)}"
    NSLog("FLOPPER-NETWORK request started id=$requestId url=$urlString")
    connection.send(
        method = "newRequest",
        payload = jsonObject(
            "id" to requestId,
            "timestamp" to nowMillis(),
            "method" to "GET",
            "url" to urlString,
            "headers" to requestHeaders,
            "data" to null,
        ),
    )

    NSURLSession.sharedSession.dataTaskWithRequest(request) { data: NSData?, response: platform.Foundation.NSURLResponse?, error: NSError? ->
      val activeConnection = this.connection ?: return@dataTaskWithRequest
      val httpResponse = response as? NSHTTPURLResponse
      val bodyText = when {
        data != null -> "binary-response"
        error != null -> error.localizedDescription
        else -> null
      }
      val statusCode = httpResponse?.statusCode?.toInt() ?: 0
      if (error != null) {
        NSLog("FLOPPER-NETWORK request failed id=$requestId error=${error.localizedDescription}")
      } else {
        NSLog("FLOPPER-NETWORK response received id=$requestId status=$statusCode")
      }

      activeConnection.send(
          method = "newResponse",
          payload = jsonObject(
              "id" to requestId,
              "timestamp" to nowMillis(),
              "status" to statusCode,
              "reason" to if (statusCode > 0) "HTTP $statusCode" else (error?.localizedDescription ?: "Unknown"),
              "headers" to headerArray(httpResponse?.allHeaderFields),
              "data" to bodyText,
              "isMock" to false,
          ),
      )
    }.resume()
  }
}

private fun nowMillis(): Double = platform.Foundation.NSDate().timeIntervalSince1970 * 1000.0

private fun headerArray(headers: Map<Any?, *>?): List<Map<String, String>> {
  if (headers == null) {
    return emptyList()
  }
  return headers.entries.mapNotNull { (key, value) ->
    val keyText = key?.toString() ?: return@mapNotNull null
    val valueText = value?.toString() ?: return@mapNotNull null
    mapOf(
        "key" to keyText,
        "value" to valueText,
    )
  }
}

private fun jsonObject(vararg entries: Pair<String, Any?>): String? {
  return entries.joinToString(
      prefix = "{",
      postfix = "}",
      separator = ",",
  ) { (key, value) ->
    "\"${escapeJson(key)}\":${jsonValue(value)}"
  }
}

private fun jsonValue(value: Any?): String = when (value) {
  null -> "null"
  is String -> "\"${escapeJson(value)}\""
  is Number, is Boolean -> value.toString()
  is Map<*, *> -> value.entries.joinToString(prefix = "{", postfix = "}", separator = ",") { (key, nested) ->
    "\"${escapeJson(key.toString())}\":${jsonValue(nested)}"
  }
  is List<*> -> value.joinToString(prefix = "[", postfix = "]", separator = ",") { nested ->
    jsonValue(nested)
  }
  else -> "\"${escapeJson(value.toString())}\""
}

private fun escapeJson(value: String): String = buildString {
  value.forEach { character ->
    when (character) {
      '\\' -> append("\\\\")
      '"' -> append("\\\"")
      '\b' -> append("\\b")
      '\n' -> append("\\n")
      '\r' -> append("\\r")
      '\t' -> append("\\t")
      else -> append(character)
    }
  }
}
