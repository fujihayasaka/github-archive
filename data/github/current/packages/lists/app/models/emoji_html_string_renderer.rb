# typed: true
# frozen_string_literal: true

class EmojiHtmlStringRenderer
  # Regexp for strings which don't need modification: anything matching this
  # MUST be guaranteed HTML_safe and to contain no emoji.
  SAFE_STRING_REGEXP = /\A[a-z0-9. _-]+\z/i
  DEFAULT_CACHE_KEY_PREFIX = "emoji_str"

  # Public: Returns the String cache key that would be used for caching the HTMLified result of the emoji string.
  #
  # emoji_str - a String that might contain raw emoji characters, colon-style emoji markup like `:smile:`, or neither;
  #             can be nil
  # cache_key_prefix - a String used to prefix the cache key for this emoji string; only used if skip_cache=false
  #
  # Returns a String.
  def self.cache_key_for(emoji_str, cache_key_prefix:)
    emoji_str_hash = Digest::SHA256.hexdigest(emoji_str)
    "#{cache_key_prefix}:#{emoji_str_hash}"
  end

  # emoji_str - a String that might contain raw emoji characters, colon-style emoji markup like `:smile:`, or neither;
  #             can be nil
  # cache_key_prefix - a String used to prefix the cache key for this emoji string; only used if skip_cache=false
  # skip_cache - a Boolean indicating whether we should avoid caching the HTML taggified result for the given
  #              emoji string; defaults to using cache
  def initialize(emoji_str, cache_key_prefix: nil, skip_cache: false)
    @emoji_str = emoji_str
    @cache_key_prefix = cache_key_prefix.presence || DEFAULT_CACHE_KEY_PREFIX
    @skip_cache = skip_cache
  end

  # Public: Returns a Promise that resolves to an HTML string for displaying the string that may contain emoji.
  # The resulting string may include g-emoji HTML tags.
  def async_to_html
    return Promise.resolve(nil) unless @emoji_str # avoid errors when passing nil to #escape_html
    return Promise.resolve(ERB::Util.force_escape(@emoji_str)) if SAFE_STRING_REGEXP.match?(@emoji_str)
    return Promise.resolve(g_emoji_taggify_string) if @skip_cache

    Platform::Loaders::Cache.fetch(cache_key) { g_emoji_taggify_string }
  end

  # Public: Returns an HTML string for displaying the string that may contain emoji. May include g-emoji HTML
  # tags.
  def to_html
    async_to_html.sync
  end

  private

  def cache_key
    self.class.cache_key_for(@emoji_str, cache_key_prefix: @cache_key_prefix)
  end

  def g_emoji_taggify_string
    clean_input = ERB::Util.force_escape(@emoji_str) # escape HTML tags
    html = GitHub::HTML::EmojiFilter.to_html(clean_input) # produce g-emoji tags
    html.html_safe # rubocop:disable Rails/OutputSafety
  end
end
