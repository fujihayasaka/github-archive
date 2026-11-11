# typed: true
# frozen_string_literal: true

class Settings::AppearancePreferences::RelativeTimesController < ApplicationController
  include Settings::ControllerMethods
  include ApplicationController::VerifiedFetchDependency
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  allow_verified_fetch only: [:update]

  def update
    new_preference = params[:relative_time_preference]
    current_user.settings.set!(:relative_time_preference, new_preference)

    GitHub.dogstats.increment("relative_time_preference.update", tags: ["preference:#{new_preference}"])

    success_message = "Time display preference successfully saved."
    render json: { notice: success_message }
  rescue SettingsCollection::InvalidUpdate => e
    error_message = "Time display preference could not be saved: #{e.message}"
    render json: { error: error_message }, status: 422
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
