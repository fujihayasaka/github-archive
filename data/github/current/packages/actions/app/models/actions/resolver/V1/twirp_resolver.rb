# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotAllowNameWithOwner
# rubocop:disable GitHub/DoNotAllowLogin
# Disabled cops since this is an internal API and these cops are disabled for internal API endpoints.

# Supports resolving action repositories only.
# This will be removed once the `resolve_immutable_actions` feature has been rolled out for all customers.
class Actions::Resolver::V1::TwirpResolver

  sig { params(workflow_repo: Repository, workflow_run_id: Integer, job_id: String, should_instrument_request: T::Boolean).void }
  def initialize(workflow_repo:, workflow_run_id:, job_id:, should_instrument_request:)
    @workflow_repo = workflow_repo
    @workflow_run_id = workflow_run_id
    @job_id = job_id
    @should_instrument_request = should_instrument_request
    @metric_tags = ["resolver:twirp_v1", "connect:false"]
    @repository_resolver = Actions::Resolver::Internal::RepositoryResolver.new(
      metric_namespace: "api_twirp",
      metric_tags: @metric_tags,
      workflow_repo: @workflow_repo,
    )
    @deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)
  end

  sig { params(actions: T::Array[MonolithTwirp::Actions::Core::V1::Action]).returns(T::Hash[Symbol, T.untyped]) }
  def resolve(actions)
    # NWOs are case-insensitive. Normalize to lowercase.
    actions = actions.each do |action|
      action.nwo = action.nwo.downcase # rubocop:disable GitHub/DoNotAllowNameWithOwner
    end

    resolved_actions_response = resolve_action_repositories(actions)

    {
      resolved_actions: resolved_actions_response
    }
  end

  private

  def resolve_action_repositories(actions)
    GitHub.dogstats.increment(
      "resolve_action_repositories.batch_resolve.count",
      tags: @metric_tags)

    resolved_actions_response = []
    GitHub.dogstats.time("resolve_action_repositories.batch_resolve.duration", tags: @metric_tags) do
      actions.each do |action|
        resolved_actions_response << resolve_action_repository(action: action)
      end
    end

    resolved_actions_response
  end

  # Changes the org names in enterprise instances where the
  # GitHub.actions_org or GitHub.github_org overrides the default values
  sig { params(repo_nwo: String).returns(T.nilable(String)) }
  def process_action_name(repo_nwo)
    return nil unless GitHub.enterprise?
    return nil unless (GitHub.actions_org && GitHub.actions_org != "actions".freeze) ||
      (GitHub.github_org && GitHub.github_org != "github".freeze)

    if [GitHub.actions_org, GitHub.github_org].compact.size == 1
      raise StandardError, "Both GitHub.actions_org and GitHub.github_org must be set if one of them is set"
    end

    split_nwo = repo_nwo.split("/")
    org = split_nwo[0]
    org = GitHub.actions_org if org == "actions".freeze
    org = GitHub.github_org if org == "github".freeze
    "#{org}/#{split_nwo[1]}"
  end

  # Resolve one action repository.
  sig do
    params(action: MonolithTwirp::Actions::Core::V1::Action).returns(T::Hash[Symbol, T.untyped])
  end
  def resolve_action_repository(action:)
    original_action_nwo = action.nwo
    processed_action_nwo = process_action_name(original_action_nwo)
    resolved_action_nwo = processed_action_nwo || original_action_nwo

    repo = resolve_repository(resolved_action_nwo)
    unless repo.present?
      GitHub.dogstats.increment(
        "api_twirp.actions.resolve_action",
        tags: ["error:repo_not_found"].concat(@metric_tags)
      )

      GitHub.logger.warn(
        "Unable to find action repository",
        "code.namespace": "Actions::Resolver::V1::TwirpResolver",
        "code.function": "resolve_action_repository",
        "gh.action.requested_nwo": original_action_nwo,
        "gh.action.resolved_nwo": resolved_action_nwo
      )

      return error_response(code: 404, message: "Unable to resolve action #{original_action_nwo}, repository not found")
    end

    if repo_disabled_or_blocked?(repo)
      GitHub.dogstats.increment(
        "api_twirp.actions.resolve_action",
        tags: ["error:repo_access_blocked"].concat(@metric_tags)
      )

      GitHub.logger.warn(
        "Unable to access disabled or blocked action repository",
        "code.namespace": "Actions::Resolver::V1::TwirpResolver",
        "code.function": "resolve_action_repository",
        "gh.action.requested_nwo": original_action_nwo,
        "gh.action.resolved_nwo": resolved_action_nwo,
        "gh.repo.name_with_owner": repo.name_with_owner
      )

      return error_response(code: 403, message: "Repository access blocked")
    end

    # if enabled v1 and v2 of artifacts/upload-artifact and artifacts/download-artifact will be blocked
    # GHES onbox resolution is not blocked
    if @deprecated_actions_filter.action_blocked?(requested_nwo: original_action_nwo, ref: action.ref)
      msg = @deprecated_actions_filter.error_for_blocked_actions(original_action_nwo, action.ref)
      GitHub.dogstats.increment(
        "api_twirp.actions.resolve_action",
        tags: ["error:blocked_action", "origin:local"].concat(@metric_tags) # local origin is either dotcom or Proxima
      )
      return error_response(code: 422, message: msg)
    end

    if @deprecated_actions_filter.action_deprecated?(requested_nwo: original_action_nwo, ref: action.ref)
      msg = @deprecated_actions_filter.warning_for_deprecating_actions(original_action_nwo, action.ref)
      GitHub.dogstats.increment(
        "api_twirp.actions.resolve_action",
        tags: ["warning:deprecated_action"].concat(@metric_tags)
      )
      CreateActionsAnnotationsJob.perform_later(repo_id: @workflow_repo.id, workflow_run_id: @workflow_run_id, job_id: @job_id, message: msg, warning_level: "warning")
    end

    res = @repository_resolver.resolve(
      repo: repo,
      requested_nwo: original_action_nwo,
      processed_nwo: processed_action_nwo,
      ref: action.ref)

    if res.is_a?(Actions::Resolver::Internal::Error)
      error_response(code: 400, message: res.msg)
    else
      resolved_action = T.cast(res, Actions::Resolver::Internal::ResolvedAction)
      instrument_resolve_request(repo, resolved_action.ref, resolved_action.resolved_sha) if @should_instrument_request

      resolved_action.to_twirp_response
    end
  end

  # This is done to support repo redirects for resolving
  # public actions.
  def resolve_repository(repo_nwo)
    repo = Repository.nwo(repo_nwo)
    return repo unless repo.nil?

    RepositoryRedirect.find_redirected_repository(repo_nwo)
  end

  def repo_disabled_or_blocked?(repo)
    repo.access.disabled? || repo.network_broken? || repo.disabled?
  end

  def error_response(code:, message:)
    {
      error: {
        error_code: code,
        error_message: message
      }
    }
  end

  def instrument_resolve_request(repo, ref, sha)
    return if GitHub.enterprise?

    payload = {
      resolved_repository: repo,
      ref: ref,
      resolved_ref: ref,
      resolved_sha: sha,
      connect_request: false,
    }.tap do |hash|
      hash[:user] = @workflow_repo.owner if @workflow_repo.owner&.user? || @workflow_repo.owner&.organization?
      hash[:workflow_run_id] = @workflow_run_id
      hash[:job_id] = @job_id
      hash[:workflow_repository_id] = @workflow_repo.id
      hash[:action_nwo] = repo.name_with_owner
    end

    GlobalInstrumenter.instrument("actions.resolve_actions_request", payload)
  end
end
