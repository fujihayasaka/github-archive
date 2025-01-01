# typed: strict
# frozen_string_literal: true

class Businesses::Billing::CopilotPremiumUsageReportController < Businesses::BillingsController
  include Copilot::Usage
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  allow_verified_fetch only: [:create]

  before_action :authorize_admin_access, only: [:create]

  sig { void }
  def create
    premium_usage_csv_request(entity: Copilot::Business.new(this_business), user_id: current_user.id)
  end

  private

  sig { void }
  def authorize_admin_access
    if FeatureFlag.vexi.enabled?("copilot_usage_report_validations", this_business, default: false) &&
        !this_business.owners.include?(current_user)
      render json: {
        success: false,
        error: "You are not authorized to export premium usage. Please reach out to your enterprise admin or billing manager for this report."
      }, status: :forbidden
    end
  end
end
