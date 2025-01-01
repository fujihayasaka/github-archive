# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Transcode all incoming content to UTF-8. Goomba requires all input be
  # UTF-8.
  class UTF8Filter < InputFilter
    def call(text)
      GitHub::HTML::UTF8Filter.new(text, context, result).call
    end
  end
end
