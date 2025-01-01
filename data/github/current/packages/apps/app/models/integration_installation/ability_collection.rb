# typed: true
# frozen_string_literal: true

class IntegrationInstallation::AbilityCollection < Ability::Collection
  INSTRUMENT_PERMISSION_CHECKS = defined?(Rails) ? Rails.env.test? : false

  attr_reader :ability_type_prefix

  # Internal: Used by Abilities to ensure that only IntegrationInstallations
  # can be granted abilities on a Collection
  def grant?(actor, action)
    actor.can_have_granular_permissions?
  end

  # Public: access control on the collection
  #
  # actor: - The User to check permission for.
  # action - The Symbol action representing the level of permission to check for.
  #
  # Returns true or false.
  def permit?(actor, action)
    async_permit?(actor, action).sync
  end

  def async_permit?(actor, action)
    with_instrumentation_in_test_env(actor, action) do
      # TODO: this String condition can be removed once this codespace bug is resolved
      # https://github.com/github/codespaces/issues/15587
      result = if parent.resources.authzd_enabled?(action, @name) && !action.is_a?(String)
        async_has_authzd_permission?(actor: actor, action: action)
      else
        async_context_allows_access?(actor: actor, action: action).then do |result|
          result && async_has_coarse_grained_permission?(actor: actor, action: action).then do |result|
            result || async_has_indirect_permission?(actor: actor, action: action).then do |result|
              result || async_has_granular_permission?(actor: actor, action: action)
            end
          end
        end
      end
    end
  end

  private

  # Does the actor have access according to the Authzd service?
  def async_has_authzd_permission?(actor:, action:)
    return Promise.resolve(false) unless parent.is_a?(Repository) && ([:read, :write].include?(action))

    case action
    when :read; parent.async_can_read_resource?(actor, @name)
    when :write; parent.async_can_write_resource?(actor, @name)
    end
  end

  def async_context_allows_access?(actor:, action:)
    actor_context = actor.access_context if actor.respond_to?(:access_context)
    return Promise.resolve(true) unless actor_context

    async_has_granular_permission?(actor: actor_context, action: action).then do |result|
      result || async_has_coarse_grained_permission?(actor: actor_context, action: action)
    end
  end

  # Does the actor have access via the parent Repository?
  def async_has_coarse_grained_permission?(actor:, action:)
    case parent
    when Codespace
      parent.async_permit?(actor, action)
    when PullRequest
      case @name
      when "sarifs"
        parent.async_repository.then do |repository|
          repository.resources.pull_requests.async_permit?(actor, action)
        end
      else
        # It's not enough to have access to the Repository in order to
        # gain access to these resources. Further access is required.
        Promise.resolve(false)
      end
    when Repository
      case @name
      when "actions", "attestations", "checks", "contents", "content_references", "deployments",
           "discussions", "issues", "metadata", "packages", "pages", "pull_requests", "repository_projects",
           "single_file", "statuses", "workflows"

        # Access to the parent Repository will suffice to grant access to other resources.
        parent.async_permit?(actor, action)
      else
        # It's not enough to have access to the parent Repository in order to
        # gain access to these resources. Further access is required.
        Promise.resolve(false)
      end
    else
      # We don't grant access to resources by virtue of having access to the
      # parent for non-Repository parents.
      Promise.resolve(false)
    end
  end

  # Does the actor have access via a special role?
  def async_has_indirect_permission?(actor:, action:)
    return Promise.resolve(false) unless actor&.ability_delegate
    return Promise.resolve(false) if actor.ability_delegate.can_have_granular_permissions?

    case parent
    when Business
      case @name
      when "enterprise_administration"
        return parent.async_adminable_by?(actor)
      end
    when Organization
      if actor
        case @name
        when "members"
          # TODO Does this need to be async?
          return Promise.resolve(parent.direct_or_team_member?(actor))
        when "organization_projects"
          return parent.async_readable_by?(actor)
        when "organization_administration",
             "organization_hooks",
             "organization_pre_receive_hooks",
             "organization_user_blocking",
             "organization_plan",
             "organization_personal_access_tokens",
             "organization_personal_access_token_requests",
             "organization_codespaces_secrets",
             "organization_private_registries"
          return parent.async_adminable_by?(actor)
        when "organization_custom_org_roles"
          return parent.async_can_access_custom_org_roles?(actor, action)
        when "organization_custom_roles"
          return parent.async_can_access_custom_repo_roles?(actor, action)
        end
      end
    when Repository
      case @name
      when "administration", "repository_pre_receive_hooks"
        # These resources are granted access solely by the fact that the actor
        # in question is a repository admin, without consideration for whether
        # the actor has access to any other resource.
        return parent.async_adminable_by?(actor)
      when "repository_hooks"
        return parent.async_can_manage_webhooks?(actor)
      when "secret_scanning_alerts"
        unless action == :read || action == :write
          return SecurityProduct::Permissions::RepoAuthz.new(parent, actor:).async_can_manage_security_products?
        end

        fgp_action = action == :read ? :view_secret_scanning_alerts : :resolve_secret_scanning_alerts
        return parent.async_secret_scanning_check_fgp_permissions(actor, fgp_action)
      when "security_events"
        result =
          if action == :write
            parent.code_scanning_writable_by?(actor)
          else
            parent.code_scanning_readable_by?(actor)
          end
        return Promise.resolve(result)
      end
    end

    Promise.resolve(false)
  end

  # Does the actor have access via granular permission?
  def async_has_granular_permission?(actor:, action:)
    return Promise.resolve(false) unless actor&.ability_delegate&.can_have_granular_permissions?

    async_has_granular_permission_on_specific_resource?(actor: actor, action: action).then do |result|
      result || async_has_granular_permission_by_default?(actor: actor, action: action)
    end
  end

  # Does the actor have a granular permission on this resource?
  def async_has_granular_permission_on_specific_resource?(actor:, action:)
    # As of right now, GitHub Apps are not allowed access
    # in any way to advisory worspace repositories until we figure
    # out the best way forward.
    #
    # See https://github.com/github/pe-repos/issues/130 for more information.
    case parent
    when PullRequest, Actions::WorkflowRun
      parent.async_repository.then do |repository|
        if repository.advisory_workspace?
          return Promise.resolve(false)
        end
      end
    when Repository
      if parent.advisory_workspace? && !parent_repository_can_have_actions_on_private_forks?(parent)
        return Promise.resolve(false)
      end
    end

    ::Permissions::Service.async_can?(actor, action, self)
  end

  # Does the actor have access via granular permission via a default permission
  # across the entire account?
  def async_has_granular_permission_by_default?(actor:, action:)
    case parent
    when PullRequest
      parent.async_repository.then do |repository|
        !repository.advisory_workspace? && repository.async_owner.then do |owner|
          # See https://github.com/github/ecosystem-apps/issues/2323
          next false unless owner
          owner.repository_resources.pull_requests.async_permit?(actor, action)
        end
      end
    when Repository
      # As of right now, GitHub Apps are not allowed access
      # in any way to advisory worspace repositories until we figure
      # out the best way forward.
      #
      # See https://github.com/github/pe-repos/issues/130 for more information.
      return Promise.resolve(false) if parent.advisory_workspace?

      parent.async_owner.then do |owner|
        # See https://github.com/github/ecosystem-apps/issues/2323
        next false unless owner

        association_default = owner.repository_resources.send(@name)
        association_default.async_permit?(actor, action)
      end
    else
      Promise.resolve(false)
    end
  end

  def with_instrumentation_in_test_env(actor, action)
    if !INSTRUMENT_PERMISSION_CHECKS
      return yield
    end

    instrumentation_hash = {
      actor_type: actor.class.name,
      actor_id: actor&.id,
      action: action,
      permission: @name,
      resource_type: @parent.class.name,
      resource_id: @parent&.id
    }
    result = T.let(nil, T.nilable(T::Boolean))

    GitHub.instrument("integration_installation.permit?", instrumentation_hash) do |payload|
      result = yield

      payload[:result] = result
    end

    result
  end

  def parent_repository_can_have_actions_on_private_forks?(repository)
    repo = repository.parent_advisory&.repository
    return false unless repo

    repo.actions_enabled? &&
      repo.feature_enabled?(:maintainer_love_advisory_workspaces_can_use_actions)
  end
end
