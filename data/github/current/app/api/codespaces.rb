# typed: true
# frozen_string_literal: true

class Api::Codespaces < Api::App
  include Api::App::CodespacesDependency

  USER_NOT_AUTHORIZED_FOR_REGION = "User is not authorized to specify region. Did you mean geo?"
  USER_NOT_AUTHORIZED_FOR_VSCS_TARGET_MESSAGE = "User is not authorized to use vscs target"
  INVALID_VSCS_TARGET_MESSAGE = "Invalid vscs target"
  INVALID_LOCATION_FOR_VSCS_TARGET_MESSAGE = "Invalid location for vscs target"
  CODESPACE_USAGE_DISALLOWED_MESSAGE = "Usage of this codespace is currently disallowed"
  # Note that we're dependent on the 'machine type' in this error message for proper handling by the VS Code extension.
  MACHINE_TYPE_POLICY_VIOLATION_MESSAGE = "This codespace is currently using a machine type disallowed by your organization settings. Please update the codespace's machine type or export your changes to a branch."
  BASE_IMAGE_POLICY_VIOLATION_MESSAGE = "This codespace uses a dev container image disallowed by your organization settings. Please export your changes to a branch."
  MAX_PER_PAGE = 50

  private

  def with_aggressive_client_timeouts(&block)
    if GitHub.flipper[:codespaces_aggressive_client_timeouts].enabled?(current_user)
      Codespaces::Client.with_timeouts({ open_timeout: 2, timeout: 5 }, &block)
    else
      yield
    end
  end

  # If the user ends up getting rate limited by calls to a different service, codespace use
  # can be affected as it uses the public API. This rate limit is meant to shields us from that
  # and gives a limit we don't expect to hit. For Codespaces rate limiting intended to actually
  # prevent fraud, see Codespaces::RateLimitable
  def rate_limit_configuration
    Api::RateLimitConfiguration.for(
      Api::RateLimitConfiguration::CODESPACES_FAMILY,
      self,
    )
  end

  # Look up codespaces based on the given combination of owner, name, and guid,
  # filtering out codespaces that the current user cannot see.
  #
  # Note that `name` and `guid` are mutually exclusive.
  #
  # owner         - User the owner of the codespaces. Defaults to `current_user`.
  # actor         - User to use for permission checks. Defaults to `owner`.
  # name          - String the name of the codespace. Defaults to nil.
  # guid          - String the guid of the codespace. Defaults to nil.
  # repository_id - Integer the repository_id of the codespace. Defaults to nil.
  # filtering_resource - Symbol Represents the type of fine-grained permission that the actor must have on a repository in order for that repository to be  returned in the filtered list.
  # legacy_endpoint - Integer the repository_id of the codespace. Defaults to nil.
  # organization  - Organization the organization the codespaces belong to. Defaults to nil.
  # include_hidden  - Skip `visible_to` scope. Defaults to false.
  # include_copilot_workspace - skips filtering codespaces created from the copilot workspace technical preview. Defaults to false.

  def find_codespaces(owner: current_user, actor: owner, name: nil, guid: nil, repository_id: nil, filtering_resource: nil, legacy_endpoint: false, organization: nil, include_hidden: false, include_copilot_workspace: false)
    return [[], []] unless owner

    raise ArgumentError, "`name` and `guid` are mutually exclusive" if name && guid

    scope = owner.codespaces

    if !legacy_endpoint
      return [[], []] unless actor
      return [[], []] if anonymous_request?
      possible_repository_ids = if repository_id
        [repository_id]
      elsif organization
        owner.codespaces.select(:repository_id).for_organization(organization).distinct.pluck(:repository_id)
      else
        scope.pluck(:repository_id).uniq
      end

      # rubocop:disable Lint/UnusedBlockArgument
      repository_ids = ProgrammaticActor::RepositoryFilter.perform(
        actor: actor,
        repository_ids: possible_repository_ids,
        resource: filtering_resource,
        augmentation: -> (actor:, repository_ids:, resource:, accessible_repository_ids:) {
          if organization.present?
            # Add forks, but not forks of forks
            accessible_repository_ids + Repository.where(parent_id: accessible_repository_ids).distinct.pluck(:id)
          else
            accessible_repository_ids
          end
        }
      )
      # rubocop:enable Lint/UnusedBlockArgument
      scope = scope.where(repository_id: repository_ids.uniq)
    else
      if repository_id.present?
        scope = scope.where(repository_id: repository_id)
      end
    end

    scope = if name
      scope.where(name: name)
    elsif guid
      scope.where(guid: guid)
    else
      scope.order("id ASC")
    end

    codespaces = if include_hidden
      scope.preload([:owner, :billable_owner]).to_a
    else
      scope.preload([:owner, :billable_owner]).visible_to(owner, include_copilot_workspace: include_copilot_workspace).to_a
    end

    authorized_codespaces = cap_filter.authorized_resources(codespaces)
    removed_codespaces = codespaces.difference(authorized_codespaces)
    unauthorized_org_ids = removed_codespaces
      .map do |codespace|
        tfca = codespace.target_for_conditional_access
        tfca.organization? ? tfca.id : nil
      end
      .compact
      .uniq
    [authorized_codespaces, unauthorized_org_ids]
  end

  def find_codespace(**args)
    codespaces, _ = find_codespaces(**args)
    codespaces.first.tap do |cs|
      set_exception_context(cs) if cs
    end
  end

  def set_exception_context(codespace)
    ::Codespaces::ErrorReporter.push(codespace: codespace)
  end
end
