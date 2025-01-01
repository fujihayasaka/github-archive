# typed: true
# frozen_string_literal: true

require "test_helper"

class SettingsAppearancePreferencesColorModesUpdaterTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
  end

  context "#update" do
    test "sets the color mode when only user_theme is passed in" do
      refute_equal ColorMode::DARK, @user.color_mode
      updater = create(:color_modes_updater, user: @user)

      updater.update(user_theme_name: UserTheme::DEFAULT_DARK.name)

      assert_equal ColorMode::DARK, @user.reload.color_mode
      assert_hydro_published({
        user_id: @user.id,
        color_mode: :DARK,
        color_mode_previous: :UNSET,
        source: :SETTINGS,
      }, schema: "github.v1.ChangeColorMode")
      refute_hydro_messages schema: "github.v1.ChangeUserTheme"
    end

    test "sets the color_mode light_theme dark_theme" do
      assert_equal ColorMode::UNSET, @user.color_mode
      assert_equal UserTheme::DEFAULT_DARK, @user.dark_theme
      assert_equal UserTheme::DEFAULT_LIGHT, @user.light_theme
      updater = create(:color_modes_updater, user: @user)

      updater.update(
        color_mode_name: ColorMode::AUTO.name,
        light_theme_name: UserTheme::DEFAULT_DARK.name,
        dark_theme_name: UserTheme::DEFAULT_LIGHT.name,
      )

      assert_equal ColorMode::AUTO, @user.reload.color_mode
      assert_equal UserTheme::DEFAULT_DARK, @user.reload.light_theme
      assert_equal UserTheme::DEFAULT_LIGHT, @user.reload.dark_theme
      assert_hydro_published({
        user_id: @user.id,
        color_mode: :AUTO,
        color_mode_previous: :UNSET,
        source: :SETTINGS,
      }, schema: "github.v1.ChangeColorMode")
      assert_hydro_published({
        user_id: @user.id,
        theme_type: ColorMode::LIGHT.hydro_mapping,
        user_theme: UserTheme::DEFAULT_DARK.db_value,
        user_theme_previous: UserTheme::DEFAULT_LIGHT.db_value,
        source: :SETTINGS,
      }, schema: "github.v1.ChangeUserTheme")
      assert_hydro_published({
        user_id: @user.id,
        theme_type: ColorMode::DARK.hydro_mapping,
        user_theme: UserTheme::DEFAULT_LIGHT.db_value,
        user_theme_previous: UserTheme::DEFAULT_DARK.db_value,
        source: :SETTINGS,
      }, schema: "github.v1.ChangeUserTheme")
    end

    test "doesn't publish hydro message when color mode doesn't change" do
      user = create(:user, :verified, color_mode: ColorMode::AUTO)
      updater = create(:color_modes_updater, user: user, current_color_mode: user.color_mode)

      updater.update(
        color_mode_name: ColorMode::AUTO.name,
        light_theme_name: UserTheme::DEFAULT_DARK.name,
        dark_theme_name: UserTheme::DEFAULT_LIGHT.name,
      )

      assert_equal ColorMode::AUTO, user.reload.color_mode
      assert_equal UserTheme::DEFAULT_DARK, user.reload.light_theme
      assert_equal UserTheme::DEFAULT_LIGHT, user.reload.dark_theme
      refute_hydro_messages schema: "github.v1.ChangeColorMode"
    end

    test "returns false when color mode wasn't found" do
      assert_equal ColorMode::UNSET, @user.color_mode
      updater = create(:color_modes_updater, user: @user, current_color_mode: @user.color_mode)

      result = updater.update(user_theme_name: "foo")

      assert_equal ColorMode::UNSET, @user.color_mode
      refute result
    end

    test "publishes correct hydro event for keyboard shortcut" do
      refute_equal ColorMode::DARK, @user.color_mode
      updater = create(
        :color_modes_updater,
        user: @user,
        current_color_mode: @user.color_mode,
        source: "keyboard_shortcut",
      )

      updater.update(user_theme_name: UserTheme::DEFAULT_DARK.name)

      assert_hydro_published({
        user_id: @user.id,
        color_mode: :DARK,
        color_mode_previous: :UNSET,
        source: :KEYBOARD_SHORTCUT,
      }, schema: "github.v1.ChangeColorMode")
    end

    test "allows user to only change mode" do
      user = create(
        :user,
        :verified,
        color_mode: ColorMode::AUTO,
        light_theme: UserTheme::DEFAULT_DARK,
        dark_theme: UserTheme::DEFAULT_LIGHT,
      )
      assert_equal ColorMode::AUTO, user.color_mode
      assert_equal UserTheme::DEFAULT_LIGHT, user.dark_theme
      assert_equal UserTheme::DEFAULT_DARK, user.light_theme
      updater = create(
        :color_modes_updater,
        user: user,
        current_color_mode: user.color_mode,
        current_light_theme: user.light_theme,
        current_dark_theme: user.dark_theme,
      )

      updater.update(color_mode_name: ColorMode::LIGHT.name)

      assert_equal ColorMode::LIGHT, user.reload.color_mode
      assert_equal UserTheme::DEFAULT_LIGHT, user.dark_theme
      assert_equal UserTheme::DEFAULT_DARK, user.light_theme
    end
  end
end
