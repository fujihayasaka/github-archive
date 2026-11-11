# typed: true
# frozen_string_literal: true

class Settings::SecurityCheckupsController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  def update
    case params[:type]
    when "updated"
      current_user.instrument_security_checkup(params[:type])
      current_user.security_checkup_completed(params[:type])

      safe_redirect_to settings_security_path(anchor: "two-factor-summary")
    when "confirmed"
      current_user.instrument_security_checkup(params[:type])
      current_user.security_checkup_completed(params[:type])

      safe_redirect_to params[:return_to]
    when "postponed"
      current_user.instrument_security_checkup(params[:type])
      current_user.security_checkup_postponed

      safe_redirect_to params[:return_to]
    when "viewed_emails"
      current_user.instrument_security_checkup(params[:type])
      current_user.security_checkup_completed(params[:type])

      safe_redirect_to settings_email_preferences_path
    else
      safe_redirect_to params[:return_to]
    end
  end
end
