# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeQualityUpload < Api::App
  include Api::App::CodeScanningHelpers
  include FeatureFlagHelper

  rate_limit_as Api::RateLimitConfiguration::CODE_SCANNING_UPLOAD_FAMILY

  # Handle a SARIF upload for code quality for internal usage
  put "/repositories/:repository_id/code-quality/analysis", operation_id: :internal do
    @route_owner = "@github/code-scanning-experiences-eng"
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    data = receive_with_schema("code-quality-analysis", "upload-analysis")

    control_access :write_code_scanning,
                    resource: repo,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                    forbid: true,
                    forbid_message: code_scanning_forbid_write_message

    return deliver_empty(status: 200) unless CodeQuality.available?(repo)

    deliver_error_if_archived! repo

    begin
      resp = upload_analysis(repo, data)
    rescue Exception => error # rubocop:todo Lint/RescueException
      deliver_error! 500, message: error.message if Rails.env.development?
      raise error
    end
    deliver_error_from_response!(resp) if resp&.key? :error

    deliver_empty(status: 200)
  end

  private

  def deliver_error_from_response!(response)
    status = if response.dig(:error, :code) == :too_large
      413
    else
      400
    end
    payload = { msg: response.dig(:error, :message) }
    halt deliver_raw payload, status: status
  end

  # Add required metadata to the request and forward it to turboquality
  def upload_analysis(repo, data)
    data = data.with_indifferent_access
    data[:sarif_id] = SimpleUUID::UUID.new.to_guid.to_s
    data[:request_id] = GitHub.context[:request_id]

    GitHub.logger.info(
      "code.namespace": "Api::RepositoryCodeQualityUpload",
      "code.function": "upload_analysis",
      "gh.request_id": data[:request_id],
      "git.ref": data[:ref],
      "git.commit.oid": data[:commit_oid],
    )

    sarif = T.must(begin
      use_jsonschema = ActiveModel::Type::Boolean.new.cast(data.delete(:validate)) || repo.feature_flag_enabled?(:code_scanning_validate_sarif, default: false)
      GitHub::Turboscan.validate_sarif(repo, data.delete(:sarif), use_jsonschema:)
    rescue GitHub::Turboscan::GzipTooLargeError
      return error_hash :too_large, "Gzipped SARIF file is too large"
    rescue GitHub::Turboscan::NoSarifToolsError
      return error_hash :bad_request, "Invalid SARIF document: No valid runs found."
    rescue ::Sarif::Error => e
      return error_hash :bad_request, "Invalid SARIF document: #{e.message}" unless e.message.nil?
    end)

    if repo.default_branch == data[:ref].delete_prefix("refs/heads/") || data[:ref].starts_with?("refs/pull/")
      GitHub::Turboquality.upload_analysis(repo.id, data, sarif)
    end
  end

  sig { params(code: Symbol, message: String).returns({ error: { code: Symbol, message: String } }) }
  private def error_hash(code, message)
    { error: { code: code, message: message } }
  end
end
