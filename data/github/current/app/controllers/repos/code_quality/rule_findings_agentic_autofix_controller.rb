# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RuleFindingsAgenticAutofixController < Repos::CodeQuality::BaseRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  before_action :ensure_feature_code_quality_enabled
  before_action :check_code_quality_write
  before_action :try_parse_json_params, only: [:create]

  sig { void }
  def create
    return render_404 unless CodeQuality::AgenticAutofix.enabled?(current_repository, current_user)

    raw_finding_numbers = params[:finding_numbers]
    return render status: :unprocessable_entity, json: { message: "Finding numbers are required" } if !raw_finding_numbers.is_a?(Array)

    finding_numbers = T.let([], T::Array[Integer])
    raw_finding_numbers.each do |finding_number|
      next if finding_number.blank?

      number = finding_number.to_i
      return render status: :unprocessable_entity, json: { message: "Invalid finding numbers" } unless number.positive?

      finding_numbers << number
    end
    return render status: :unprocessable_entity, json: { message: "Finding numbers are required" } if finding_numbers.empty?

    begin
      agentic_autofix_response = CodeQuality::AgenticAutofix.start_agentic_autofix(
        repository: current_repository,
        rule_id: params[:rule_id].to_s,
        finding_numbers:,
        current_user:,
        analytics_source: "repo_rule_findings",
      )
    rescue CodeScanning::AgenticAutofixError => e
      return render json: e.to_h, status: e.status
    end

    render json: { message: "Findings successfully assigned to Copilot and it will create a PR shortly", agenticAutofixJobId: agentic_autofix_response.job_id }, status: :ok
  end
end
