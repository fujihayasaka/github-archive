# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CodeScanning::SeveritySettingsController < AbstractRepositoryController
  include SecurityAnalysisSettingsHelper

  track_availability_slo "ui-request"
  track_latency_slo "p50-ui-request", 500
  track_latency_slo "p99-ui-request", 2000

  skip_before_action :privacy_check
  skip_before_action :cap_pagination
  before_action :manage_security_products_permission_required
  before_action :writable_repository_required

  def update
    return render_404 unless current_repository.public? || advanced_security_configurable?

    config = CodeScanningRepositoryConfig.new(current_repository)

    if params[:severity].present?
      config.set_code_scanning_severity_choice(choice: params[:severity], actor: current_user)
    end

    if params[:security_severity].present?
      config.set_code_scanning_security_severity_choice(choice: params[:security_severity], actor: current_user)
    end

    flash[:notice] = "Code Scanning alert severity settings saved."
    redirect_to :back
  end
end
