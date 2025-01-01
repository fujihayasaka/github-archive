# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # HTML filter that replaces :emoji: with images and wraps native emoji
  # characters in <g-emoji> elements. This allows JavaScript to use an
  # image-based polyfill on browsers that don't support native emoji.
  #
  # Context options:
  #   :asset_root (required) - base url to link to emoji sprite
  class EmojiFilter < ::HTML::Pipeline::EmojiFilter
    extend T::Sig
    Context = T.type_alias { T::Hash[Symbol, T.untyped] }

    VARIATION_SELECTOR_15 = "\u{fe0e}"
    ZERO_WIDTH_JOINER = "\u{200d}"
    SKIN_TONE_MODIFIERS = "\u{1F3FB}".."\u{1F3FF}"
    HAIR_STYLE_MODIFIERS = "\u{1F9B0}".."\u{1F9B2}"

    # Index of characters that, when appended after an emoji, trigger a
    # condition when we will avoid wrapping the emoji in `<g-emoji>`.
    modifier_chars = [VARIATION_SELECTOR_15, ZERO_WIDTH_JOINER].concat(SKIN_TONE_MODIFIERS.to_a).concat(HAIR_STYLE_MODIFIERS.to_a)
    MODIFIER_CHAR_MAP = modifier_chars.each_with_object({}) { |char, map| map[char] = true }

    MAX_FILE_SIZE = 16 * 1024 # 16kb
    IGNORE_PARENTS = %w(pre code tt)

    sig { params(context: Context).returns(T::Boolean) }
    def self.enabled?(context)
      !context[:blob] || context[:blob].size <= MAX_FILE_SIZE
    end

    sig { params(context: Context).returns(String) }
    def self.cache_key(context)
      HTML::Pipeline::EmojiFilter.cache_key(context)
    end

    # Public: This method is intended to run any validations to ensure the
    # correct context is set for the filter to properly run. Since the parent
    # class has a validation on the presence of context[:asset_root] we need to
    # redefine the method as we have a dynamicly set asset_root.
    #
    # Returns nothing.
    sig { void }
    def validate
      # Define any validations other than asset_root here.
    end

    # Public: The base url to link emoji sprites.
    #
    # Returns String.
    sig { returns(String) }
    def asset_root
      "#{GitHub.asset_host_url}/images/icons"
    end

    sig { returns(::Nokogiri::HTML4::DocumentFragment) }
    def call
      return doc unless self.class.enabled?(context)

      # Let our super class handle :emoji:.
      super
      doc
    end

    sig { params(text: String).returns(String) }
    def emoji_image_filter(text)
      text.gsub(emoji_pattern) do |_match|
        emoji = Emoji.find_by_alias($1)
        if emoji.raw
          emoji.raw
        else
          emoji_image_tag(emoji.name)
        end
      end
    end

    sig { returns(T::Array[String]) }
    def self.emoji_unicodes
      Emoji.all.flat_map(&:unicode_aliases)
    end

    # Build a regexp that matches all native emoji characters.
    # Some emoji code point sequences are prefixes of other emoji code point
    # sequences, e.g.:
    # U+2728 SPARKLES
    # vs.
    # U+2728 SPARKLES U+FE0F VARIATION SELECTOR-16
    # We sort the code point sequences longest-first so that the regex will
    # match the longest possible sequence.
    sig { returns(Regexp) }
    def self.unicodes_pattern
      @unicodes_pattern ||= Regexp.new(emoji_unicodes.sort_by(&:length).reverse.map { |u| Regexp.escape(u) }.join("|"))
    end

    EMOJI_FILTER_PATTERN_RE = %r{
      (?<!#{Regexp.quote(GitHub::HTML::EmojiFilter::ZERO_WIDTH_JOINER)})
      #{GitHub::HTML::EmojiFilter.unicodes_pattern}
      (?!#{Regexp.union(GitHub::HTML::EmojiFilter::MODIFIER_CHAR_MAP.keys.map { |k| Regexp.quote k })})
    }x
    EMOJI_FILTER_PATTERN = Regexp.new(EMOJI_FILTER_PATTERN_RE, timeout: 5)

    # Wrap native emoji for polyfilling.
    #
    # text - String text to replace emoji in.
    #
    # Modifies text in-place and returns text with native emoji wrapped in
    # <g-emoji> elements. Returns nil if no modifications were performed.
    sig { params(text: String).returns(T.nilable(String)) }
    def unicode_emoji_filter!(text)
      return if text.ascii_only?
      text.gsub!(EMOJI_FILTER_PATTERN) do |unicode|
        emoji = Emoji.find_by_unicode(unicode)
        "<g-emoji class='g-emoji' alias='#{emoji.name}' fallback-src='#{emoji_url(emoji.name)}'>#{unicode}</g-emoji>"
      end
    end
  end
end
