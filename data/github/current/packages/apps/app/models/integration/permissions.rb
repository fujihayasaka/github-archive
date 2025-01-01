# typed: strict
# frozen_string_literal: true

class Integration
  class Permissions
    include GitHub::Memoizer

    sig { returns(User) }
    attr_reader :actor

    sig { returns(Symbol) }
    attr_reader :action

    sig { returns(T.any(Business, Organization, User)) }
    attr_reader :target

    PERMITTED_ACTIONS = T.let(%i[install request_installation].freeze, T::Array[Symbol])
    REPO_ADMIN_PROHIBITED_INSTALLATION_REPOSITORY_RESOURCES = T.let(%w[administration].freeze, T::Array[String])

    ORGANIZATION_INSTALLATION_REQUIRED_RESOURCES = \
      T.let(Organization::Resources.subject_types + REPO_ADMIN_PROHIBITED_INSTALLATION_REPOSITORY_RESOURCES, T::Array[String])

    BATCH_SIZE = 1_000

    sig do
      params(
        integration: Integration,
        actor: T.any(User, Bot),
        action: Symbol,
        target: T.any(Business, Organization, User),
        version: T.nilable(IntegrationVersion),
        repository_selection: T.nilable(RepositorySelection),
        repository_ids: T.nilable(T::Array[Integer]),
      ).returns(Result)
    end
    def self.check(integration:, actor:, action:, target:, version: nil, repository_selection: nil, repository_ids: nil)
      new(
        integration: integration,
        actor: actor,
        action: action,
        target: target,
        version: version,
        repository_selection: repository_selection,
        repository_ids: repository_ids
      ).check
    end

    sig do
      params(
        integration: Integration,
        actor: T.any(User, Bot),
        action: Symbol,
        target: T.any(Business, Organization, User),
        version: T.nilable(IntegrationVersion),
        repository_selection: T.nilable(RepositorySelection),
        repository_ids: T.nilable(T::Array[Integer]),
      ).void
    end
    def initialize(integration:, actor:, action:, target:, version: nil, repository_selection: nil, repository_ids: nil)
      @integration = integration
      @actor       = actor
      @action      = action
      @target      = target
      @version     = version

      @repository_ids = T.let((repository_ids || []), T::Array[Integer])
      @repository_selection = T.let((repository_selection || RepositorySelection::Any), RepositorySelection)
    end

    sig { returns(Integration::Permissions::Result) }
    def check
      GitHub.dogstats.distribution_time("integrations.permission_check.#{@action}") do
        case @action
        when :install
          can_install?
        when :request_installation
          can_request_installation?
        else
          result(false, :invalid_action)
        end
      end
    end

    private

    sig { returns(Integration::Permissions::Result) }
    def can_install?
      return result(false, :attribution_only_system_identity) if Apps::Privileged.capable?(:attribution_only_system_identity, app: @integration)
      return result(false, :suspended) if @integration.suspended?
      return result(false, :spammy_target) if @target.spammy?
      return result(false, :spammy_actor)  if @actor.spammy?

      if @integration.verified_email_required?(@actor)
        return result(false, :missing_verified_email) unless installing_via_app?
      end

      # Cannot install an Integration on target that it transforming.
      if (@target.is_a?(User) || @target.is_a?(Organization)) && Organization.transforming?(@target)
        return result(false, :target_transforming_into_org)
      end

      # Cannot install an Integration on another target if it is private.
      return result(false, :not_installable_on) unless @integration.installable_on?(@target)

      # An IntegrationVersion owned by the @integration is required
      # for checking permissions.
      return result(false, :missing_version) if @version.nil?
      return result(false, :invalid_version) if @version.integration_id != @integration.id

      # We only need to evaluate the provided repository ids if the app will
      # grant access to repos.
      if @repository_selection == RepositorySelection::Subset && @repository_ids.any? && has_repository_permissions?
        GitHub.dogstats.distribution "integration.permissions.repositories.size", @repository_ids.size

        if GitHub.flipper[:repo_subset_limit_for_installations].enabled?(@target)
          return result(false, :too_many_repositories) if @repository_ids.count > Integration::InstallationService::DEFAULT_MAX_REPOS
        end

        return result(false, :not_owned_by_target) unless target_owns_all_repository_ids?(@repository_ids)
        return result(false, :advisory_workspace_repo_included) if repository_ids_include_advisory_workspace?(@repository_ids)
      end

      if @target.is_a?(Business)
        return result(false, :missing_required_feature_flag) if @actor.is_a?(Bot) && !@target.feature_enabled?(:enterprise_app_installation_management)
        return result(false, :requires_enterprise_permissions) unless @version.any_permissions_of_type?(Business) || @integration.connect_app?

        return result(true, :admin_of_business) if @target.adminable_by?(actor) || @actor.is_a?(Bot)

        return result(false, :not_admin_on_target)
      end

      # Any app can be installed by an admin.
      return result(true, :is_admin) if @target.adminable_by?(@actor)

      if installing_via_app?
        return result(false, :not_business_org) unless @target.business
        # Fetch the integration that is authenticated rather than @integration
        bot = T.cast(@actor, Bot)
        integration = T.must(bot.integration)

        unless integration.installed_on?(@target.business)
          return result(false, :not_installed_on_enterprise)
        end

        case @repository_selection
        when RepositorySelection::All
          # Install on all repositories is allowed for apps.
          return result(true, :all_repositories)
        when RepositorySelection::Subset
          if @repository_ids.any?
            # Enusre that target owns all requested repos.
            return result(true, :not_owned_by_target) if target_owns_all_repository_ids?(@repository_ids)
          end
        end

        return result(false, :not_admin_on_all_repos)
      end

      # We only allow orgs to be installed on by a non admin.
      return result(false, :not_adminable) unless @target.is_a?(Organization)

      # Only admins can install permissionless apps.
      return result(false, :not_adminable) unless has_permissions?

      # Only org admins can install apps that are requesting org access or
      # the ability to administrate repositories.
      return result(false, :requires_org_permissions) if requires_organization_installation?

      # At this point the app is only asking for repository access without
      # administration.

      case @repository_selection
      when RepositorySelection::All
        # Only target admins can install on all repositories
        return result(false, :all_repositories)
      when RepositorySelection::Subset
        if @repository_ids.any?
          # An actor can only install apps on repos they admin.
          return result(false, :not_admin_on_subset) unless can_admin_all_repository_ids?(@repository_ids)
        end
      else
        # See if the actor can admin at least one repository owned by the target.
        return result(false, :not_admin_on_any_repos) unless can_admin_a_repo_on_target?
      end

      result(true)
    end

    sig { returns(Integration::Permissions::Result) }
    def can_request_installation?
      # Cannot request an installation on a User target.
      return result(false, :not_an_organization) unless @target.is_a?(Organization)

      # Cannot install an Integration on another target if it is private.
      return result(false, :not_installable_on_target) unless @integration.installable_on?(@target)

      # Admins don't need to request an installation.
      return result(false, :is_admin) if @target.adminable_by?(@actor)

      # Organization members can request an installation
      return result(true, :organization_member)  if @target.member?(@actor)

      # Orgs can disable installation requests from outside collaborators
      return result(false, :installation_requests_disabled) if @target.denies_third_party_access_requests_from_outside_collaborators?

      # Otherwise, requests are allowed for collaborators
      return result(true, :outside_collaborator) if @target.user_is_outside_collaborator?(@actor.id)

      result(false, :not_part_of_organization)
    end

    sig { returns(T::Boolean) }
    def requires_organization_installation?
      (ORGANIZATION_INSTALLATION_REQUIRED_RESOURCES & T.must(@version).default_permissions.keys).any?
    end

    sig { params(repo_ids: T::Array[Integer]).returns(T::Boolean) }
    def target_owns_all_repository_ids?(repo_ids)
      !repo_ids.in_groups_of(batch_size_for(repo_ids), false).any? do |ids_group|
        Repository.where(id: ids_group).where("owner_id != ?", @target.id).exists?
      end
    end

    sig { params(repo_ids: T::Array[Integer]).returns(T::Boolean) }
    def can_admin_all_repository_ids?(repo_ids)
      adminable_repo_ids = @actor.associated_repository_ids(
        repository_ids: repo_ids, min_action: :admin, organization: @target
      )

      (repo_ids - adminable_repo_ids).empty?
    end

    sig { returns(T::Boolean) }
    def can_admin_a_repo_on_target?
      repo_ids = @actor.associated_repository_ids(
        min_action:             :admin,
        including:              [:direct, :indirect_via_membership],
        include_indirect_forks: false,
        include_oopfs:          false,
        organization:           @target
      )

      return false if repo_ids.none?

      # Filter out advisory repositories
      (repo_ids - workspace_repository_ids).any?
    end

    sig { params(repo_ids: T::Array[Integer]).returns(T::Boolean) }
    def repository_ids_include_advisory_workspace?(repo_ids)
      repo_ids.intersection(workspace_repository_ids).any?
    end

    sig { params(value: T::Boolean, reason: Symbol).returns(Integration::Permissions::Result) }
    def result(value, reason = :default)
      Integration::Permissions::Result.for(self, result: value, reason: reason)
    end

    sig { params(repo_ids: T::Array[Integer]).returns(Integer) }
    def batch_size_for(repo_ids)
      return BATCH_SIZE if repo_ids.size < BATCH_SIZE * 5
      BATCH_SIZE * 10
    end

    sig { returns(T::Boolean) }
    def has_repository_permissions?
      T.must(@version).permissions_of_type("Repository").any?
    end

    sig { returns(T::Boolean) }
    def has_permissions?
      T.must(@version).default_permissions.any?
    end

    sig { returns(T::Array[Integer]) }
    memoize def workspace_repository_ids
      RepositoryAdvisory.where(owner_id: @target.id).pluck(:workspace_repository_id)
    end

    sig { returns(T::Boolean) }
    def installing_via_app?
      @actor.is_a?(Bot)
    end
  end
end
