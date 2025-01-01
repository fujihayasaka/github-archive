# typed: true
# frozen_string_literal: true

class Actions::Resolver::V2::TwirpResolver

  sig { params(workflow_repo: Repository, workflow_run_id: Integer, job_id: String, should_instrument_request: T::Boolean, is_hosted_runner: T::Boolean).void }
  def initialize(workflow_repo:, workflow_run_id:, job_id:, should_instrument_request:, is_hosted_runner:)
    @workflow_repo = workflow_repo
    @workflow_run_id = workflow_run_id
    @job_id = job_id
    @should_instrument_request = should_instrument_request

    @metric_tags = ["resolver:twirp_v2", "connect:false", "is_hosted_runner:#{is_hosted_runner}"]
    @repository_resolver = Actions::Resolver::Internal::RepositoryResolver.new(
      metric_namespace: "api_twirp",
      metric_tags: @metric_tags,
      workflow_repo: @workflow_repo
    )
    @package_resolver = Actions::Resolver::V2::Internal::PackageResolver.new(
      metric_namespace: "api_twirp",
      metric_tags: @metric_tags,
      actor_id: workflow_repo.id,
      actor_type: "repository",
      workflow_repo: workflow_repo)
    @actions_classifier = Actions::Resolver::V2::Internal::ActionsClassifier.new(
      metric_namespace: "api_twirp",
      metric_tags: @metric_tags,
      workflow_repo: @workflow_repo)
    @deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: false, proxima_fallback_request: false)
  end

  sig { params(actions: T::Array[MonolithTwirp::Actions::Core::V1::Action]).returns(T::Hash[Symbol, T.untyped]) }
  def resolve(actions)
    # NWOs are case-insensitive. Normalize to lowercase.
    actions = actions.each do |action|
      action.nwo = action.nwo.downcase # rubocop:disable GitHub/DoNotAllowNameWithOwner
    end

    resolved_actions_response = resolve_actions(actions)

    {
      resolved_actions: resolved_actions_response
    }
  end

  private

  # Supports resolving action repositories and action packages.
  def resolve_actions(actions)
    GitHub.dogstats.increment(
      "resolve_actions.batch_resolve.count",
      tags: @metric_tags)

    GitHub.dogstats.time("resolve_actions.batch_resolve.duration", tags: @metric_tags) do
      unordered_resolved_actions = {}

      input_actions = actions.map do |a|
        original_action_nwo = a.nwo # rubocop:disable GitHub/DoNotAllowNameWithOwner
        processed_action_nwo = process_action_name(original_action_nwo)
        Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
          requested_nwo: original_action_nwo,
          processed_nwo: processed_action_nwo,
          ref: a.ref)
      end

      collection = @actions_classifier.classify(input_actions)

      # Resolve all repository actions
      collection.repository_actions.each do |action|
        unordered_resolved_actions["#{action.requested_nwo}@#{action.ref}"] = resolve_action_repository(action: action)
      end

      # Add an error for each unservable semver action
      collection.unservable_actions.each do |action|
        GitHub.dogstats.increment(
          "api_twirp.actions.resolve_action",
          tags: ["error:#{action.error}", "origin:local"].concat(@metric_tags) # local origin is either dotcom or Proxima
        )

        GitHub.logger.warn(
          "Unable to resolve action package",
          "code.namespace": "Actions::Resolver::V2::TwirpResolver",
          "code.function": "resolve_actions",
          "gh.action.requested_nwo": action.requested_nwo,
          "gh.action.resolved_nwo": action.resolved_nwo,
          "gh.action.ref": action.ref,
          "gh.action.normalised_semver": action.normalised_semver,
          "gh.action.error": action.error
        )

        msg = "Unable to resolve action #{action.requested_nwo}@#{action.ref}, action not found"
        # WARNING TO FUTURE DEVS: Do not expose the error message to the user.
        # These are the only error cases that are safe to expose to the user.
        # Exposing any other error could leak information about the existence of private actions.
        # Please think very hard before changing this. If in doubt, ask the Security team for an audit.
        if action.error == :version_not_found
          msg = "Unable to resolve action #{action.requested_nwo}@#{action.ref}, package version not found"
        elsif action.error == :blocked_action
          msg = @deprecated_actions_filter.error_for_blocked_actions(action.requested_nwo, action.ref)
        end

        unordered_resolved_actions["#{action.requested_nwo}@#{action.ref}"] = error_response(code: 422, message: msg)
      end

      # Resolve all package actions
      package_actions = collection.package_actions
      if package_actions.any?
        @package_resolver.resolve(actions: package_actions).each do |res|
          if res.is_a?(Actions::Resolver::Internal::Error)
            unordered_resolved_actions["#{res.requested_name}@#{res.ref}"] = error_response(code: 422, message: res.msg)
          else
            resolved_action = T.cast(res, Actions::Resolver::Internal::ResolvedAction)
            instrument_resolve_request_with_package(resolved_action) if @should_instrument_request

            unordered_resolved_actions["#{resolved_action.requested_name}@#{resolved_action.ref}"] = resolved_action.to_twirp_response
          end
        end
      end

      # Return the resolved actions in the same order as they were requested.
      input_actions.map do |action|
        if @deprecated_actions_filter.action_deprecated?(requested_nwo: action.requested_nwo, ref: action.ref)
          msg = @deprecated_actions_filter.warning_for_deprecating_actions(action.requested_nwo, action.ref)
          GitHub.dogstats.increment(
            "api_twirp.actions.resolve_action",
            tags: ["warning:deprecated_action"].concat(@metric_tags)
          )
          CreateActionsAnnotationsJob.perform_later(repo_id: @workflow_repo.id, workflow_run_id: @workflow_run_id, job_id: @job_id, message: msg, warning_level: "warning")
        end
        unordered_resolved_actions["#{action.requested_nwo}@#{action.ref}"]
      end
    end
  end

  # Resolve one action repository.
  sig do
    params(action: Actions::Resolver::V2::Internal::ActionsCollection::Action).returns(T::Hash[Symbol, T.untyped])
  end
  def resolve_action_repository(action:)
    repo = resolve_repository(action.resolved_nwo)
    unless repo.present?
      GitHub.dogstats.increment(
        "api_twirp.actions.resolve_action",
        tags: ["error:repo_not_found"].concat(@metric_tags)
      )

      GitHub.logger.warn(
        "Unable to find action repository",
        "code.namespace": "Actions::Resolver::V2::TwirpResolver",
        "code.function": "resolve_action_repository",
        "gh.action.requested_nwo": action.requested_nwo,
        "gh.action.resolved_nwo": action.resolved_nwo
      )

      return error_response(code: 404, message: "Unable to resolve action #{action.requested_nwo}@#{action.ref}, action not found")
    end

    if repo_disabled_or_blocked?(repo)
      GitHub.dogstats.increment(
        "api_twirp.actions.resolve_action",
        tags: ["error:repo_access_blocked"].concat(@metric_tags)
      )

      # Disabled cops since Actions team will communicate any change in requirements to disambiguate display and unique name_with_owner in future.
      GitHub.logger.warn(
        "Unable to access disabled or blocked action repository",
        "code.namespace": "Actions::Resolver::V2::TwirpResolver",
        "code.function": "resolve_action_repository",
        "gh.action.requested_nwo": action.requested_nwo,
        "gh.action.resolved_nwo": action.resolved_nwo,
        "gh.repo.name_with_owner": repo.name_with_owner # rubocop:disable GitHub/DoNotAllowNameWithOwner
      )

      return error_response(code: 403, message: "Repository access blocked")
    end

    res = @repository_resolver.resolve(
      repo: repo,
      requested_nwo: action.requested_nwo,
      processed_nwo: action.processed_nwo,
      ref: action.ref)

    if res.is_a?(Actions::Resolver::Internal::Error)
      error_response(code: 400, message: res.msg)
    else
      resolved_action = T.cast(res, Actions::Resolver::Internal::ResolvedAction)
      instrument_resolve_request_with_repository(repo, resolved_action.ref, resolved_action.resolved_sha) if @should_instrument_request

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

  sig { params(resolved_action: Actions::Resolver::Internal::ResolvedAction).void }
  def instrument_resolve_request_with_package(resolved_action)
    return if GitHub.enterprise?

    payload = {
      ref: resolved_action.ref,
      resolved_ref: resolved_action.resolved_ref,
      connect_request: false,
      package_id: resolved_action.package_id
    }.tap do |hash|
      # If there is a repo with this NWO, include it in the payload so that we
      # can include the resolve of the action package on the popularity counter of the repository.
      # This is *not* critical to guarantee the immutability of package actions
      # but a nice to have as it means a repository with many action package
      # downloads will still has its namespace retired,
      repo = Repository.with_name_with_owner(resolved_action.resolved_name)
      if repo
        hash[:resolved_repository] = repo
      end

      hash[:user] = @workflow_repo.owner if @workflow_repo.owner&.user? || @workflow_repo.owner&.organization?
      hash[:workflow_run_id] = @workflow_run_id
      hash[:job_id] = @job_id
      hash[:workflow_repository_id] = @workflow_repo.id
      hash[:action_nwo] = resolved_action.resolved_name
    end

    GlobalInstrumenter.instrument("actions.resolve_actions_request", payload)
  end

  def instrument_resolve_request_with_repository(repo, ref, sha)
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
      # Disabled cops since Actions team will communicate any change in requirements to disambiguate display and unique name_with_owner in future.
      hash[:action_nwo] = repo.name_with_owner # rubocop:disable GitHub/DoNotAllowNameWithOwner
    end

    GlobalInstrumenter.instrument("actions.resolve_actions_request", payload)
  end

  def error_response(code:, message:)
    {
      error: {
        error_code: code,
        error_message: message
      }
    }
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
    "#{org}/#{split_nwo[1]}" # rubocop:disable GitHub/DoNotAllowLogin
  end
end
