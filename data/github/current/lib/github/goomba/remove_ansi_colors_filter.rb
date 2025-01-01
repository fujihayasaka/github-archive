# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class RemoveANSIColorsFilter < InputFilter
    PATTERN = /\e\[(\d+)(;\d+)*m/

    def call(text)
      text.gsub(PATTERN, "")
    end
  end
end
