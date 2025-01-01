# typed: true
# frozen_string_literal: true

class Settings::AppearancePreferences::ColorModesUpdater
  DEFAULT_SOURCE = :SETTINGS
  SOURCE_MAPPING = {
    "keyboard_shortcut" => :KEYBOARD_SHORTCUT,
    "profile" => :PROFILE,
    "settings_viewed" => :SETTINGS_VIEWED,
  }.freeze

  def initialize(user:, current_light_theme:, current_dark_theme:, current_color_mode:, source:)
    @user = user
    @current_light_theme = current_light_theme
    @current_dark_theme = current_dark_theme
    @current_color_mode = current_color_mode
    @source = source
  end

  def update(
    color_mode_name: nil,
    user_theme_name: nil,
    light_theme_name: nil,
    dark_theme_name: nil
  )
    if user_theme_name
      theme = UserTheme.from_name(user_theme_name)
      color_mode = theme&.color_mode
      return false unless color_mode

      theme_symbol = "#{color_mode}_theme".to_sym
      current_user_theme = user[theme_symbol]
      instrument_user_theme_change(
        color_mode: color_mode,
        new_theme: theme,
        current_user_theme: current_user_theme,
      )
      instrument_color_mode_change(new_color_mode: color_mode)

      ActiveRecord::Base.connected_to(role: :writing) do
        user.update(theme_symbol => theme, :color_mode => theme.color_mode)
      end
    else
      light_theme = UserTheme.from_name(light_theme_name) || current_light_theme
      dark_theme = UserTheme.from_name(dark_theme_name) || current_dark_theme
      new_color_mode = ColorMode.from_name(color_mode_name)
      return false unless new_color_mode

      instrument_color_mode_change(new_color_mode: new_color_mode)
      instrument_user_theme_change(
        color_mode: ColorMode::LIGHT,
        new_theme: light_theme,
        current_user_theme: current_light_theme,
      )
      instrument_user_theme_change(
        color_mode: ColorMode::DARK,
        new_theme: dark_theme,
        current_user_theme: current_dark_theme,
      )

      ActiveRecord::Base.connected_to(role: :writing) do
        user.update(color_mode: new_color_mode, light_theme: light_theme, dark_theme: dark_theme)
      end
    end
  end

  private

  attr_reader :user, :current_color_mode, :current_light_theme, :current_dark_theme

  def source
    SOURCE_MAPPING.fetch(@source, DEFAULT_SOURCE)
  end

  def instrument_color_mode_change(new_color_mode:)
    return if new_color_mode.db_value == current_color_mode.db_value

    GlobalInstrumenter.instrument(
      "user.change_color_mode",
      user: user,
      color_mode: new_color_mode.db_value,
      color_mode_previous: current_color_mode.db_value,
      source: source,
    )

    GitHub.dogstats.increment(
      "user.color_mode.changed",
      tags: [
        "value:#{new_color_mode.name}",
        "previous_value:#{current_color_mode.name}",
        "source:#{source.to_s.downcase}",
      ],
    )
  end

  def instrument_user_theme_change(color_mode:, new_theme:, current_user_theme:)
    return if new_theme.name == current_user_theme.name

    GlobalInstrumenter.instrument(
      "user.change_user_theme",
      user: user,
      theme_type: color_mode.hydro_mapping,
      user_theme: new_theme.db_value,
      user_theme_previous: current_user_theme.db_value,
      source: source,
    )

    GitHub.dogstats.increment(
      "user.#{current_color_mode.name}_theme.changed",
      tags: [
        "value:#{new_theme.name}",
        "previous_value:#{current_user_theme.name}",
        "source:#{source.to_s.downcase}",
      ],
    )
  end
end
