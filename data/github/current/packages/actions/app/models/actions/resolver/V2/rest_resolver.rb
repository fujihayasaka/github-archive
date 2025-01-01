# typed: true
# frozen_string_literal: true

class Actions::Resolver::V2::RestResolver
  extend T::Sig

  sig { params(action_repo: Repository, workflow_repo: T.nilable(Repository), workflow_run_id: T.nilable(Integer), job_id: T.nilable(String), connect_request: T::Boolean, current_integration_installation: T.untyped, current_enterprise_installation: T.untyped).void }
  def initialize(action_repo:, workflow_repo:, workflow_run_id:, job_id:, connect_request:, current_integration_installation:, current_enterprise_installation:)
    @action_repo = action_repo
    @workflow_repo = workflow_repo
    @workflow_run_id = workflow_run_id
    @job_id = job_id
    @connect_request = connect_request
    @current_integration_installation = current_integration_installation
    @current_enterprise_installation = current_enterprise_installation

    metric_tags = ["resolver:rest_v2", "connect:#{connect_request}"]
    @repository_resolver = Actions::Resolver::Internal::RepositoryResolver.new(
      metric_namespace: "api",
      metric_tags: metric_tags)
    @package_resolver = Actions::Resolver::V2::Internal::PackageResolver.new(
      metric_namespace: "api",
      metric_tags: metric_tags,
      actor_id: 0,  # Since we don't have a workflow repository in GitHub Connect we pass a 0 here.
      actor_type: "connect") # Not a proper actor type but this field is used for logging only.
    @actions_classifier = Actions::Resolver::V2::Internal::ActionsClassifier.new(
      metric_namespace: "api",
      metric_tags: metric_tags,
      anonymous: true)

    @deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: connect_request)
  end

  sig { params(original_action_name: T.nilable(String), ref: String).returns(T.any(Actions::Resolver::Success, Actions::Resolver::Error)) }
  def resolve(original_action_name:, ref:)
    input_action = if original_action_name
      # Presence of the original action name indicates that we *might* have processed the action name
      # Hence we use the repo as the processed name.

      # NWOs are case-insensitive. Normalize to lowercase.
      original_action_name = original_action_name.downcase

      Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: original_action_name,
        processed_nwo: @action_repo.name_with_display_owner,
        ref: ref)
    else
      # Absence of the original action name indicates that *no* processing was done.
      # Hence we pass the repo as the request nwo and leave the processed one blank.
      Actions::Resolver::V2::Internal::ActionsCollection::Action.new(
        requested_nwo: @action_repo.name_with_display_owner,
        processed_nwo: nil,
        ref: ref)
    end

    collection = @actions_classifier.classify([input_action])

    if repository_action = collection.repository_actions.first
      # Resolve the Action from a Repository ref
      return resolve_action_repository(repository_action)
    elsif unservable_action = collection.unservable_actions.first
      # Return an error for the failed action

      GitHub.logger.warn(
        "Unable to resolve action package",
        "code.namespace": "Actions::Resolver::V2::RestResolver",
        "code.function": "resolve",
        "gh.action.requested_nwo": unservable_action.requested_nwo,
        "gh.action.resolved_nwo": unservable_action.resolved_nwo,
        "gh.action.ref": unservable_action.ref,
        "gh.action.normalised_semver": unservable_action.normalised_semver,
        "gh.action.error": unservable_action.error
      )

      msg = "Unable to resolve action #{unservable_action.requested_nwo}@#{unservable_action.ref}, action not found"

      # WARNING TO FUTURE DEVS: Do not expose the error message to the user.
      # This is the only error case that is safe to expose to the user.
      # Exposing any other error could leak information about the existence of private actions.
      # Please think very hard before changing this. If in doubt, ask the Security team for an audit.
      if unservable_action.error == :version_not_found
        msg = "Unable to resolve action #{unservable_action.requested_nwo}@#{unservable_action.ref}, package version not found"
      elsif unservable_action.error == :blocked_action
        msg = @deprecated_actions_filter.error_for_blocked_actions(unservable_action.requested_nwo, unservable_action.ref)
      end

      return Actions::Resolver::Error.new(status: 422, msg: msg)
    elsif package_action = collection.package_actions.first
      # Resolve the package action
      res = @package_resolver.resolve(actions: [package_action])[0]
      if res.is_a?(Actions::Resolver::Internal::Error)
        return Actions::Resolver::Error.new(status: 422, msg: res.msg)
      else
        resolved_action = T.cast(res, Actions::Resolver::Internal::ResolvedAction)

        instrument_resolve_request_with_package(resolved_action)
        return Actions::Resolver::Success.new(status: 200, body: resolved_action.to_rest_response)
      end
    end

    # Should never be reached!
    Actions::Resolver::Error.new(status: 500, msg: "Unable to resolve action #{input_action.requested_nwo}@#{input_action.ref}, action not found") # rubocop:disable GitHub/DoNotAllowNameWithOwner
  end

  private

  def resolve_action_repository(action)
    res = @repository_resolver.resolve(
      repo: @action_repo,
      requested_nwo: action.requested_nwo,
      processed_nwo: action.processed_nwo,
      ref: action.ref)

    if res.is_a?(Actions::Resolver::Internal::Error)
      Actions::Resolver::Error.new(status: 422, msg: res.msg)
    else
      resolved_action = T.cast(res, Actions::Resolver::Internal::ResolvedAction)
      instrument_connect_request(@action_repo, resolved_action.ref)
      instrument_resolve_request_with_repository(@action_repo, resolved_action.ref, resolved_action.resolved_sha)

      Actions::Resolver::Success.new(status: 200, body: resolved_action.to_rest_response)
    end
  end

  def instrument_connect_request(repo, ref)
    return unless @connect_request
    return if GitHub.enterprise?

    GlobalInstrumenter.instrument("actions.connect_resolve_request", {
      enterprise_installation: @current_enterprise_installation,
      resolved_repository: repo,
      ref: ref,
    })
  end

  sig { params(resolved_action: Actions::Resolver::Internal::ResolvedAction).void }
  def instrument_resolve_request_with_package(resolved_action)
    return if GitHub.enterprise?

    # We also include the repo with the matching NWO in the payload so that we
    # can include the resolve of the action package on the popularity counter of the repository.
    # This is *not* critical to guarantee the immutability of package actions
    # but a nice to have as it means a repository with many action package
    # downloads will still has its namespace retired,
    payload = {
      resolved_repository: @action_repo,
      ref: resolved_action.ref,
      resolved_ref: resolved_action.resolved_ref,
      connect_request: @connect_request,
      package_id: resolved_action.package_id
    }.tap do |hash|
      if @connect_request
        hash[:enterprise_installation] = @current_enterprise_installation
      elsif @current_integration_installation&.target.present?
        owner = @current_integration_installation.target
        hash[:user] = owner if owner.user? || owner.organization?
        hash[:workflow_run_id] = @workflow_run_id
        hash[:job_id] = @job_id
        hash[:workflow_repository_id] = @workflow_repo&.id || 0
        hash[:action_nwo] = resolved_action.resolved_name
      end
    end

    GlobalInstrumenter.instrument("actions.resolve_actions_request", payload)
  end

  def instrument_resolve_request_with_repository(repo, ref, resolved_sha)
    return if GitHub.enterprise?

    payload = {
      resolved_repository: repo,
      ref: ref,
      resolved_ref: ref,
      resolved_sha: resolved_sha,
      connect_request: @connect_request,
    }.tap do |hash|
      if @connect_request
        hash[:enterprise_installation] = @current_enterprise_installation
      elsif @current_integration_installation&.target.present?
        owner = @current_integration_installation.target
        hash[:user] = owner if owner.user? || owner.organization?
        hash[:workflow_run_id] = @workflow_run_id
        hash[:job_id] = @job_id
        hash[:workflow_repository_id] = @workflow_repo&.id || 0
        # Disabled cops since Actions team will communicate any change in requirements to disambiguate display and unique name_with_owner in future.
        hash[:action_nwo] = repo.name_with_owner # rubocop:disable GitHub/DoNotAllowNameWithOwner
      end
    end

    GlobalInstrumenter.instrument("actions.resolve_actions_request", payload)
  end
end
