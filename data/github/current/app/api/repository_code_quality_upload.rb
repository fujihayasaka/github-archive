# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeQualityUpload < Api::App
  include Api::App::CodeScanningHelpers
  include Api::App::CodeQualityHelpers
  include FeatureFlagHelper

  rate_limit_as Api::RateLimitConfiguration::DEFAULT_FAMILY

  # Handle a SARIF upload for code quality for internal usage
  put "/repositories/:repository_id/code-quality/analysis", operation_id: :internal do
    @route_owner = "@github/code-scanning-experiences-eng"
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    ensure_read_access_and_code_quality_enabled!(repo, forbid: repo.public?)

    data = receive_with_schema("code-quality-analysis", "upload-analysis")
    ensure_commit_oid_format!(repo, data["commit_oid"])

    control_access :write_code_scanning,
                    resource: repo,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                    forbid: true,
                    forbid_message: code_scanning_forbid_write_message

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

    response = nil
    if data[:ref].starts_with?("refs/pull/")
      response = GitHub::Turboquality.upload_analysis(repo.id, repo.owner_id, data, sarif)
      key = CodeQualityPullRequestAnalyses.analysis_first_upload_key(repository: repo, ref: data[:ref], commit_oid: data[:commit_oid])
      upload_analysis_start_time = Time.now

      begin
        first_analysis = CodeScanning::KV.store.get(key).value!

        if first_analysis.nil?
          CodeScanning::KV.store.set(key, upload_analysis_start_time.to_s, expires: 1.day.from_now)
          TrackCodeQualityDelayJob.schedule(repo, data[:ref], data[:commit_oid])
        end
      rescue => e
        GitHub.logger.error(
          "code.namespace": "Api::RepositoryCodeQualityUpload",
          "code.function": "upload_analysis",
          "error": "KV store or delay tracking failed: #{e.class}: #{e.message}",
          "gh.request_id": data[:request_id],
          "git.ref": data[:ref],
          "git.commit.oid": data[:commit_oid],
        )
        # Proceed without delay tracking
      end
    elsif repo.default_branch == data[:ref].delete_prefix("refs/heads/")
      response = GitHub::Turboquality.upload_analysis(repo.id, repo.owner_id, data, sarif)
      CodeQuality::RepositoryUpdatePublisher.publish_repository(repo:, code_quality_enabled: true)
    end

    response
  end
  sig { params(code: Symbol, message: String).returns({ error: { code: Symbol, message: String } }) }
  private def error_hash(code, message)
    { error: { code: code, message: message } }
  end
end
