# typed: true
# frozen_string_literal: true

class GitHubModels::OrganizationBillingsController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :require_feature
  before_action :organization_admin_required
  before_action :github_models_required
  before_action :parse_json_params, only: [:create]

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:create]

  def create
    if params[:enable] == "1"
      success = this_organization.enable_models_billing(current_user)
      status = success ? :ok : :unprocessable_entity
    elsif params[:enable] == "0"
      success = this_organization.disable_models_billing(current_user)
      status = success ? :ok : :unprocessable_entity
    end

    render status: status, json: { enabled: this_organization.models_billing_enabled? }
  end

  private

  def require_feature
    return if user_feature_enabled?(:github_models_billing_ui)
    return if this_organization.feature_enabled?(:github_models_billing_ui)

    render_404
  end
end
