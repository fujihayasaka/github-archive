# typed: strict
# frozen_string_literal: true

class Orgs::CopilotPremiumUsageReportController < Orgs::Controller
  include Copilot::Usage
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  allow_verified_fetch only: [:create]

  before_action :authorize_admin_access, only: [:create]

  sig { void }
  def create
    premium_usage_csv_request(entity: Copilot::Organization.new(this_organization), user_id: current_user.id)
  end

  private

  sig { void }
  def authorize_admin_access
    if FeatureFlag.vexi.enabled?("copilot_usage_report_validations", this_organization, default: false) &&
       !(this_organization.adminable_by?(current_user) || this_organization.business&.owners&.include?(current_user))
      render json: {
        success: false,
        error: "You are not authorized to export premium usage. Please reach out to your enterprise/organization admin or billing manager for this report."
      }, status: :forbidden
    end
  end
end
