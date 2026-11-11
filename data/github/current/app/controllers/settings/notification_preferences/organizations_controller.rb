# typed: true
# frozen_string_literal: true

class Settings::NotificationPreferences::OrganizationsController < ApplicationController
  include Settings::NotificationPreferencesControllerMethods
  include OrganizationsHelper

  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:update, :destroy]

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings
  javascript_bundle :settings

  def destroy
    return render_404 unless request.xhr?

    organization = Organization.find_by(login: params[:id])
    return head 404 if organization.nil?

    settings_response = GitHub.newsies.get_and_update_settings(current_user) do |settings|
      settings.email organization, nil
    end

    return head 500 if settings_response.failed?
    head 200
  end

  def update
    return render_404 unless request.xhr?

    handle_update_for_settings_page
  end

  private

  def handle_update_for_settings_page
    organization = Organization.find_by(login: params[:id])
    return render_404 if organization.nil?

    return render json: { error: "Email is required" }, status: 422 unless params[:email].present?

    begin
      success = current_user.update_organization_notifications_routing(organization, params[:email])

      return head 422 if !success
    rescue ArgumentError => e
      return render json: { error: e.message }, status: 422
    rescue User::NotificationServiceError => e
      return head 500
    end

    head 200
  end

  def target_for_conditional_access
    # This controller requires the user to be logged in, but this filter
    # gets called before `login_required`, so we have to handle the case
    # where `current_user` is `nil`.
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
