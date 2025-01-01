# typed: true
# frozen_string_literal: true

class Settings::ProfileEmailsController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :require_non_enterprise_managed_user, only: [:destroy]

  stylesheet_bundle :settings
  javascript_bundle :settings

  def destroy
    current_user.update_attribute(:profile_email, nil)

    redirect_to settings_user_profile_path(current_user)
  end

  private

  def require_non_enterprise_managed_user
    return render_404 if current_user.is_enterprise_managed?
  end
end
