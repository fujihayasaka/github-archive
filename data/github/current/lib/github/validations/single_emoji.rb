# typed: true
# frozen_string_literal: true

module GitHub
  module Validations
    # Public: Rails validation that ensures that a field, if non-nil, contains
    # exactly one recognized emoji. Native or colon-style (`:smile:`) emoji are
    # accepted.
    #
    # Uses `GitHub::Goomba::SimpleDescriptionPipeline` internally to normalize
    # emoji representations. If you wish to use a different Goomba pipeline,
    # define a method named `#{attribute}_html` to invoke it.
    class SingleEmojiValidator < ActiveModel::EachValidator

      # 36 characters is the longest of any colon-style emoji or native Unicode
      # emoji. Add two more characters for the colon on either end of a colon-style
      # emoji, and you have 38.
      EMOJI_MAX_LENGTH = 38

      def validate_each(record, attribute, value)
        return unless value
        return if too_long?(record, attribute, value)

        html_method = :"#{attribute}_html"
        html = record.respond_to?(html_method) ? record.send(html_method) : to_html(value)

        single_emoji?(record, attribute, html) && !contains_extra_text?(record, attribute, html)
      end

      private

      def to_html(value)
        GitHub::Goomba::SimpleDescriptionPipeline.to_html(value, { base_url: GitHub.url }, nil)
      end

      def too_long?(record, attribute, value)
        if value.length > EMOJI_MAX_LENGTH
          record.errors.add attribute, "is too long (maximum is #{EMOJI_MAX_LENGTH} characters)"
          true
        else
          false
        end
      end

      def single_emoji?(record, attribute, html)
        emoji_count = html.scan(GitHub::HTML::EmojiFilter::EMOJI_FILTER_PATTERN).size + html.scan(/<img/).size

        if emoji_count > 1
          record.errors.add attribute, "can only be one emoji"
          false
        elsif emoji_count < 1
          record.errors.add attribute, "does not contain a recognized emoji"
          false
        else
          true
        end
      end

      def contains_extra_text?(record, attribute, html)
        contains_only_wrapped_emoji = html =~ /<\/g-emoji><\/div>/ && html =~ /<div><g-emoji/
        contains_only_native_emoji = html =~ /#{GitHub::HTML::EmojiFilter::EMOJI_FILTER_PATTERN}<\/div>/ && html =~ /<div>#{GitHub::HTML::EmojiFilter::EMOJI_FILTER_PATTERN}/
        contains_only_custom_emoji = html =~ /><\/div>/ && html =~ /<div><img/

        if !contains_only_wrapped_emoji && !contains_only_native_emoji && !contains_only_custom_emoji
          record.errors.add attribute, "can only contain one supported emoji"
          true
        else
          false
        end
      end
    end
  end
end
