# typed: true
# frozen_string_literal: true

# Custom ActiveRecord Type for wrapping a theme TINYINT column.
# Ensures we're working with Theme value objects as much as possible.
class UserThemeType < ActiveRecord::Type::Integer
  def type
    :integer
  end

  # Converts a value from database input to the appropriate ruby type.
  # This method expects an integer from the database, which it will convert to
  # a Theme value object.
  def deserialize(db_value)
    UserTheme.from_db_value(db_value)
  end

  # Called by ActiveRecord when setting the attribute on the object.
  def cast(value)
    case value
    when Integer
      UserTheme.from_db_value(value)
    when String
      UserTheme.from_db_value(value.to_i)
    else
      value
    end
  end

  # Casts a value from the ruby type to a type that the database knows how to
  # understand. This method expects a UserTheme object which it will convert to an
  # integer for the database to store.
  def serialize(theme)
    if theme.present?
      theme.db_value
    else
      nil
    end
  end
end
