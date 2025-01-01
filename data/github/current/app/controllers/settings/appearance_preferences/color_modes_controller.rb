# typed: true
# frozen_string_literal: true

class Settings::AppearancePreferences::ColorModesController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  allow_verified_fetch only: [:update]

  def update
    successful_update = false

    if system_mode?
      successful_update = color_mode_updater.update(
        color_mode_name: params[:color_mode],
        light_theme_name: params[:light_theme],
        dark_theme_name: params[:dark_theme],
      )
    elsif single_mode?
      successful_update = color_mode_updater.update(user_theme_name: params[:user_theme])
    end

    if successful_update
      if request.xhr?
        render json: {
          color_mode: current_user.color_mode_with_default.name,
          light_theme: current_user.light_theme.name,
          dark_theme: current_user.dark_theme.name
        }
      else
        flash[:notice] = "Theme preference successfully saved."
        redirect_to settings_appearance_preferences_path
      end
    else
      if request.xhr?
        render(
          status: 404,
          json: "Unable to update color mode, themes not found.",
        )
      else
        flash[:error] = "Unable to update color mode, themes not found."
        redirect_to settings_appearance_preferences_path
      end
    end
  end

  private

  def color_mode_updater # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @_color_mode_updater ||= Settings::AppearancePreferences::ColorModesUpdater.new(
      user: current_user,
      current_light_theme: current_user.light_theme,
      current_dark_theme: current_user.dark_theme,
      current_color_mode: current_user.color_mode,
      source: params[:source],
    )
  end

  def system_mode?
    params[:color_mode].present?
  end

  def single_mode?
    params[:user_theme].present?
  end
end
