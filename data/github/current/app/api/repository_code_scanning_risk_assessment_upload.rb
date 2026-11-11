# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeScanningRiskAssessmentUpload < Api::App
  include Api::App::CodeScanningHelpers
  include FeatureFlagHelper

  rate_limit_as Api::RateLimitConfiguration::CODE_SCANNING_UPLOAD_FAMILY

  # Handle a SARIF upload for code scanning risk assessments for internal usage
  put "/repositories/:repository_id/code-scanning/risk-assessment", operation_id: "code-scanning/risk-assessment-upload", read_from_replicas: true do
    @route_owner = "@github/code-scanning-experiences-eng"
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    ensure_read_access!(repo, forbid: repo.public?)

    deliver_error_if_archived! repo

    data = receive_with_openapi

    # Initially we control access to risk assessments via a feature flag
    # Later we'll check whether the repo and assessment id match an existing assessment.
    return deliver_error(404) unless code_scanning_risk_assessment_available?(repo, data["assessment_id"])

    control_access :write_code_scanning_risk_assessment,
                    resource: repo,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                    forbid: true

    begin
      response = upload_analysis(repo, data)
    rescue Exception => error # rubocop:todo Lint/RescueException
      deliver_error! 500, message: error.message if Rails.env.development?
      raise error
    end
    if response&.key? :error
      status = case response.dig(:error, :code)
      when :bad_request
        400
      when :too_large
        413
      when :service_unavailable
        503
      else
        500
      end
      deliver_error! status, message: response.dig(:error, :message)
    end

    deliver_empty(status: 200)
  end

  private

  sig { params(repo: Repository, forbid: T::Boolean).void }
  def ensure_read_access!(repo, forbid: false)
    can_read = access_allowed? :v4_get_repo,
                                resource: repo,
                                repo: repo,
                                allow_integrations: true,
                                allow_user_via_granular_actor: true

    deliver_error!(forbid ? 403 : 404) if !can_read
  end

  def code_scanning_risk_assessment_available?(repo, assessment_id)
    # Security assessments are only available for organizations
    return false unless repo.owner&.organization?

    # If the FF is enabled, then we allow all access to this endpoint
    return true if FeatureFlag.vexi.enabled?(:code_scanning_risk_assessment, repo, repo.owner, default: false)

    # Check whether the repo has the specific assessment that is not completed yet.
    SecurityProductsEnablement::CodeScanningAssessmentRepository
      .not_completed
      .where(repository_id: repo.id, assessment_id: assessment_id)
      .exists?
  end

  # Add required metadata to the request and forward it to turboscan
  def upload_analysis(repo, data)
    data = data.with_indifferent_access
    GitHub.logger.info(
      "code.namespace": "Api::RepositoryCodeScanningRiskAssessmentUpload",
      "code.function": "upload_analysis",
      "gh.request_id": data[:request_id],
    )

    sarif_data = data[:sarif]
    # The sarif data will be empty if all languages failed. In that case we do not
    # need to validate the SARIF, but we still send the result to turboscan to
    # make it explicitly acknowledge the failure.

    sarif = nil
    unless sarif_data.nil?
      # Validate the SARIF file
      sarif = T.must(begin
        use_jsonschema = ActiveModel::Type::Boolean.new.cast(data[:validate]) || repo.feature_flag_enabled?(:code_scanning_validate_sarif, default: false)
        GitHub::Turboscan.validate_sarif(repo, sarif_data, use_jsonschema:)
      rescue GitHub::Turboscan::GzipTooLargeError
        return error_hash :too_large, "Gzipped SARIF file is too large"
      rescue GitHub::Turboscan::NoSarifToolsError
        return error_hash :bad_request, "Invalid SARIF document: No valid runs found."
      rescue ::Sarif::Error => e
        return error_hash :bad_request, "Invalid SARIF document: #{e.message}" unless e.message.nil?
      end)
    end

    resp = GitHub::Turboscan::RiskAssessment.process_risk_assessment(
      owner_id: repo.owner_id,
      repository_id: repo.id,
      assessment_id: data[:assessment_id],
      sarif_bytes: sarif&.gzip,
    )
    if resp.blank? || resp.error.present?
      error_hash :service_unavailable, "Code scanning unavailable. Please try again later."
    end
  end

  sig { params(code: Symbol, message: String).returns({ error: { code: Symbol, message: String } }) }
  private def error_hash(code, message)
    { error: { code: code, message: message } }
  end
end
