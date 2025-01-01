# typed: true
# frozen_string_literal: true
class UnconvertedStringFromBinary < ActiveRecord::Type::Binary
  def cast(value)
    if value.is_a?(Data)
      value.to_s
    else
      value
    end
  end
end
