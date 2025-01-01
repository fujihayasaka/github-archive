# typed: true
# frozen_string_literal: true

class StringFromBinary < ActiveRecord::Type::Binary
  def cast(value)
    value = super

    if value && value.is_a?(String) && value.encoding != Encoding::UTF_8
      value = value.dup
      value.force_encoding("UTF-8")
    end

    value
  end
end
