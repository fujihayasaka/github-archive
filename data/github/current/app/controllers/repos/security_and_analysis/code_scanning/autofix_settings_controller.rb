# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CodeScanning::AutofixSettingsController < AbstractRepositoryController
  include SecurityAnalysisSettingsHelper

  track_availability_slo "ui-request"
  track_latency_slo "p50-ui-request", 500
  track_latency_slo "p99-ui-request", 2000

  skip_before_action :privacy_check
  skip_before_action :cap_pagination
  before_action :manage_security_products_permission_required
  before_action :writable_repository_required
  before_action :code_scanning_autofix_required

  def update
    policy = params[:policy]
    if policy.nil? && params[:value]
      policy = params[:value] == "0" ? "disabled" : "enabled"
    end

    case policy
    when "enabled"
      CodeScanningRepositoryConfig.new(current_repository).enable_code_scanning_autofix_settings(actor: current_user)

      GitHub.instrument("repo.code_scanning_autofix_enabled", actor: current_user, repo: current_repository, org: current_repository.owner)
      GlobalInstrumenter.instrument("security_analysis.update", event_name: "code_scanning_autofix.enabled", owner: current_repository.owner, actor: current_user)

      flash[:notice] = "Autofix is now enabled for this repository."
    when "disabled"
      CodeScanningRepositoryConfig.new(current_repository).disable_code_scanning_autofix_settings(actor: current_user)

      GitHub.instrument("repo.code_scanning_autofix_disabled", actor: current_user, repo: current_repository, org: current_repository.owner)
      GlobalInstrumenter.instrument("security_analysis.update", event_name: "code_scanning_autofix.disabled", owner: current_repository.owner, actor: current_user)

      flash[:notice] = "Autofix is now disabled for this repository."
    else
      flash[:error] = "You provided an invalid input value. Please try again."
    end

    redirect_to :back
  end

  private

  def code_scanning_autofix_required
    render_404 unless code_scanning_autofix_settings_configurable?
  end

  def code_scanning_autofix_settings_configurable?
    CodeScanning::Autofix.repo_settings_configurable?(current_repository)
  end
end
