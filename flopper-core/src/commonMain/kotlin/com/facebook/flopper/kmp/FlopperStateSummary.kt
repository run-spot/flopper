package com.facebook.flopper.kmp

data class FlopperStateSummary(
    val entries: List<Entry> = emptyList(),
) {
  data class Entry(
      val name: String,
      val state: String,
  )
}
