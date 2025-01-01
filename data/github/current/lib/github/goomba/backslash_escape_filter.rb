# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # The BackslashEscapeFilter replaces any backslashes with html entities
  # so they will not be altered by markdown
  # see: https://github.github.com/gfm/#backslash-escapes
  class BackslashEscapeFilter < InputFilter
    def call(input)
      input.gsub("\\", "&#92;")
    end
  end
end
