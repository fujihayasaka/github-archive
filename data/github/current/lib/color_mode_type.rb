# typed: true
# frozen_string_literal: true

# Custom ActiveRecord Type for wrapping a color_mode TINYINT column.
# Ensures we're working with ColorMode value objects as much as possible.
class ColorModeType < ActiveRecord::Type::Integer
  def type
    :integer
  end

  # Converts a value from database input to the appropriate ruby type.
  # This method expects an integer from the database, which it will convert to
  # a ColorMode value object.
  def deserialize(db_value)
    ColorMode.from_db_value(db_value)
  end

  # Called by ActiveRecord when setting the attribute on the object.
  def cast(value)
    case value
    when Integer
      ColorMode.from_db_value(value)
    when String
      ColorMode.from_db_value(value.to_i)
    else
      value
    end
  end

  # Casts a value from the ruby type to a type that the database knows how to
  # understand.  This method expects a ColorMode object which it will convert to an
  # integer for the database to store.
  def serialize(color_mode)
    if color_mode.present?
      color_mode.db_value
    else
      ColorMode::UNSET.db_value
    end
  end
end
