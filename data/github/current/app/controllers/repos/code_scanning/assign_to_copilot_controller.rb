# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AssignToCopilotController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::ControllerAccessChecks

  allow_verified_fetch only: [:create]

  before_action :login_required
  before_action :check_code_scanning_write
  before_action :try_parse_json_params, only: [:create]

  def create
    return head(:not_found) if GitHub.enterprise?

    return head(:not_found) unless CodeScanning::AgenticAutofix.enabled?(current_repository, current_user)
    return head(:not_found) unless FeatureFlag.vexi.enabled?(:code_scanning_autofix_use_cca_public_preview, current_repository, current_repository.owner, default: false)

    return head(:not_found) unless current_repository.writable_by?(current_user)

    alert_numbers = params[:alert_numbers]
    return render status: :unprocessable_entity, json: { message: "Alert numbers are required" } if alert_numbers.blank? || !alert_numbers.is_a?(Array)

    alert_numbers = alert_numbers.map(&:to_i)
    return render status: :unprocessable_entity, json: { message: "Invalid alert numbers" } unless alert_numbers.all? { |n| n > 0 && n <= Api::App::CodeScanningHelpers::MAX_ALERT_NUMBER }

    begin
      agentic_autofix_response = CodeScanning::AgenticAutofix.start_agentic_autofix(
        repository: current_repository,
        alert_numbers:,
        current_user:,
        analytics_source: "repo_alert_list",
      )
    rescue CodeScanning::AgenticAutofixError => e
      return render json: e.to_h, status: e.status
    end

    render json: { message: "Alerts successfully assigned to Copilot and it will create a PR shortly", agenticAutofixJobId: agentic_autofix_response.job_id }
  end
end
