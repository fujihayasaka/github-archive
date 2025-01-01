# typed: true
# frozen_string_literal: true

class Orgs::SecurityAnalysisController < Orgs::Controller
  # Access
  before_action :manage_security_products_permission_required

  def update
    error_message = UpdateSecuritySettings.perform(current_organization, params, actor: current_user).try(:fetch, :error, nil)
    return redirect_to(:back, flash: { error: error_message }) if error_message.present?

    track_task_completion
    flash[:notice] = "Security settings updated for #{current_organization.name}'s repositories."

    redirect_to settings_org_security_analysis_path(current_organization, show_update_tip: params[:show_update_tip], show_alert_tip: params[:show_alert_tip], tip: get_onboarding_tip)
  end

  private

  def current_organization # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @current_organization if defined? @current_organization
    @current_organization = Organization.find_by_login(org_login_param)
  end

  def target_for_conditional_access
    current_organization
  end

  def get_onboarding_tip
    referrer = Addressable::URI.parse(request.referrer)
    return nil unless referrer && referrer.domain == request.domain
    return nil unless referrer.query_values
    referrer.query_values["tip"]
  end

  def track_task_completion
    if params[:advanced_security] == "enable_all"
      OnboardingTasks::AdvancedSecurity::EnableAdvancedSecurity.new(taskable: current_organization, user: current_user).complete
    end
    if params[:secret_scanning] == "enable_all"
      OnboardingTasks::AdvancedSecurity::EnableSecretScanning.new(taskable: current_organization, user: current_user).complete
    end
    if params[:code_scanning] == "enable_all"
      OnboardingTasks::AdvancedSecurity::EnableCodeScanning.new(taskable: current_organization, user: current_user).complete
    end
    if params[:secret_scanning_push_protection] == "enable_all"
      OnboardingTasks::AdvancedSecurity::EnablePushProtection.new(taskable: current_organization, user: current_user).complete
    end
  end
end
