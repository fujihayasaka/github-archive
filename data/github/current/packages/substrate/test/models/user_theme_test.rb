# typed: true
# frozen_string_literal: true

require "test_helper"

class UserThemeTest < GitHub::TestCase
  def test_to_s
    assert_equal UserTheme::DEFAULT_LIGHT.to_s, UserTheme::DEFAULT_LIGHT.name
  end

  def test_to_sym
    assert_equal UserTheme::DEFAULT_DARK.to_sym, :dark
  end

  def test_from_db_value
    assert_equal UserTheme.from_db_value(UserTheme::DEFAULT_LIGHT.db_value), UserTheme::DEFAULT_LIGHT
    assert_equal UserTheme.from_db_value(UserTheme::DEFAULT_DARK.db_value), UserTheme::DEFAULT_DARK
  end

  def test_from_name
    assert_equal UserTheme.from_name(UserTheme::DEFAULT_LIGHT.name), UserTheme::DEFAULT_LIGHT
    assert_equal UserTheme.from_name(UserTheme::DEFAULT_DARK.name), UserTheme::DEFAULT_DARK
  end

  def test_equality
    assert_equal UserTheme::DEFAULT_DARK, UserTheme::DEFAULT_DARK
    refute_equal UserTheme::DEFAULT_LIGHT, UserTheme::DEFAULT_DARK
  end

  def test_labels
    assert_equal UserTheme::DEFAULT_DARK.label, "Dark default"
    assert_equal UserTheme::DEFAULT_LIGHT.label, "Light default"
  end

  def test_theme_mode
    assert_equal UserTheme::DEFAULT_DARK.color_mode, ColorMode::DARK
    assert_equal UserTheme::DEFAULT_LIGHT.color_mode, ColorMode::LIGHT
  end

  def test_light_themes
    light_themes = UserTheme::light_themes.map(&:name).join(", ")
    assert_includes light_themes, "light"
    refute_includes light_themes, "dark"
  end

  def test_dark_themes
    dark_themes = UserTheme::dark_themes.map(&:name).join(", ")
    assert_includes dark_themes, "dark"
    refute_includes dark_themes, "light"
  end
end
