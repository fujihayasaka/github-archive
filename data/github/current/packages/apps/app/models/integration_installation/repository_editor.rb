# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  class RepositoryEditor
    include Scientist

    attr_reader :installation, :action, :repositories, :editor, :skip_callbacks, :entry_point
    alias_method :skip_callbacks?, :skip_callbacks

    DEFAULT_ERROR_MSG = "You do not have permission to modify this app on %s. Please contact an Organization Owner."

    class Result
      class Error < StandardError; end

      def self.success(installation) new(:success, installation: installation) end
      def self.failed(error) new(:failed, error: error) end

      attr_reader :error, :installation

      def initialize(status, installation: nil, error: nil)
        @status       = status
        @installation = installation
        @error        = error
      end

      def success?
        @status == :success
      end

      def failed?
        @status == :failed
      end
    end

    def self.perform(installation, action:, repositories:, editor:, skip_callbacks: false, entry_point:)
      new(installation, action, repositories, editor, skip_callbacks, entry_point).perform
    end

    def initialize(installation, action, repositories, editor, skip_callbacks = false, entry_point)
      @installation, @action = installation, action
      @repositories, @editor = Array(repositories), editor
      @skip_callbacks        = skip_callbacks
      @entry_point           = ::Permissions::Service::EntryPoint.lookup(entry_point)
    end

    def perform
      begin
        result = case action
        when :add
          add_repositories
        when :add_from_api
          add_repositories_from_api
        when :remove
          remove_repositories
        when :update
          update_repositories
        else
          Result.failed("Invalid action")
        end

        bust_cache
        after_updated_callbacks unless skip_callbacks? || result.failed?
        result
      rescue Result::Error => e
        Result.failed(e.message)
      end
    end

    def after_updated_callbacks
      return if installation.destroyed?

      UpdateIntegrationInstallationRateLimitJob.perform_later(installation.id)

      case action
      when :add
        instrument_repositories_added
      when :add_from_api
        instrument_repositories_added
      when :remove
        instrument_repositories_removed
      when :update
        instrument_repositories_added if repositories_to_add.any?
        instrument_repositories_removed if repositories_to_remove.any?
      end
    end

    private

    def add_repositories
      result = IntegrationInstallation::Permissions.check(
        installation: installation,
        actor:        editor,
        action:       :add_repositories,
        repositories: repositories,
      )

      if !result.permitted?
        GitHub.dogstats.increment("integration_installation.update", tags: ["result:failed", "type:repositories", "action:add"])
        raise Result::Error, result.error_message
      end

      ApplicationRecord::Permissions.transaction do
        install_on_repositories(repositories)

        unless GitHub.repository_transfer_requests_enabled?
          # To avoid a race condition around transferring repos and editing installations
          # on GHES we recheck repo ownership to make sure the repo transfer didn't occur after the initial check
          # https://github.com/github/ecosystem-apps/issues/4363
          result = IntegrationInstallation::Permissions.check(
            installation: installation,
            actor:        editor,
            action:       :add_repositories,
            repositories: repositories,
            skip_installed_on_target_check: true
          )
          if !result.permitted?
            GitHub.dogstats.increment("integration_installation.update", tags: ["result:failed", "type:repositories", "action:add"])
            raise Result::Error, result.error_message
          end
        end
      end

      GitHub.dogstats.increment("integration_installation.update", tags: ["result:success", "type:repositories", "action:add"])

      Result.success(installation)
    end

    def add_repositories_from_api
      result = IntegrationInstallation::Permissions.check(
        installation: installation,
        actor:        editor,
        action:       :add_repositories_from_api,
        repositories: repositories,
      )

      if !result.permitted?
        GitHub.dogstats.increment("integration_installation.update", tags: ["result:failed", "type:repositories", "action:add_repositories_from_api"])
        raise Result::Error, result.error_message
      end

      ApplicationRecord::Permissions.transaction do
        install_on_repositories(repositories)
      end

      GitHub.dogstats.increment("integration_installation.update", tags: ["result:success", "type:repositories", "action:add_repositories_from_api"])

      Result.success(installation)
    end

    def remove_repositories
      result = IntegrationInstallation::Permissions.check(
        installation: installation,
        actor:        editor,
        action:       :remove_repositories,
        repositories: repositories,
      )

      if !result.permitted?
        GitHub.dogstats.increment("integration_installation.update", tags: ["result:failed", "type:repositories", "action:remove"])
        raise Result::Error, result.error_message
      end

      repository_ids           = repositories.map(&:id)
      all_repositories_removed = (installation.repository_ids - repository_ids).empty?

      # Uninstall the app entirely if the editor is removing all of the repos
      if all_repositories_removed && Apps::Privileged.capable?(:auto_uninstall, app: installation.integration)
        GitHub.dogstats.increment("integration_installation.update", tags: ["result:success", "type:repositories", "action:update"])
        return Result.success(installation.uninstall(actor: editor))
      end

      ApplicationRecord::Permissions.transaction do
        uninstall_from_repositories(repository_ids)
      end

      SyncScopedIntegrationInstallationsJob.perform_later(
        installation,
        action: :repositories_removed,
        repository_ids: repository_ids,
        entry_point: entry_point.to_sym,
      )

      GitHub.dogstats.increment("integration_installation.update", tags: ["result:success", "type:repositories", "action:remove"])
      Result.success(installation)
    end

    def update_repositories
      if installation.installed_on_all_repositories?
        GitHub.dogstats.increment("integration_installation.update", tags: ["result:failed", "type:repositories", "action:update"])
        return Result.failed(DEFAULT_ERROR_MSG % installation.target.display_login)
      end

      # Cache the repositories to add and remove before modifying the installation
      repositories_to_add
      repositories_to_remove

      ApplicationRecord::Permissions.transaction do
        if repositories_to_add.any?
          @repositories = repositories_to_add
          add_repositories
        end

        if repositories_to_remove.any?
          @repositories = repositories_to_remove
          remove_repositories
        end
      end

      Result.success(installation)
    end

    def repositories_to_add
      @repositories_to_add ||= filter_addable_repositories(repositories)
    end

    def repositories_to_remove
      @repositories_to_remove ||= filter_removeable_repositories(repositories)
    end

    def filter_addable_repositories(repositories)
      return [] if repositories.empty?

      repository_ids           = repositories.map(&:id)
      installed_repository_ids = installation.repository_ids

      ids = repository_ids - installed_repository_ids

      return [] if ids.empty?

      ids &= editor.associated_repository_ids(min_action: :admin, repository_ids: Repository.owned_by(installation.target).ids)
      repositories.select { |repository| ids.include?(repository.id) }
    end

    def filter_removeable_repositories(repositories)
      repository_ids = installation.repository_ids - repositories.map(&:id)
      return [] if repository_ids.empty?

      repository_ids &= editor.associated_repository_ids(min_action: :admin, repository_ids: installation.repository_ids)

      if GitHub.flipper[:fully_load_removable_repositories_for_installation].enabled?
        installation.repositories.where(id: repository_ids)
      else
        installation.repositories.where(id: repository_ids).select(:id, :owner_id).to_a
      end
    end

    def install_on_repositories(repositories)
      rows = repositories.flat_map do |repository|
        repository_permissions.map do |resource, action|
          subject = repository.resources.public_send(resource)
          ::Permissions::Service.app_attributes(actor: installation, subject: subject, action: action)
        end
      end

      ::Permissions::Service.grant_permissions(rows, entry_point: entry_point)
    end

    def uninstall_from_repositories(repository_ids)
      return if repository_ids.empty?

      ::Permissions::Service.revoke_permissions_granted_on_subjects(
        actor_ids:     [installation.id],
        actor_type:    "IntegrationInstallation",
        subject_ids:   repository_ids,
        subject_types: Repository::Resources.individual_type_prefixed_subject_types,
        entry_point: entry_point,
      )

      # This removes permissions that were granted
      # such as access to protected branches.
      revoke_child_resources_for(repository_ids)
    end

    def instrument_repositories_added
      actor = case editor
      when IntegrationInstallation, ScopedIntegrationInstallation
        editor.bot
      else
        editor
      end

      installation.instrument_repositories_added(repositories.map(&:id), actor: actor, repository_selection: "selected")
    end

    def instrument_repositories_removed
      installation.instrument_repositories_removed(repositories.map(&:id), actor: editor)
    end

    def revoke_child_resources_for(repository_ids)
      revoke_protected_branch_access(repository_ids)
    end

    def revoke_protected_branch_access(repository_ids)
      ProtectedBranch.where(repository_id: repository_ids).in_batches do |relation|
        ::Permissions::Service.revoke_permissions_granted_on_subjects(
          actor_ids:     [installation.ability_id],
          actor_type:    installation.ability_type,
          subject_ids:   relation.pluck(:id),
          subject_types: ProtectedBranch::Resources.individual_type_prefixed_subject_types,
          entry_point: entry_point,
        )
      end
    end

    def repository_permissions
      return @repository_permissions if defined?(@repository_permissions)
      @repository_permissions = installation.version.permissions_of_type(Repository)

      if Apps::Privileged.capable?(:static_installation_repository_permissions, app: installation.integration)
        @repository_permissions = Apps::Privileged.property(:static_installation_repository_permissions, app: installation.integration)
      end

      @repository_permissions
    end

    def bust_cache
      # Update parent installation's updated_at to bust cache. Skip if installion was destroyed by action.
      # See: https://github.com/github/ecosystem-apps/issues/2730
      #
      # Note that this operation is busting the permissions cache and any scoped installation cache.
      installation.clear_cached_permissions unless installation.destroyed?
    end
  end
end
