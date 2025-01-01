# typed: true
# frozen_string_literal: true

# Theme value object. Used with UserThemeType via the Rails Attributes API.
class UserTheme
  THEMES = []
  LIGHT_THEME_DATABASE_DEFAULT = 1
  DARK_THEME_DATABASE_DEFAULT = 2

  # * `db_value` - the TINYINT value stored in the DB.
  #    This must remain stable after introduction.
  # * `name` - the internal identifier.
  #    This should remain stable after introduction.
  # * `sort` - the order in which the theme should be displayed.
  # * `label` - This label will be user facing to describe the theme.
  # * `color_mode` - The ColorMode this theme has as a fallback.
  # * `feature_flag` - The feature flag this theme is enabled for (nil if generally available).
  attr_reader :db_value, :sort, :name, :label, :color_mode, :feature_flag

  def initialize(db_value:, sort:, name:, label:, color_mode:, feature_flag: nil)
    @db_value, @sort, @name, @label, @color_mode, @feature_flag = db_value, sort, name, label, color_mode, feature_flag
  end

  def to_s
    name
  end

  def to_sym
    name.to_sym
  end

  # Registers a new theme.
  #
  # Returns the theme object
  def self.register(**kwargs)
    theme = new(**T.unsafe(kwargs))
    THEMES << theme
    theme
  end

  # Given the db_value of a UserTheme, return the UserTheme
  def self.from_db_value(db_value)
    THEMES.find { |theme| theme.db_value == db_value }
  end

  # Given the name of a UserTheme, return the UserTheme
  def self.from_name(name)
    THEMES.find { |theme| theme.name == name }
  end

  def self.light_themes
    THEMES.select { |theme| theme.color_mode.light? }
  end

  def self.dark_themes
    THEMES.select { |theme| theme.color_mode.dark? }
  end

  DEFAULT_LIGHT = register(db_value: LIGHT_THEME_DATABASE_DEFAULT, sort: 1, name: "light", label: "Light default", color_mode: ColorMode::LIGHT)
  DEFAULT_DARK  = register(db_value: DARK_THEME_DATABASE_DEFAULT,  sort: 5, name: "dark",  label: "Dark default", color_mode: ColorMode::DARK)
  register(db_value: 3,  sort: 9, name: "dark_dimmed",  label: "Dark dimmed", color_mode: ColorMode::DARK)
  register(db_value: 4,  sort: 6, name: "dark_high_contrast",  label: "Dark high contrast", color_mode: ColorMode::DARK)
  register(db_value: 5,  sort: 7, name: "dark_colorblind",  label: "Dark colorblind", color_mode: ColorMode::DARK, feature_flag: :color_modes_color_blind_themes)
  register(db_value: 6,  sort: 3, name: "light_colorblind",  label: "Light colorblind", color_mode: ColorMode::LIGHT, feature_flag: :color_modes_color_blind_themes)
  register(db_value: 7,  sort: 2, name: "light_high_contrast",  label: "Light high contrast", color_mode: ColorMode::LIGHT)
  register(db_value: 8,  sort: 4, name: "light_tritanopia",  label: "Light Tritanopia", color_mode: ColorMode::LIGHT, feature_flag: :color_modes_color_blind_themes_2)
  register(db_value: 9,  sort: 8, name: "dark_tritanopia",  label: "Dark Tritanopia", color_mode: ColorMode::DARK, feature_flag: :color_modes_color_blind_themes_2)
end
