# typed: true
# frozen_string_literal: true

class Settings::AppearancePreferencesController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :all_color_mode_themes, only: [:show]

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    # If a user hasn't picked a color mode, update their choice
    # to be the default we display on this page. This behavior
    # ensures users who see the page won't be confused if/when
    # we change the default color mode from LIGHT to AUTO.
    if current_user.color_mode.unset?
      color_mode_updater.update(color_mode_name: ColorMode.default.name)
    end

    render "settings/appearance_preferences/show"
  end

  private

  def color_mode_updater # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_color_mode_updater ||= Settings::AppearancePreferences::ColorModesUpdater.new(
      user: current_user,
      current_light_theme: current_user.light_theme,
      current_dark_theme: current_user.dark_theme,
      current_color_mode: current_user.color_mode,
      source: "settings_viewed",
    )
  end

  def label_for_theme(theme)
    if user_or_global_preview_enabled?(:color_modes_color_blind_themes_2)
      if theme.label == "Light colorblind"
        "Light Protanopia & Deuteranopia"
      elsif theme.label == "Dark colorblind"
        "Dark Protanopia & Deuteranopia"
      else
        theme.label
      end
    else
      theme.label
    end
  end

  helper_method :label_for_theme
end
