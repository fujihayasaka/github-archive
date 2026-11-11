# typed: true
# frozen_string_literal: true

class Businesses::CodeScanningAiFindingsPoliciesController < Businesses::BusinessController
  include SecretScanningCustomPatternsHelper

  before_action :modify_code_security_policies_permission_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  track_latency_slo "p99-ui-request", 2000
  track_latency_slo "p50-ui-request", 500
  track_availability_slo "ui-request"

  def update
    case params[:policy]
    when CodeScanning::AiFindings::POLICY_NAME
      update_ai_findings
    else
      render_404
    end
  end

  private

  def update_ai_findings
    return render_404 unless CodeScanning::AiFindings.policy_available?(this_business)

    case params[:value]
    when "allowed"
      this_business.allow_code_scanning_ai_findings_policy(actor: current_user)
      flash[:notice] = "Policy changes saved."
    when "disallowed"
      this_business.disallow_code_scanning_ai_findings_policy(actor: current_user)
      flash[:notice] = "Policy changes saved."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end
end
