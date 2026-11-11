# typed: true
# frozen_string_literal: true

class Orgs::Settings::InteractionLimitsController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :ensure_interaction_limits_enabled
  before_action :ensure_can_manage_interaction_limits

  allow_verified_fetch only: [:update]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
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
      object: this_organization,
      limit: limit,
      duration: duration,
      actor: current_user,
    }

    result = InteractionLimits::SetInteractionLimit.call(inputs)

    if result.success?
      flash[:notice] = "Organization interaction limit settings saved."
    else
      flash[:error] = result.error
    end

    if params[:return_to].present?
      safe_redirect_to(params[:return_to], fallback: org_interaction_limits_path(this_organization))
    else
      redirect_to org_interaction_limits_path(this_organization)
    end
  end

  private

  def ensure_interaction_limits_enabled
    render_404 unless GitHub.interaction_limits_enabled?
  end

  def ensure_can_manage_interaction_limits
    render_404 unless this_organization.can_set_interaction_limits?(current_user)
  end
end
