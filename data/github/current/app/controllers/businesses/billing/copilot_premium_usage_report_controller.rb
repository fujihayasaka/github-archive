# typed: strict
# frozen_string_literal: true

class Businesses::Billing::CopilotPremiumUsageReportController < Businesses::BillingsController
  include Copilot::Usage
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  before_action :login_required
  allow_verified_fetch only: [:create]
  before_action :parse_json_params, only: [:create]

  before_action :authorize_admin_access, only: [:create]

  sig { void }
  def create
    entity = find_selected_organization ? Copilot::Organization.new(T.must(find_selected_organization)) : Copilot::Business.new(this_business)
    premium_usage_csv_request(entity: entity, user_id: current_user.id)
  end

  private

  sig { void }
  def authorize_admin_access
    if FeatureFlag.vexi.enabled?("copilot_usage_report_validations", this_business, default: false)
      if params[:organization].present?
        selected_org = find_selected_organization
        unless selected_org&.adminable_by?(current_user)
          render json: {
          success: false,
          error: "You are not authorized to export premium usage. Please reach out to your enterprise admin or billing manager for this report."
          }, status: :forbidden and return
        end
      elsif !(this_business.owner?(current_user) || this_business.billing_manager?(current_user))
        render json: {
          success: false,
          error: "You are not authorized to export premium usage. Please reach out to your enterprise admin or billing manager for this report."
        }, status: :forbidden and return
      end
    end
  end

  sig { returns(T.nilable(Organization)) }
  def find_selected_organization
    return nil unless params[:organization].present?

    org_id = Platform::Helpers::GlobalId.parse(params[:organization]).id.to_s
    Organization.find_by(id: org_id)
  end
end
