# frozen_string_literal: true

# Adjusts string encoding to UTF-8 from varbinary columns
# Copied from https://github.com/github/github/blob/82c1af65ea86297150262cb5e0ed33900f32c04c/packages/substrate/app/models/string_from_binary.rb
class StringFromBinary < ActiveRecord::Type::Binary
  def deserialize(value)
    value = super(value)

    if value && value.encoding != Encoding::UTF_8
      value = value.dup
      value.force_encoding("UTF-8")
    end

    value
  end
end
