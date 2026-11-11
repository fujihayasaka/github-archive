# typed: true
# frozen_string_literal: true

module CacheKeyLoggingDenylist
  BLOB_MARKUP_PREFIX = "blob_markup"
  API_REPOS_PREFIX = "api-user-repos"
  TREE_HELPER_PREFIX = "format_commit_message_short"
  TREE_ENTRY_PREFIX = "colorized_lines"
  SYNTAX_HIGHLIGHTED_DIFF_PREFIX = "SyntaxHighlightedDiff"
  NETWORK_GRAPH_PREFIX = "ng:v7"

  DENIED_CACHE_KEY_PREFIXES = [
    BLOB_MARKUP_PREFIX,
    API_REPOS_PREFIX,
    TREE_HELPER_PREFIX,
    TREE_ENTRY_PREFIX,
    SYNTAX_HIGHLIGHTED_DIFF_PREFIX,
    NETWORK_GRAPH_PREFIX,
  ]

  REDACTED = "REDACTED"

  def self.scrub(cache_key)
    DENIED_CACHE_KEY_PREFIXES.each do |prefix|
      return "#{prefix}:#{REDACTED}" if cache_key.start_with? prefix
    end
    cache_key
  end

  def self.scrub_multi(cache_keys)
    cache_keys.map { |key| scrub(key) }
  end
end
