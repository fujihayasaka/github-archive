# typed: true
# frozen_string_literal: true

class Businesses::CodeScanningAutofixPoliciesController < Businesses::BusinessController
  include SecretScanningCustomPatternsHelper

  before_action :modify_code_security_policies_permission_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  track_latency_slo "p99-ui-request", 2000
  track_latency_slo "p50-ui-request", 500
  track_availability_slo "ui-request"

  def update
    case params[:policy]
    when CodeScanning::AutofixCodeql::POLICY_NAME
      update_codeql
    when CodeScanning::AutofixThirdPartyTools::POLICY_NAME
      update_third_party_tools
    else
      render_404
    end
  end

  private

  def update_codeql
    return render_404 unless CodeScanning::AutofixCodeql.policy_available?(this_business)

    case params[:value]
    when "allowed"
      this_business.allow_code_scanning_autofix_policy(actor: current_user)
      flash[:notice] = "Policy changes saved."
    when "disallowed"
      this_business.disallow_code_scanning_autofix_policy(actor: current_user)
      flash[:notice] = "Policy changes saved."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end

  def update_third_party_tools
    return render_404 unless CodeScanning::AutofixThirdPartyTools.policy_available?(this_business)

    case params[:value]
    when "allowed"
      this_business.allow_code_scanning_autofix_third_party_tools_policy(actor: current_user)
      flash[:notice] = "Policy changes saved."
    when "disallowed"
      this_business.disallow_code_scanning_autofix_third_party_tools_policy(actor: current_user)
      flash[:notice] = "Policy changes saved."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end
end
