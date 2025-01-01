# typed: true
# frozen_string_literal: true

module Integration::RepositoriesDependency
  DEFAULT_PERMISSION = "metadata"
  PER_PAGE = 100
  BATCH_SIZE = 1_000

  extend T::Helpers

  requires_ancestor { Integration }

  # Public: Given an array of repository ids return
  # the list of repositories we actually have access to as
  # an Integration.
  #
  #  current_integration_installation: An installation record that can be used to further limit the result.
  #  repository_ids:                   An array of repository ids.
  #  permissions:                      An array of granular repository permissions.
  #  owner_ids:                        An array of owner ids
  #
  # Returns an Array of repository ids.
  def accessible_repository_ids(current_integration_installation:, repository_ids: [], permissions: Repository::Resources.subject_types, owner_ids: [])
    repository_ids = repository_ids.uniq
    GitHub.dogstats.distribution("integration.accessible_repository_ids.count", repository_ids.size)

    GitHub.dogstats.time("integration.accessible_repository_ids.time") do
      return [] unless repository_ids.present?

      if current_integration_installation
        return [] unless current_integration_installation.integration_id == self.id
        return [] if current_integration_installation.suspended?

        current_permissions = Repository::Resources.filter(current_integration_installation.permissions).keys
        return [] unless (current_permissions & permissions).any?

        return repository_ids & current_integration_installation.repository_ids
      end

      # Global apps have access to all repositories if it requires
      # repository permissions.
      if Apps::Privileged.capable?(:installed_globally, app: self)
        # Ensure that the global app has at least one
        # of the permissions that are requested.
        return [] unless (latest_version.permissions_of_type(Repository).keys & permissions).any?
        repo_ids = if repository_ids.size > (BATCH_SIZE * 2)
          Repository.batched_scope(:id, values: repository_ids, batch_size: BATCH_SIZE).pluck(:id)
        else
          Repository.where(id: repository_ids).pluck(:id)
        end
        return repo_ids
      end

      owner_ids = if owner_ids.present?
        owner_ids.uniq
      elsif repository_ids.size > (BATCH_SIZE * 2)
        Repository.batched_scope(:id, values: repository_ids, batch_size: BATCH_SIZE).execute do |scope|
          scope.distinct(:owner_id).async_pluck(:owner_id)
        end.flat_map(&:value).uniq
      else
        Repository.where(id: repository_ids).select(:owner_id).distinct.pluck(:owner_id)
      end

      installation_ids = Authorization.service.actor_ids_with_granular_permissions_on(
        actor_type:   "IntegrationInstallation",
        subject_type: "Repository",
        subject_ids:  repository_ids,
        owner_ids:    owner_ids,
        permissions:  permissions,
      )

      relation = IntegrationInstallation.not_suspended.where(id: installation_ids).where(integration: self)
      resource = Array(permissions).find { |p| p == DEFAULT_PERMISSION }

      promise = Platform::Loaders::ActiveRecord.load_relation(relation).then do |installations|
        Promise.all(
          installations.map do |installation|
            installation.async_target.then do
              installation.repository_ids(
                repository_ids: repository_ids,
                resource: resource
              )
            end
          end,
        )
      end

      (promise.then(&:flatten).sync).sort
    end
  end

  def accessible_repository_ids_by_owner(current_integration_installation:, owner_and_repo_ids: {}, resource: nil)
    return [] if owner_and_repo_ids.empty?

    permissions = resource.nil? ? Repository::Resources.subject_types : [resource]

    owner_ids = owner_and_repo_ids.keys
    repository_ids = owner_and_repo_ids.values.flatten.uniq

    if current_integration_installation
      return accessible_repository_ids(current_integration_installation:, repository_ids:, permissions:, owner_ids:)
    end

    # Global apps have access to all repositories if it requires
    # repository permissions.
    if Apps::Privileged.capable?(:installed_globally, app: self)
      return accessible_repository_ids(current_integration_installation:, repository_ids:, permissions:, owner_ids:)
    end

    relation = IntegrationInstallation.not_suspended.where(integration: self).with_target_id_type(owner_ids, "User")

    promise = Platform::Loaders::ActiveRecord.load_relation(relation).then do |installations|
      Promise.all(
        installations.map do |installation|
          installation.async_target.then do
            filterable_repository_ids = owner_and_repo_ids[installation.target_id]
            next [] if filterable_repository_ids.empty?

            options = {}

            if resource.present?
              options[:resource] = resource
            end

            if filterable_repository_ids.size > (BATCH_SIZE * 2)
              filterable_repository_ids & installation.repository_ids(**options)
            else
              options[:repository_ids] = filterable_repository_ids
              installation.repository_ids(**options)
            end
          end
        end
      )
    end

    (promise.then(&:flatten).sync).sort
  end

  # Public: Repository ids owned by target account that the given actor can
  # install integrations on.
  #
  #   target: the target of the installation, must be an Organization
  #   actor: the User requesting installation.
  #   exclude_installed: exclude the repositories already on the installation (default true).
  #
  # Returns an Array.
  def installable_repository_ids_on_by(target:, actor:, exclude_installed: true)
    return [] unless actor&.user?
    return [] if target.is_a?(Business)
    return [] if target.user? && actor != target

    actor_can_install_on_all_repositories = installable_on_all_repositories_by?(target: target, actor: actor)
    target_repository_ids = Repositories::Public.active_owned_by(target.id).pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))

    repository_ids = if actor_can_install_on_all_repositories
      target_repository_ids
    else
      actor.associated_repository_ids(min_action: :admin, repository_ids: target_repository_ids)
    end

    if exclude_installed && (installation = installations.with_user(target).first)
      if installation.repository_selection == "selected"
        repository_ids -= installation.repository_ids
      end
    end

    workspace_repo_ids = RepositoryAdvisory.where(owner_id: target.id).pluck(:workspace_repository_id)

    repository_ids -= workspace_repo_ids

    if actor_can_install_on_all_repositories || installable_on_by?(target: target, actor: actor, repository_ids: repository_ids)
      repository_ids
    else
      []
    end
  end

  # Public: Repository ids owned by target account that the given actor can
  # request integration installation on.
  #
  #   target: the target of the installation, must be an Organization
  #   actor: the User requesting installation.
  #   exclude_requested: exclude the repositories already on the installation (default true).
  #
  # Returns an Array.
  def requestable_repository_ids_on_by(target:, actor:, exclude_requested: true)
    return [] if target.is_a?(Business) || target.user?
    return [] unless actor&.user?

    check = requestable_on_by(target: target, actor: actor)
    return [] unless check.permitted?

    if actor.feature_enabled?(:requestable_repository_ids_on_by_with_internal_repos)
      new_requestable_repository_ids_on_by(target:, actor:, exclude_requested:, check: check)
    else
      old_requestable_repository_ids_on_by(target:, actor:, exclude_requested:)
    end
  end

  def old_requestable_repository_ids_on_by(target:, actor:, exclude_requested:)
    repository_ids = actor.associated_repository_ids(repository_ids: Repository.active.where(owner_id: target.id).pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id")))
    repository_ids -= installable_repository_ids_on_by(target: target, actor: actor)
    repository_ids |= target.repositories.public_scope.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id")) if target.member?(actor)

    if exclude_requested && (installation = installations.with_user(target).first)
      repository_ids -= installation.repository_ids
    end

    repository_ids
  end

  def new_requestable_repository_ids_on_by(target:, actor:, exclude_requested:, check:)
    repository_ids =
      case check.reason
      when :organization_member
        page = 1

        # This collects all repositories that the organization member has access
        # to no matter the visibility.
        boma_args = {
          organization: target,
          user: actor,
          pagination: GH::Pagination::Offset.new(per_page: PER_PAGE, page: page),
          permission: Repositories::PlatformPermissionSwitch.new(nil, override: true),
        }

        collection = Repositories.domain.by_org_member(
          Repositories::ByOrgMemberArgs.new(boma_args)
        )

        repo_ids = collection.map(&:id)

        # Auto paginate over the entire collection to gather all of the results.
        while collection.count == PER_PAGE do
          page += 1
          boma_args[:pagination] = GH::Pagination::Offset.new(per_page: PER_PAGE, page: page)

          collection = Repositories.domain.by_org_member(
            Repositories::ByOrgMemberArgs.new(boma_args)
          )

          repo_ids.concat(collection.map(&:id))
        end

        repo_ids
      when :outside_collaborator
        # This only collects repositories the actor has direct access on.
        # The `affiliations` KWARG doesn't actually do anything on
        # `#by_org_member` otherwise we'd have used that.
        target.collaborating_repository_ids_for([actor.id]).map(&:last)
      else
        # This there is a case we don't know how to handle, just fail closed.
        []
      end

    return repository_ids if repository_ids.empty?

    repository_ids -= installable_repository_ids_on_by(target: target, actor: actor)

    if exclude_requested && (installation = installations.with_target(target).first)
      repository_ids -= installation.repository_ids
    end

    repository_ids
  end
end
