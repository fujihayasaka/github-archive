# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeScanningUpload < Api::App
  include Api::App::CodeScanningHelpers
  include FeatureFlagHelper

  rate_limit_as Api::RateLimitConfiguration::CODE_SCANNING_UPLOAD_FAMILY

  # Handle a SARIF upload
  post "/repositories/:repository_id/code-scanning/sarifs", operation_id: "code-scanning/upload-sarif" do
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    data = receive_with_openapi
    pull = nil
    if current_integration&.launch_github_app? || current_integration&.launch_lab_github_app?
      pull = find_pull_request_from_ref(repo, data["ref"])
    end

    control_access :write_code_scanning,
      resource: pull || repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_write_message

    deliver_error_if_archived! repo

    # Normalize to commit_oid internally, and validate commit and ref for non pull requests
    data["commit_oid"] = data["commit_sha"]

    begin
      resp = upload_analysis(repo, data)
    rescue Exception => error # rubocop:todo Lint/GenericRescue
      deliver_error! 500, message: error.message if Rails.env.development?
      raise error
    end

    deliver_error_from_response!(resp) if resp.key? :error

    # On success, build the proper response
    deliver :code_scanning_receipt_hash, { id: resp[:id] }, repo: repo, status: 202
  end

  # Handle a SARIF upload (Actions Only)
  put "/repositories/:repository_id/code-scanning/analysis", operation_id: :internal do
    @route_owner = "@github/code-scanning-experiences-eng"
    repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }
    # This endpoint is only exposed when reached from Actions because the old PR
    # from forks flow allowed upload with a read token. There doesn't seem to
    # be any reason to expose it publicly as customers should use the
    # `.../sarifs` endpoint. This method expects multiple parameters that are
    # fairly Actions-specific.
    deliver_error!(404) unless current_integration&.launch_github_app? || current_integration&.launch_lab_github_app?
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    data = receive_with_schema("code-scanning-analysis", "upload-analysis")
    pull = find_pull_request_from_ref(repo, data["ref"])

    control_access :write_code_scanning,
                    resource: pull || repo,
                    allow_integrations: true,
                    allow_user_via_granular_actor: false,
                    forbid: true

    deliver_error_if_archived! repo

    resp = upload_analysis(repo, data)
    deliver_error_from_response!(resp) if resp.key? :error

    deliver_raw resp, status: 202
  end

  private

  def deliver_error_from_response!(turboscan_response)
    status = if turboscan_response.dig(:error, :code) == :too_large
      413
    else
      400
    end
    payload = { msg: turboscan_response.dig(:error, :message) }
    halt deliver_raw payload, status: status
  end

  # Add required metadata to the request and forward it to turboscan
  def upload_analysis(repo, data)
    repo.code_scanning_active!

    data = data.with_indifferent_access
    data[:sarif_id] = SimpleUUID::UUID.new.to_guid.to_s
    data[:track_status] = repo.default_branch == data[:ref].delete_prefix("refs/heads/")
    data[:upload_started_at] = @request_start_time || Time.now
    data[:request_id] = GitHub.context[:request_id]
    data[:analysis_key] ||= "(default)"

    GitHub.logger.info(
      "code.namespace": "Api::RepositoryCodeScanningUpload",
      "code.function": "upload_analysis",
      "gh.request_id": data[:request_id],
      "git.ref": data[:ref],
      "git.commit.oid": data[:commit_oid],
    )

    begin
      analyzed_commit = Repositories.domain.commits.by_oid(repository: repo, commit_oid: data["commit_oid"])
      deliver_error!(404, message: "commit not found") if analyzed_commit.nil?
    rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
      deliver_error!(404, message: "commit not found")
    end

    data["head_commit_oid"] = if analyzed_commit.merge_commit?
      analyzed_commit.parent_oids[1]
    else
      analyzed_commit.oid
    end

    sarif = T.must(begin
      use_jsonschema = ActiveModel::Type::Boolean.new.cast(data.delete(:validate)) || repo.feature_enabled?(:code_scanning_validate_sarif)
      GitHub::Turboscan.validate_sarif(repo, data.delete(:sarif), use_jsonschema:)
    rescue GitHub::Turboscan::GzipTooLargeError
      GitHub::Turboscan.delivery_zip_too_big_error(repo, data, max: GitHub::Turboscan::UPLOAD_MAX_SIZE)
      return error_hash :too_large, "Gzipped SARIF file is too large"
    rescue GitHub::Turboscan::NoSarifToolsError
      GitHub::Turboscan.delivery_invalid_sarif_error(repo, data, message: "Invalid SARIF document: Empty sarif file provided.")
      return error_hash :bad_request, "Invalid SARIF document: No valid runs found."
    rescue ::Sarif::EmptyError
      GitHub::Turboscan.delivery_invalid_zip_error(repo, data, is_empty: true)
      return error_hash :bad_request, "Empty gzip provided. Expected Base64 encoded gzip'd SARIF file."
    rescue ::Sarif::LimitError
      GitHub::Turboscan.delivery_sarif_too_big_error(repo, data, max: GitHub::Turboscan::SARIF_MAX_SIZE)
      return error_hash :too_large, "Invalid SARIF document: Decompressed document exceeds #{ActiveSupport::NumberHelper.number_to_human_size(GitHub::Turboscan::SARIF_MAX_SIZE)}."
    rescue ::Sarif::ReadError
      GitHub::Turboscan.delivery_invalid_zip_error(repo, data, is_empty: false)
      return error_hash :bad_request, "Could not decode SARIF content. Expected Base64 encoded gzip'd file."
    rescue ::Sarif::Error => e
      GitHub::Turboscan.delivery_invalid_sarif_error(repo, data, message: "Invalid SARIF document: #{e.message}")
      return error_hash :bad_request, "Invalid SARIF document: #{e.message}" unless e.message.nil?
    end)

    # Store the source repository in the data payload by looking it up in the PR object
    pull_request_ref_matcher = data[:ref]&.match(/\Arefs\/pull\/([0-9]+)\/(head|merge)\Z/)
    if pull_request_ref_matcher
      pr_number = pull_request_ref_matcher[1]
      ref_type = pull_request_ref_matcher[2]
      pull_request = PullRequest.with_number_and_repo(pr_number, repo)

      deliver_error!(404, message: "ref is a pull request that could not be found") unless pull_request

      source_repository = pull_request.head_repository
      deliver_error!(422, message: "source repository for pull request could not be determined") unless source_repository

      data[:source_repository_id] = source_repository.id
      # Prevent spammy users from triggering alerts on forked repos
      deliver_error!(404, message: "Forked repository is flagged as Spammy") if source_repository.spammy? && source_repository.fork?

      # If the base_ref and/or base_sha are not provided by the uploader, we
      # take a guess. These values could be out of date if they have changed
      # since the workflow run that performed the analysis started.
      data[:base_ref] ||= "refs/heads/#{pull_request.base_ref_name}"

      if ref_type == "merge"
        # If this is a pull request merge commit, we still want to post annotations on the head commit or they won't show up on the pull request page.
        deliver_error!(400, message: "ref is a pull request merge but commit_oid is not a merge commit") if analyzed_commit.parent_oids.length != 2
        annotated_commit_oid = analyzed_commit.parent_oids[1]

        # We prefer the base_sha that we've been sent as it would be a bit
        # strange to ignore. However, note that as this is a merge commit, we
        # know that the first parent is the perfect SHA to compare against. We
        # can review this decision if we see it having strange effects.
        data[:base_sha] ||= analyzed_commit.parent_oids[0]
      else
        annotated_commit_oid = data["commit_oid"]
        data[:base_sha] ||= pull_request.base_sha
      end

      code_scanning_check_suite = CheckRun.create_code_scanning_check_suite(
        repository: repo,
        annotated_commit_oid: annotated_commit_oid,
        analyzed_commit_oid: data["commit_oid"],
        ref: data[:ref],
        base_ref: data[:base_ref],
        base_sha: data[:base_sha],
      )

      deliver_error!(404, message: "check suite not found") if code_scanning_check_suite.nil?

      check_runs = CheckRun.create_code_scanning_check_runs(
        check_suite: code_scanning_check_suite.check_suite,
        tool_names: sarif.tool_names
      )
    else
      ref = repo.refs.find(data["ref"])&.qualified_name
      if ref.nil?
        deliver_error!(404, message: "ref '#{data["ref"]}' not found in this repository")
      else
        data["ref"] = ref
      end

      # Analyses for refs that are not under `refs/pull/*` are normally for a branch under
      # `/refs/heads/*` and triggered by `on: push` or a schedule. As such there
      # might not be a PR to associate an Alert Diff with and no need for check runs
      # to display a Diff. In that case we do not create any check runs.
      data[:source_repository_id] = repo.id
      check_runs = []

      # However, if a PR for that ref does exist, we create check runs and make use of the analysis
      # Note that this logic is duplicated in the CodeScanningProcessedAnalysis stream processor to
      # guard against race conditions. If you change it here it should also be updated there.
      pull_request = PullRequest.find_open_based_on_head_ref(repo.id, data[:ref])&.find { |pr| pr.repository_id == repo.id && !pr.spammy? }
      if pull_request.present? && pull_request.base_ref != data[:ref].delete_prefix("refs/heads/") && pull_request.head_sha == data["commit_oid"]
        code_scanning_check_suite = CheckRun.create_code_scanning_check_suite(
          repository: repo,
          annotated_commit_oid: data["commit_oid"],
          analyzed_commit_oid: data["commit_oid"],
          ref: data[:ref],
          base_ref: "refs/heads/#{pull_request.base_ref}",
          base_sha: pull_request.base_sha,
        )

        deliver_error!(404, message: "check suite not found") if code_scanning_check_suite.nil?

        check_runs = CheckRun.create_code_scanning_check_runs(
          check_suite: code_scanning_check_suite.check_suite,
          tool_names: sarif.tool_names
        )
      end
    end

    # Add some diagnostic data
    # Note: We use symbols (rather than strings) for data injected by the API
    data[:check_run_ids] = check_runs.map(&:id)
    data[:upload_finished_at] = Time.now

    resp = GitHub::Turboscan.upload_analysis(repo, data, sarif)

    if resp.key? :error
      # We failed to send the request to Turboscan.
      # This is either an S3 error or a conversion error.
      # Set the check_run as failed
      check_runs.each { |c| c.update(conclusion: "failure") }
    end

    # Return the response from Turboscan directly
    resp
  end

  sig { params(code: Symbol, message: String).returns({ error: { code: Symbol, message: String } }) }
  private def error_hash(code, message)
    { error: { code: code, message: message } }
  end
end
