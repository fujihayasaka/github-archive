# typed: strict
# frozen_string_literal: true

class Orgs::CopilotPremiumUsageReportController < Orgs::Controller
  include Copilot::Usage
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  before_action :login_required
  allow_verified_fetch only: [:create]
  before_action :parse_json_params, only: [:create]

  before_action :authorize_admin_access, only: [:create]

  sig { void }
  def create
    organization = find_selected_organization || this_organization
    premium_usage_csv_request(entity: Copilot::Organization.new(organization), user_id: current_user.id)
  end

  private

  sig { void }
  def authorize_admin_access
    if FeatureFlag.vexi.enabled?("copilot_usage_report_validations", this_organization, default: false) &&
        !(
          this_organization.adminable_by?(current_user) ||
          this_organization.billing_manager?(current_user) ||
          this_organization.business&.owner?(current_user) ||
          this_organization.business&.billing_manager?(current_user)
        )
      render json: {
        success: false,
        error: "You are not authorized to export premium usage. Please reach out to your enterprise/organization admin or billing manager for this report."
      }, status: :forbidden
    end
  end

  sig { returns(T.nilable(Organization)) }
  def find_selected_organization
    org_global_id = params[:organization]
    return nil unless org_global_id.present?

    org_id = Platform::Helpers::GlobalId.parse(org_global_id).id.to_s
    Organization.find_by(id: org_id)
  end
end
