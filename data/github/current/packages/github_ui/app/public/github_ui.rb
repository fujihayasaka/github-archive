# typed: strict
# frozen_string_literal: true

module GitHubUI
  TARGETS = T.let({
    preview: "preview",
    full: "full",
    canary_0: "canary-0",
    canary_1: "canary-1",
    canary_2: "canary-2",
    warmup: "warmup",
  }.freeze, T::Hash[Symbol, String])

  # Shared types
  ManifestData = T.type_alias { T::Hash[String, T.untyped] }
  SHA = T.type_alias { String }
  Target = T.type_alias { String }
  SHAFallbackEntry = T.type_alias { { sha: SHA, expires_at: Time } }

  # Shared constants
  PREVIEW_TTL = T.let(60 * 60 * 24, Integer) # 1 day in seconds
end
