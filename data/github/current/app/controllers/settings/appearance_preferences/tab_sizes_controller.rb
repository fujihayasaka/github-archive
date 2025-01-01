# typed: true
# frozen_string_literal: true

class Settings::AppearancePreferences::TabSizesController < ApplicationController
  include OrganizationsHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  allow_verified_fetch only: [:update]

  def update
    new_size = params[:tab_size_rendering_preference]
    current_user.settings.set!(:tab_size, new_size)
    success_message = "Tab size rendering preference successfully saved."

    size_tag = UserSettings::TAB_SIZES.include?(new_size.to_i) ? new_size : nil

    GitHub.dogstats.increment("tab_size_rendering_preference.update", tags: ["size:#{size_tag}"])

    if request.xhr?
      render json: { notice: success_message }
    else
      flash[:notice] = success_message
      redirect_to settings_appearance_preferences_path
    end

  rescue SettingsCollection::InvalidUpdate => e
    error_message = "Tab size rendering preference could not be saved: #{e.message}"

    if request.xhr?
      render json: { error: error_message }, status: 422
    else
      flash[:error] = error_message
      redirect_to settings_appearance_preferences_path
    end
  end

  private

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end
end
