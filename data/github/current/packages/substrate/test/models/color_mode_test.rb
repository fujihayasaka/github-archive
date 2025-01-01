# typed: true
# frozen_string_literal: true

require "test_helper"

class ColorModeTest < GitHub::TestCase
  def test_to_s
    assert_equal ColorMode::LIGHT.to_s, ColorMode::LIGHT.name
  end

  def test_default
    assert_equal ColorMode.default, ColorMode::AUTO
  end

  def test_from_db_value
    assert_equal ColorMode.from_db_value(ColorMode::LIGHT.db_value), ColorMode::LIGHT
    assert_equal ColorMode.from_db_value(ColorMode::AUTO.db_value), ColorMode::AUTO
    assert_equal ColorMode.from_db_value(ColorMode::DARK.db_value), ColorMode::DARK
    assert_equal ColorMode.from_db_value(ColorMode::UNSET.db_value), ColorMode::UNSET
  end

  def test_from_name
    assert_equal ColorMode.from_name(ColorMode::LIGHT.name), ColorMode::LIGHT
    assert_equal ColorMode.from_name(ColorMode::AUTO.name), ColorMode::AUTO
    assert_equal ColorMode.from_name(ColorMode::DARK.name), ColorMode::DARK
    assert_equal ColorMode.from_name(ColorMode::UNSET.name), ColorMode::UNSET
  end

  def test_equality
    assert_equal ColorMode::UNSET, ColorMode::UNSET
    assert_equal ColorMode::DARK, ColorMode::DARK
    refute_equal ColorMode::UNSET, ColorMode::AUTO
  end

  def test_unset
    assert ColorMode::UNSET.unset?
    refute ColorMode::AUTO.unset?
    refute ColorMode::DARK.unset?
    refute ColorMode::LIGHT.unset?
  end

  def test_auto
    assert ColorMode::AUTO.auto?
    refute ColorMode::UNSET.auto?
    refute ColorMode::DARK.auto?
    refute ColorMode::LIGHT.auto?
  end

  def test_light
    assert ColorMode::LIGHT.light?
    refute ColorMode::AUTO.light?
    refute ColorMode::DARK.light?
  end

  def test_dark
    assert ColorMode::DARK.dark?
    refute ColorMode::LIGHT.dark?
    refute ColorMode::AUTO.dark?
  end
end
