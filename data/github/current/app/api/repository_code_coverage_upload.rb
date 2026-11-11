# typed: true
# frozen_string_literal: true

require "github/turboquality"

class Api::RepositoryCodeCoverageUpload < Api::App
  include Api::App::CodeScanningHelpers
  include FeatureFlagHelper

  rate_limit_as Api::RateLimitConfiguration::CODE_SCANNING_UPLOAD_FAMILY

  # Handle a code coverage report upload for internal usage
  put "/repositories/:repository_id/code-coverage/report", operation_id: "code-coverage/upload-code-coverage-report", read_from_replicas: true do
    @route_owner = "@github/code-scanning-experiences-eng"
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    deliver_error!(404) unless code_coverage_upload_available?(repo)

    ensure_read_access!(repo, forbid: repo.public?)

    data = receive_with_openapi

    control_access :write_code_scanning,
                    resource: repo,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                    forbid: true,
                    forbid_message: code_scanning_forbid_write_message

    return deliver_empty(status: 200) unless CodeQuality.available?(repo)

    deliver_error_if_archived! repo

    validated_data = transform_data_for_upload!(repo: repo, data: data.with_indifferent_access)

    resp = upload_coverage(repo, validated_data)
    deliver_error_from_response!(resp) if resp&.key? :error

    deliver_empty(status: 200)
  end

  private

  sig { params(repo: Repository, data: T::Hash[T.any(Symbol, String), T.untyped]).returns(T::Hash[T.any(Symbol, String), T.untyped]) }
  def transform_data_for_upload!(repo:, data:)
    # The validation criteria for the ref and commit_oid are as follows:
    # - If a pull_request_number is provided and the pull request with that number exists
    # - If no pull_request_number is provided, the ref must be a valid reference in the repository.
    # - In all cases, commit_oid must identify an existing commit in the repository.
    ref = data[:ref]
    deliver_error!(400, message: "Ref is required") unless ref
    validate_language!(data[:language_name])
    if data[:pull_request_number]
      pull = PullRequest.with_number_and_repo(data.delete(:pull_request_number).to_i, repo)
      deliver_error!(400, message: "Provided pull_request_number is not valid") unless pull
      data[:base_branch_name] = pull.base_ref_name
      head_ref_obj = repo.refs.find(ref)
      deliver_error!(400, message: "Provided ref is not a valid reference") unless head_ref_obj
      head_ref = head_ref_obj.name
      deliver_error!(400, message: "Provided ref does not match the pull request's head ref") unless head_ref == pull.head_ref_name
      data[:branch_name] = pull.head_ref_name
      data[:pr_number] = pull.number
    else
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

    data
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

  def code_coverage_upload_available?(repo)
    owner = repo.owner
    return false unless owner&.organization?

    FeatureFlag.vexi.enabled?(:code_coverage_upload_api, owner, default: false)
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
      coverage_report_b64 = data.delete(:coverage_report).to_s
      Base64.strict_decode64(coverage_report_b64)
    rescue ArgumentError
      return error_hash :bad_request, "Invalid coverage report: Expected valid Base64 encoded content."
    end

    begin
      GitHub::Turboquality.upload_coverage_report(repo.id, data, coverage_report)
    rescue ::Azure::Core::Http::HTTPError => e
      return error_hash :too_large, "Coverage report is too large" if e.status_code == 413
      return error_hash :unprocessable, "Coverage report payload could not be processed" if e.status_code == 422

      error_hash :internal_server_error, "An unexpected error occurred while uploading the coverage report"
    rescue StandardError
      error_hash :internal_server_error, "An unexpected error occurred while uploading the coverage report"
    end
  end

  sig { params(code: Symbol, message: String).returns({ error: { code: Symbol, message: String } }) }
  def error_hash(code, message)
    { error: { code: code, message: message } }
  end
end
