# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Goomba text filter that wraps native emoji characters in <g-emoji>
  # elements.
  # Originally this allowed JavaScript to use an image-based polyfill on browsers
  # that don't support native emoji.
  # Now, it's used to wrap the handful of native emoji that have older, non-color
  # variants that don't render in color by default in Chromium-based browsers.
  #
  # Context options:
  #   :asset_root (required) - base url to link to emoji sprite
  class UnicodeEmojiFilter < TextFilter
    IGNORE_PARENTS = GitHub::HTML::EmojiFilter::IGNORE_PARENTS.map { |tag| "#{tag} :text" }.join(", ")
    SELECTOR = Goomba::Selector.new(match: ":text", reject: IGNORE_PARENTS)
    LEGACY_EMOJI = %w(
      relaxed
      warning
      frowning_face
      airplane
      spades
      hearts
      diamonds
      clubs
      arrow_upper_right
      arrow_lower_right
      arrow_lower_left
      arrow_upper_left
      arrow_up_down
      left_right_arrow
      arrow_heading_up
      arrow_heading_down
      arrow_forward
      arrow_backward
      eject_button
      bangbang
      interrobang
      a
      b
      m
      o2
      parking
    ).map { Emoji.find_by_alias(_1).raw }
    LEGACY_EMOJI_PATTERN = Regexp.new(LEGACY_EMOJI.join("|") + "\u{fe0f}?")

    def self.cache_key(context)
      GitHub::HTML::EmojiFilter.cache_key(context)
    end

    def initialize(*args)
      super
      @filter = GitHub::HTML::EmojiFilter.new("", context, result)
    end

    def selector
      SELECTOR
    end

    def call(text)
      return if text.html.ascii_only?
      text.html.gsub!(LEGACY_EMOJI_PATTERN) do |unicode|
        emoji = Emoji.find_by_unicode(unicode)
        "<g-emoji class='g-emoji' alias='#{emoji.name}'>#{unicode}</g-emoji>"
      end
    end
  end
end
