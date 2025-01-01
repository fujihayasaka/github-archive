# typed: true
# frozen_string_literal: true

# ColorMode value object. Used with ColorModeType via the Rails Attributes API.
class ColorMode
  MODES = []
  DATABASE_DEFAULT_VALUE  = 0
  DATABASE_AUTO_VALUE     = 1
  DATABASE_LIGHT_VALUE    = 2
  DATABASE_DARK_VALUE     = 3

  attr_reader :db_value, :name, :hydro_mapping

  # * `db_value` - the TINYINT value stored in the DB.
  # * `name` - the internal identifier.
  # * `hydro_mapping` - the symbol to use for Hydro events involving this theme.
  # All should remain stable once introduced.
  def initialize(db_value, name, hydro_mapping)
    @db_value, @name, @hydro_mapping = db_value, name, hydro_mapping
  end

  def to_s
    name
  end

  def unset?
    db_value == DATABASE_DEFAULT_VALUE
  end

  def light?
    db_value == DATABASE_LIGHT_VALUE
  end

  def auto?
    db_value == DATABASE_AUTO_VALUE
  end

  def dark?
    db_value == DATABASE_DARK_VALUE
  end

  def self.default
    AUTO
  end

  # Register a color mode. Called at application initialization below.
  def self.register(db_value, label, hydro_mapping)
    mode = new(db_value, label, hydro_mapping)
    MODES << mode
    mode
  end

  # Given an integer, return the ColorMode with that database value
  def self.from_db_value(db_value)
    MODES.find { |mode| mode.db_value == db_value }
  end

  # Given the name of a ColorMode, return the ColorMode
  def self.from_name(name)
    MODES.find { |mode| mode.name == name }
  end

  UNSET = register(DATABASE_DEFAULT_VALUE,  "unset", :UNSET)
  AUTO  = register(DATABASE_AUTO_VALUE,     "auto",  :AUTO)
  LIGHT = register(DATABASE_LIGHT_VALUE,    "light", :LIGHT)
  DARK  = register(DATABASE_DARK_VALUE,     "dark",  :DARK)
end
