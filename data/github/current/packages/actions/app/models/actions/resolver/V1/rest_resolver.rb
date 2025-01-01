# typed: true
# frozen_string_literal: true

# Supports resolving action repositories only.
# This will be removed once the `resolve_immutable_actions` feature has been rolled out for all customers.
class Actions::Resolver::V1::RestResolver
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
    @repository_resolver = Actions::Resolver::Internal::RepositoryResolver.new(
      metric_namespace: "api",
      metric_tags: ["resolver:rest_v1", "connect:#{connect_request}"])

    @deprecated_actions_filter = Actions::Resolver::Internal::DeprecatedActionsFilter.new(workflow_repo: workflow_repo, connect_request: connect_request)
  end

  sig { params(original_action_name: T.nilable(String), ref: String).returns(T.any(Actions::Resolver::Success, Actions::Resolver::Error)) }
  def resolve(original_action_name:, ref:)
    res = if original_action_name
      # Presence of the original action name indicates that we *might* have processed the action name
      # Hence we use the repo as the processed name.

      # NWOs are case-insensitive. Normalize to lowercase.
      original_action_name = original_action_name.downcase

      if @deprecated_actions_filter.action_blocked?(requested_nwo: original_action_name, ref: ref)
        msg = @deprecated_actions_filter.error_for_blocked_actions(original_action_name, ref)
        return Actions::Resolver::Error.new(status: 422, msg: msg)
      end

      @repository_resolver.resolve(
        repo: @action_repo,
        requested_nwo: original_action_name,
        processed_nwo: @action_repo.name_with_display_owner,
        ref: ref)
    else
      if @deprecated_actions_filter.action_blocked?(requested_nwo: @action_repo.name_with_display_owner, ref: ref)
        msg = @deprecated_actions_filter.error_for_blocked_actions(@action_repo.name_with_display_owner, ref)
        return Actions::Resolver::Error.new(status: 422, msg: msg)
      end
      # Absence of the original action name indicates that *no* processing was done.
      # Hence we pass the repo as the request nwo and leave the processed one blank.
      @repository_resolver.resolve(
        repo: @action_repo,
        requested_nwo: @action_repo.name_with_display_owner,
        processed_nwo: nil,
        ref: ref)
    end

    if res.is_a?(Actions::Resolver::Internal::Error)
      Actions::Resolver::Error.new(status: 422, msg: res.msg)
    else
      resolved_action = T.cast(res, Actions::Resolver::Internal::ResolvedAction)
      instrument_connect_request(resolved_action.ref)
      instrument_resolve_request(resolved_action.ref, resolved_action.resolved_sha)

      Actions::Resolver::Success.new(status: 200, body: resolved_action.to_rest_response)
    end
  end

  private

  def instrument_connect_request(ref)
    return unless @connect_request
    return if GitHub.enterprise?

    GlobalInstrumenter.instrument("actions.connect_resolve_request", {
      enterprise_installation: @current_enterprise_installation,
      resolved_repository: @action_repo,
      ref: ref,
    })
  end

  def instrument_resolve_request(ref, resolved_sha)
    return if GitHub.enterprise?

    payload = {
      resolved_repository: @action_repo,
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
        hash[:action_nwo] = @action_repo.name_with_owner # rubocop:disable GitHub/DoNotAllowNameWithOwner
      end
    end

    GlobalInstrumenter.instrument("actions.resolve_actions_request", payload)
  end
end
