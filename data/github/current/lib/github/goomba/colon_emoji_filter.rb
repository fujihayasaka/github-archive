# typed: true
# frozen_string_literal: true

require_relative "colon_emojiable"

module GitHub::Goomba
  # Goomba text filter that replaces :emoji: with images.
  #
  # Context options:
  #   :asset_root (required) - base url to link to emoji sprite
  class ColonEmojiFilter < TextFilter
    include ColonEmojiable

    IGNORE_PARENTS = GitHub::HTML::EmojiFilter::IGNORE_PARENTS.map { |tag| "#{tag} :text" }.join(", ")
    SELECTOR = Goomba::Selector.new(match: ":text", reject: IGNORE_PARENTS)

    def self.cache_key(context)
      GitHub::HTML::EmojiFilter.cache_key(context)
    end

    def initialize(*args)
      super
      @filter = GitHub::HTML::EmojiFilter.new("", context, result)
    end

    sig { returns(Goomba::Selector) }
    def selector
      SELECTOR
    end

    sig { params(text: Goomba::TextNode).returns(T.nilable(String)) }
    def call(text)
      return if probably_not_a_colon_emoji?(text.html)

      result = @filter.emoji_image_filter(text.html)
      if result == text.html
        # There were no modifications, so just return nil to keep the text node as-is.
        # FIXME: We should use gsub! instead of gsub to implement this behavior
        # more efficiently.
        nil
      else
        result
      end
    end
  end
end
