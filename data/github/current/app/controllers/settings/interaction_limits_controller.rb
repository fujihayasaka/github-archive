# typed: true
# frozen_string_literal: true

class Settings::InteractionLimitsController < ApplicationController
  include Settings::ControllerMethods
  include BusinessesHelper
  include OrganizationsHelper
  include SettingsHelper
  include TwoFactorHelper
  include ApplicationController::VerifiedFetchDependency

  stylesheet_bundle :settings
  javascript_bundle :settings
  javascript_bundle :sessions

  allow_verified_fetch only: [:update]

  before_action :login_required
  before_action :ensure_can_set_interaction_limits
  before_action :ensure_trade_restrictions_allows_org_settings_access

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:show]

  def show
    render "settings/interaction_limits/show"
  end

  def update
    limit = InteractionLimits::SetInteractionLimit.enum_to_limit_name(
      params[:interaction_setting]
    )
    duration = if params[:expiry].present?
      params[:expiry].downcase.to_sym
    else
      :one_day
    end

    inputs = {
      object: current_user,
      limit: limit,
      duration: duration,
      actor: current_user,
    }

    result = InteractionLimits::SetInteractionLimit.call(inputs)

    if result.success?
      flash[:notice] = "User interaction limit settings saved."
    else
      flash[:error] = result.error
    end

    if params[:return_to].present?
      safe_redirect_to(params[:return_to], fallback: settings_interaction_limits_path)
    else
      redirect_to settings_interaction_limits_path
    end
  end

  private

  def ensure_can_set_interaction_limits
    return render_404 if current_user.is_enterprise_managed?

    return render_404 unless GitHub.interaction_limits_enabled?
    render_404 unless current_user.can_set_interaction_limits?(current_user)
  end
end
