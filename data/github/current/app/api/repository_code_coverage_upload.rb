# typed: true
# frozen_string_literal: true

require "github/turboquality"

class Api::RepositoryCodeCoverageUpload < Api::App
  include Api::App::CodeScanningHelpers
  include FeatureFlagHelper

  MAX_COVERAGE_REPORT_SIZE = 10.megabytes

  rate_limit_as Api::RateLimitConfiguration::DEFAULT_FAMILY

  # Handle a code coverage report upload for internal usage
  put "/repositories/:repository_id/code-coverage/report", operation_id: "code-coverage/upload-code-coverage-report", read_from_replicas: true do
    @route_owner = "@github/code-scanning-experiences-eng"
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    deliver_error!(404) unless code_coverage_upload_available?(repo)

    ensure_read_access!(repo, forbid: repo.public?)

    data = receive_with_openapi
    ensure_commit_oid_format!(repo, data["commit_oid"])

    if FeatureFlag.vexi.enabled?(:use_code_quality_fgr, repo, default: false)
      control_access :write_code_quality,
        resource: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        forbid: true,
        forbid_message: "You are not authorized to upload code coverage reports."
    else
      control_access :write_code_scanning,
        resource: repo,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        forbid: true,
        forbid_message: "You are not authorized to upload code coverage reports."
    end

    unless CodeQuality.enabled?(repo)
      deliver_error!(403, message: "Code quality is not enabled for this repository. Enable code quality in your repository settings.")
    end

    deliver_error_if_archived! repo

    validated_data = transform_data_for_upload!(repo: repo, data: data.with_indifferent_access)

    resp = upload_coverage(repo, validated_data)
    deliver_error_from_response!(resp) if resp&.key? :error

    deliver_empty(status: 201)
  end

  private

  sig { params(repo: Repository, data: T::Hash[T.any(Symbol, String), T.untyped]).returns(T::Hash[T.any(Symbol, String), T.untyped]) }
  def transform_data_for_upload!(repo:, data:)
    # The validation criteria for the ref and commit_oid are as follows:
    # - If a pull_request_number is provided and the pull request with that number exists
    # - If no pull_request_number is provided, the ref must be a valid reference in the repository.
    # - In all cases, commit_oid must identify an existing commit in the repository.
    validate_language!(data[:language_name])
    if data[:pull_request_number]
      pull = PullRequest.with_number_and_repo(data.delete(:pull_request_number).to_i, repo)
      deliver_error!(400, message: "Provided pull_request_number is not valid") unless pull
      data[:base_branch_name] = pull.base_ref_name
      data[:branch_name] = pull.head_ref_name
      data[:pr_number] = pull.number
    else
      ref = data[:ref]
      deliver_error!(400, message: "Ref or Pull Request number is required") unless ref
      provided_ref = repo.refs.find(ref)
      deliver_error!(400, message: "Provided ref is not a valid reference") unless provided_ref
      deliver_error!(400, message: "Only default branch is allowed if no pull_request_number is provided") unless provided_ref.default_branch?
      data[:branch_name] = provided_ref.name
    end

    deliver_error!(400, message: "Provided commit_oid is required") unless data[:commit_oid]
    commit = begin
      repo.commits.find(data[:commit_oid])
    rescue GitRPC::ObjectMissing, GitRPC::InvalidObject, ArgumentError
      nil
    end
    deliver_error!(400, message: "Provided commit_oid is not a valid commit") unless commit

    latest_commit = repo.commits.last_touched(data[:branch_name])

    if latest_commit.nil?
      deliver_error!(400, message: "Coverage report for #{commit.oid} cannot be uploaded for #{data[:branch_name]}")
    end

    return data if latest_commit.oid == commit.oid

    halt deliver_raw({ message: "Coverage report for #{commit.oid} cannot be uploaded for #{data[:branch_name]} because it is not the latest commit on the branch" },
       status: 200)
  end

  sig { params(lang: T.nilable(String)).returns(T.nilable(Linguist::Language)) }
  def validate_language!(lang)
    if lang.nil? || lang.empty?
      deliver_error!(400, message: "language_name is required")
    end
    language = Linguist::Language.find_by_alias(lang)
    deliver_error!(400, message: "Provided language_name is not valid") unless language
  end

  sig { params(repo: Repository, forbid: T::Boolean).void }
  def ensure_read_access!(repo, forbid: false)
    can_read = access_allowed? :v4_get_repo,
                                resource: repo,
                                repo: repo,
                                allow_integrations: true,
                                allow_user_via_granular_actor: true

    deliver_error!(forbid ? 403 : 404) if !can_read
  end

  sig { params(repo: Repository).returns(T::Boolean) }
  def code_coverage_upload_available?(repo)
    owner = repo.owner
    return false unless owner&.organization?

    CodeCoverage.available?(repo) && FeatureFlag.vexi.enabled?(:code_coverage_upload_api, owner, default: false)
  end

  def deliver_error_from_response!(response)
    status = case response.dig(:error, :code)
    when :too_large
      413
    when :unprocessable
      422
    when :internal_server_error
      500
    else
      400
    end
    payload = { message: response.dig(:error, :message) }
    halt deliver_raw payload, status: status
  end

  def upload_coverage(repo, data)
    data = data.with_indifferent_access
    data[:coverage_report_id] = SimpleUUID::UUID.new.to_guid.to_s
    data[:request_id] = GitHub.context[:request_id]

    GitHub.logger.info(
      "code.namespace": "Api::RepositoryCodeCoverageUpload",
      "code.function": "upload_coverage",
      "gh.request_id": data[:request_id],
      "git.ref": data[:ref],
      "git.commit.oid": data[:commit_oid],
    )

    coverage_report = begin
      Base64.strict_decode64(data.delete(:coverage_report).to_s)
    rescue ArgumentError
      return error_hash :bad_request, "Invalid coverage report: Expected valid Base64 encoded content."
    end

    if coverage_report.bytesize > MAX_COVERAGE_REPORT_SIZE
      return error_hash :too_large, "Coverage report exceeds the maximum allowed size of #{ActiveSupport::NumberHelper.number_to_human_size(MAX_COVERAGE_REPORT_SIZE)}"
    end

    begin
      GitHub::Turboquality.upload_coverage_report(repo.id, data, coverage_report)
    rescue ::Azure::Core::Http::HTTPError => e
      return error_hash :too_large, "Coverage report is too large" if e.status_code == 413
      return error_hash :unprocessable, "Coverage report payload could not be processed" if e.status_code == 422

      error_hash :internal_server_error, "An unexpected error occurred while uploading the coverage report"
    rescue StandardError => e
      Failbot.report(e,
        catalog_service: "github/code_scanning",
        repository_id: repo.id,
        request_id: data[:request_id],
      )
      error_hash :internal_server_error, "An unexpected error occurred while uploading the coverage report"
    end
  end

  sig { params(code: Symbol, message: String).returns({ error: { code: Symbol, message: String } }) }
  def error_hash(code, message)
    { error: { code: code, message: message } }
  end
end
