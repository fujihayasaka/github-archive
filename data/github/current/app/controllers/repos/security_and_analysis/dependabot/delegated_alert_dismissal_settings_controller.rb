# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::Dependabot::DelegatedAlertDismissalSettingsController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
                      ApplicationRecord::Repositories,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::Notify,
    only: [:update]

  track_availability_slo "ui-request"
  track_latency_slo "p50-ui-request", 500
  track_latency_slo "p99-ui-request", 2000

  skip_before_action :privacy_check
  skip_before_action :cap_pagination
  before_action :manage_security_products_permission_required
  before_action :writable_repository_required

  def update
    service = SecurityProduct::DependabotDelegatedAlertDismissal.new(current_repository)

    # Check if the feature is available for this repository
    can_enable_result = service.can_enable?(actor: current_user, options: {})

    # If the feature cannot be enabled and is not already enabled
    unless can_enable_result.value || service.enabled?
      # If the feature is not available (e.g., feature flag disabled), return 404
      # For other errors (e.g., GHAS/code security disabled), show an error message
      if can_enable_result.error == :feature_not_available
        return render_404
      elsif can_enable_result.error?
        flash[:error] = SecurityProduct::DependabotDelegatedAlertDismissal.error_to_message(can_enable_result.error)
      else
        flash[:error] = "Delegated alert dismissal is not available for this repository."
      end
      return redirect_to :back
    end

    case policy_value
    when "enabled"
      result = service.enable(actor: current_user, options: {})
      if result.error?
        flash[:error] = SecurityProduct::DependabotDelegatedAlertDismissal.error_to_message(result.error)
      else
        flash[:notice] = "Delegated alert dismissal is now enabled for this repository."
      end
    when "disabled"
      result = service.disable(actor: current_user, options: {})
      if result.error?
        flash[:error] = SecurityProduct::DependabotDelegatedAlertDismissal.error_to_message(result.error)
      else
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
