# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CodeScanning::DelegatedAlertDismissalSettingsController < AbstractRepositoryController
  track_availability_slo "ui-request"
  track_latency_slo "p50-ui-request", 500
  track_latency_slo "p99-ui-request", 2000

  skip_before_action :privacy_check
  skip_before_action :cap_pagination
  before_action :manage_security_products_permission_required
  before_action :writable_repository_required

  def update
    can_enable = CodeScanning::AlertDismissalService.new(current_repository).can_enable?.value
    return render_404 unless can_enable

    case policy_value
    when "enabled"
      result = CodeScanning::AlertDismissalService.new(current_repository).enable(actor: current_user, options: {})
      if result.error?
        flash[:error] = "Delegated alert dismissal could not be enabled."
      else
        GitHub.instrument("repo.code_scanning_delegated_alert_dismissal_enabled", actor: current_user, repo: current_repository)
        flash[:notice] = "Delegated alert dismissal is now enabled for this repository."
      end
    when "disabled"
      result = CodeScanning::AlertDismissalService.new(current_repository).disable(actor: current_user, options: {})
      if result.error?
        flash[:error] = "Delegated alert dismissal could not be disabled."
      else
        GitHub.instrument("repo.code_scanning_delegated_alert_dismissal_disabled", actor: current_user, repo: current_repository)
        flash[:notice] = "Delegated alert dismissal is now disabled for this repository."
      end
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end

  private

  def policy_value
    return "enabled" if params[:value] == "1"
    return "disabled" if params[:value] == "0"
    "invalid"
  end

end
