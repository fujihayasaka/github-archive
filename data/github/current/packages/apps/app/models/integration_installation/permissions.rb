# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  class Permissions
    include Scientist

    BATCH_SIZE = 1_000

    attr_reader :installation, :actor, :action, :options

    class Result
      attr_reader :actor, :target, :action, :result, :reason

      def self.for(check, result:, reason: nil)
        new(check.actor, check.target, check.action, result, reason: reason)
      end

      DEFAULT_REASON = "You do not have permission to %{action} this app on %{target}."

      HUMAN_READABLE_REASONS = {
        requires_org_permissions: "You cannot %{action} apps with organization permissions on %{target}.",
        not_admin_on_subset: "You do not have permission to %{action} this app on %{target}.",
        not_owned_by_target: "Repositories must be owned by %{target}.",
        target_not_organization: "You cannot %{action} apps installed on other user accounts.",
        transfer_in_progress: "You cannot add a repository that is being transferred.",
        missing_verified_email: "You must verify your email to install this app",
        suspended_by_staff: "This installation has been blocked by GitHub. Please reach out to support for more details.",
        already_suspended: "This installation has already been suspended.",
        too_many_repositories_to_add: "You are only permitted to add #{Integration::InstallationService::DEFAULT_MAX_REPOS} repositories at a time.",
        too_many_repositories_to_remove: "You are only permitted to remove #{Integration::InstallationService::DEFAULT_MAX_REPOS} repositories at a time.",
        unknown_actor_type: "Installations may only be modified by known types of actors."
      }.freeze

      def initialize(actor, target, action, result, reason:)
        @actor, @target, @action = actor, target, action
        @result, @reason = result, reason
      end

      def permitted?
        @result
      end

      def error_message
        full_reason = HUMAN_READABLE_REASONS.fetch(reason, DEFAULT_REASON)
        full_reason = full_reason + CONTACT_ORGANIZATION_OWNER_MESSAGE if target.organization?

        I18n.interpolate(full_reason, { action: "modify", target: target.display_login })
      end
    end

    def self.check(installation:, actor:, action:, **options)
      new(installation, actor, action, options).check
    end

    def initialize(installation, actor, action, options = {})
      @installation = installation
      @actor        = actor
      @action       = action
      @options      = options

      @skip_installed_on_target_check = options.fetch(:skip_installed_on_target_check, false)
    end

    def check
      case action
      when :admin
        can_admin
      when :update_permissions
        can_update_permissions
      when :install_all_repositories
        can_install_all_repositories
      when :view
        can_view_installation
      when :add_repositories
        can_add(@options[:repositories])
      when :add_repositories_from_api
        can_add_from_api(@options[:repositories])
      when :remove_repositories
        can_remove(@options[:repositories])
      when :uninstall
        can_uninstall
      when :auto_upgrade
        can_auto_upgrade(@options[:version])
      when :suspend
        can_suspend
      when :unsuspend
        can_unsuspend
      when :configure_access_to_repository
        can_configure_access_to(@options[:repository])
      else
        result(false, :action_invalid)
      end
    end

    def target
      installation.target
    end

    def integration
      installation.integration
    end

    private

    # Private: Can the given actor perform any action
    # on the IntegrationInstallation.
    #
    # Returns a Result
    def can_admin
      return result(true, :is_admin) if target.adminable_by?(actor)

      result(false, :not_adminable_by)
    end

    def can_update_permissions
      # Ensure that the version belongs to this integration.
      version = @options[:version]
      return result(false, :missing_version) if version.nil?
      return result(false, :incorrect_version) unless version.integration_id == installation.integration_id

      admin_result = can_admin
      return admin_result if admin_result.permitted?

      return result(false, :target_not_organization) unless target.is_a?(Organization)
      return result(false, :not_adminable_by) if version.default_permissions.none?

      differ = IntegrationVersion::Differ.perform(
        old_version: installation.version, new_version: version
      )

      if differ.permissions_of_type(Organization, action: :added).any? || differ.permissions_of_type(Organization, action: :upgraded).any?
        return result(false, :requires_org_permissions)
      end

      if differ.permissions_of_type(User, action: :added).any?
        return result(false, :not_adminable_by)
      end

      can_admin_all_repositories_result = ensure_repositories_adminable(installation.repositories, actor)
      return can_admin_all_repositories_result unless can_admin_all_repositories_result.permitted?

      if differ.permissions_added.key?("administration") || differ.permissions_upgraded.key?("administration")
        action = differ.permissions_added["administration"] || differ.permissions_upgraded["administration"]

        # Because `administration` allows the creation of repositories
        # we need to ensure that non organization admins cannot
        # grant `:write` or above.
        #
        # See https://github.com/github/github/issues/107143
        if T.must(Ability.actions[action]) > T.must(Ability.actions[:read])
          return result(false, :not_adminable_by)
        end
      end

      result(true, :can_update)
    end

    # Private: Can the given actor view the IntegrationInstallation, either as an
    # owning admin or a repo admin on any of the repositories.
    #
    # If as an admin on a subset or repos, we only show the repos available.
    #
    # Returns a Result
    def can_view_installation
      admin_result = can_admin
      return admin_result if admin_result.permitted?

      integration_result = Integration::Permissions.check(
        integration: integration,
        actor:       actor,
        action:      :request_installation,
        target:      target,
      )

      result(integration_result.permitted?, integration_result.reason)
    end

    # Private: Can the given actor alter this to be an install on all repos.
    #
    # Returns a Result
    def can_install_all_repositories
      integration_result = Integration::Permissions.check(
        integration:          integration,
        actor:                actor,
        action:               :install,
        target:               target,
        repository_selection: Integration::Permissions::RepositorySelection::All,
        version:              installation.version,
      )

      result(integration_result.permitted?, integration_result.reason)
    end

    # Private: Can the given actor add the specified repositories to this
    # installation.
    #
    # Returns a Result
    def can_add(repositories = [])
      if integration.can_request_oauth_on_install? && actor.must_verify_email?
        return result(false, :missing_verified_email)
      end

      repositories_addable_result = ensure_repositories_can_be_added(repositories)
      return repositories_addable_result unless repositories_addable_result.permitted?

      case actor
      when Bot; result(true, :is_app_actor)
      when User; can_add_as_user(repositories, actor)
      else; result(false, :unknown_actor_type)
      end
    end

    # Private: Can the given actor add the specified repositories to this
    # installation after creating the repository via the API.
    #
    # Returns a Result
    def can_add_from_api(repositories = [])
      repositories_addable_result = ensure_repositories_can_be_added(repositories)
      return repositories_addable_result unless repositories_addable_result.permitted?

      if integration_installation_can_self_install?
        return result(true, :self_install)
      end

      case actor
      when Bot; result(true, :is_app_actor)
      when User; can_add_as_user(repositories, actor)
      else; result(false, :unknown_actor_type)
      end
    end

    # Private: Can the given actor remove the specified repositories from this
    # installation.
    #
    # Returns a Result
    def can_remove(repositories, skip_limit_check: false)
      track_repositories_size_metrics(repositories)

      repository_ownership_result = ensure_repository_ownership(repositories)
      return repository_ownership_result unless repository_ownership_result.permitted?

      requested_ids = repositories.map(&:id)
      repository_ids = installation.repository_ids
      return result(false, :not_installed) if (requested_ids - repository_ids).any?

      if !skip_limit_check && installation.target.feature_enabled?(:repo_subset_limit_for_installations)
        if requested_ids.count > Integration::InstallationService::DEFAULT_MAX_REPOS
          return result(false, :too_many_repositories_to_remove)
        end
      end

      return result(true, :is_admin) if can_admin.permitted?

      if app_actor?
        all_repositories_same_owner = repositories.all? { |repo| repo.owner_id == target.id }
        return result(false, :not_owned_by_target) unless all_repositories_same_owner

        result(true, :app_actor)
      else
        ensure_repositories_adminable(repositories, actor)
      end
    end

    # Private: Can the given actor remove the specified repositories from this
    # installation.
    #
    #  - Can remove if admin
    #  - Can remove if noora can admin all repos and there aren't any org permissions
    #
    # Returns a Result
    def can_uninstall
      return result(true) if can_admin.permitted?
      return result(false, :requires_org_permissions) if requires_organization_installation?

      can_remove(installation.repositories, skip_limit_check: true)
    end

    def can_auto_upgrade(new_version)
      return result(false, :missing_version)   unless new_version.present?
      return result(false, :incorrect_version) unless new_version.integration_id == installation.integration_id

      return result(true) if new_version.default_permissions.empty?
      return result(true) if Apps::Privileged.capable?(:auto_upgrade_permissions, app: installation.integration)

      diff   = new_version.diff(installation.version)
      target = installation.target

      unless target.is_a?(Business)
        return result(false, :single_file_name_changed) if diff.single_file_paths_added?
        return result(false, :content_references_added) if diff.content_references_added?
      end

      subject_types = case target
      when Business
        Business::Resources.subject_types
      when Organization
        (Repository::Resources.subject_types + Organization::Resources.subject_types)
      when User
        Repository::Resources.subject_types
      end

      return result(false, :permissions_added)    if permissions_part_of_subject_types?(diff.permissions_added, subject_types)
      return result(false, :permissions_upgraded) if permissions_part_of_subject_types?(diff.permissions_upgraded, subject_types)

      result(true)
    end

    def can_suspend
      return result(true) if actor.staff_user?
      return result(false, :already_suspended) if installation.user_suspended?

      can_admin
    end

    def can_unsuspend
      if installation.staff_suspended? && !actor.staff_user?
        return result(false, :suspended_by_staff)
      end

      can_admin
    end

    def can_configure_access_to(repository)
      # Can't configure repo access if we don't have access to repos.
      return result(false, :no_access_to_repositories) if Repository::Resources.filter(installation.get_cached_permissions).none?

      repository_ownership_result = ensure_repository_ownership([repository])
      return repository_ownership_result unless repository_ownership_result.permitted?

      if RepositoryAdvisory.where(workspace_repository_id: repository.id).exists?
        return result(false, :advisory_workspace_repo_included)
      end

      # Admins rule everything.
      admin_result = can_admin
      return admin_result if admin_result.permitted?

      # Only organizations allow outside collaborators or members to configure
      # repository access.
      return result(false, :target_not_organization) unless target.organization?

      # If the installation is on "all repos" only admins can configure the
      # installation's repository access
      return result(false, :installed_on_all_repositories) if installation.installed_on_all_repositories?

      # Allow org members to configure access on this repository if they can at
      # least see the repository. They may or may not have direct access.
      if target.member?(actor)
        return result(true, :organization_member) if repository.readable_by?(actor)
        return result(false, :repository_not_accessible)
      end

      # Orgs can disable installation requests from outside collaborators
      if target.denies_third_party_access_requests_from_outside_collaborators?
        return result(false, :installation_requests_disabled)
      end

      if Authorization.service.direct_ability_between(actor: actor, subject: repository)
        return result(true, :outside_collaborator)
      end

      result(false, :not_part_of_organization)
    end

    # Private: do the referenced permissions require organization approval
    #
    # Returns a Boolean
    def requires_organization_installation?(permissions = nil)
      permissions ||= @installation.permissions
      Organization::Resources.subject_types.any? { |type| permissions.include?(type) }
    end

    def result(value, reason = nil)
      Result.for(self, result: value, reason: reason)
    end

    # does the user have admin ability over all the repositories
    def ensure_repositories_adminable(repositories, actor)
      if all_repositories_adminable?(repositories, actor)
        result(true, :admin_on_selected_repos)
      else
        result(false, :not_admin_on_subset)
      end
    end

    def all_repositories_adminable?(repositories, actor)
      # direct admin abilities on repo
      direct_admin_repo_ids = Authorization.service.most_capable_collaborator_abilities_from_actor(
        actor:        actor,
        subject_type: Repository,
        subject_ids:  repositories.map(&:id),
        min_action: :admin,
      ).pluck(:subject_id)

      # they have an explicit admin ability on all the provided repos
      return true if direct_admin_repo_ids.count == repositories.count

      # do they have admin on all the owning orgs of the remaining repos?
      direct_admin_repos = Repository.where(id: direct_admin_repo_ids)
      remaining_repos = repositories - direct_admin_repos

      repo_owning_org_ids = remaining_repos.map(&:owning_organization_id).uniq
      org_admin_abilities = Ability.user_admin_on_organization(
        actor_id: actor.id,
        subject_id: repo_owning_org_ids,
      )

      org_admin_abilities.count == repo_owning_org_ids.count
    end

    def repos_include_advisory_workspace?(repositories)
      repositories.map(&:id).in_groups_of(BATCH_SIZE, false).any? do |repo_ids|
        RepositoryAdvisory.where(workspace_repository_id: repo_ids).exists?
      end
    end

    def ensure_repository_ownership(repositories)
      return result(false, :no_repositories_submitted) unless repositories.present?
      return result(false, :not_owned_by_target) unless repositories.all? { |repository| repository.owner_id == target.id }

      result(true)
    end

    def ensure_no_transfers_in_progress(repositories)
      return result(true) if Apps::Privileged.capable?(:follow_repository_transfers, app: integration)
      repositories.any?(&:transfer_in_progress?) ? result(false, :transfer_in_progress) : result(true)
    end

    def permissions_part_of_subject_types?(permissions, subject_types)
      (permissions.keys & subject_types).any?
    end

    def integration_installation_can_self_install?
      return false unless actor.is_a?(IntegrationInstallation)
      return false unless actor.target == target

      args = {
        priority: Ability.priorities[:direct],
        action: Ability.actions[:write],
        actor_id: actor.ability_id,
        actor_type: actor.ability_type,
        subject_type: Repository.new.resources.administration.ability_type,
      }

      sql = Arel.sql <<-SQL, **args
        SELECT 1
        FROM permissions
        WHERE priority = :priority
        AND actor_id = :actor_id
        AND actor_type = :actor_type
        AND subject_type = :subject_type
        AND action IN (:action)
        LIMIT 1
      SQL

      Permission.connection.select_value(sql).present?
    end

    def ensure_repositories_can_be_added(repositories)
      track_repositories_size_metrics(repositories)

      if installation.target.feature_enabled?(:repo_subset_limit_for_installations)
        if repositories.is_a?(Array) && repositories.count > Integration::InstallationService::DEFAULT_MAX_REPOS
          return result(false, :too_many_repositories_to_add)
        end
      end

      repository_ownership_result = ensure_repository_ownership(repositories)
      return repository_ownership_result unless repository_ownership_result.permitted?

      repository_transfer_result = ensure_no_transfers_in_progress(repositories)
      return repository_transfer_result unless repository_transfer_result.permitted?

      unless @skip_installed_on_target_check
        if installation.repository_ids(repository_ids: repositories.map(&:id)).any?
          return result(false, :already_installed)
        end
      end

      if repos_include_advisory_workspace?(repositories)
        unless Apps::Privileged.capable?(:can_install_on_security_advisory_repos, app: integration)
          return result(false, :advisory_workspace_repo_included)
        end
      end

      result(true)
    end

    def can_add_as_user(repositories, actor)
      return result(true, :is_admin) if can_admin.permitted?
      ensure_repositories_adminable(repositories, actor)
    end

    def track_repositories_size_metrics(repositories)
      return unless repositories && repositories.count > 0

      GitHub.dogstats.distribution(
        "integration_installation.permissions.repositories.size",
        repositories.count,
        tags: { action: action }
      )
    end

    def app_actor?
      actor.is_a?(Bot)
    end
  end
end
