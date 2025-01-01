# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  class Editor
    attr_reader :installation, :repositories, :target, :permissions,
                :editor, :pending_request, :skip_callbacks, :appending,
                :entry_point
    alias_method :skip_callbacks?, :skip_callbacks
    alias_method :appending?, :appending

    # Result from the IntegrationInstallation edit
    class Result
      class Error < StandardError
        attr_reader :reason
        def initialize(message, reason = nil)
          @reason = reason
          super(message)
        end
      end

      def self.success(installation) new(:success, installation: installation) end
      def self.failed(error, reason = nil) new(:failed, error: error, reason: reason) end

      attr_reader :error, :installation, :reason

      def initialize(status, installation: nil, error: nil, reason: nil)
        @status       = status
        @installation = installation
        @error        = error
        @reason       = reason
      end

      def success?
        @status == :success
      end

      def failed?
        @status == :failed
      end
    end

    # Public: Edit an integration's access to repositories
    #
    # integration     - The Integration being installed.
    # repositories:   - An Array of Repositories to include in the installation and uninstallation. (Optional.).
    # editor:         - The User performing the installation edit.
    # skip_callbacks  - skip calling callbacks after the installation is edited,
    #                   allowing the caller to trigger the callbacks as required.
    # entry_point:    - Object: The `self` of the code calling this method. Used
    #                   for instrumentation.
    # Returns an IntegrationInstallation::Editor::Result.
    def self.perform(
      installation,
      repositories: nil,
      editor:,
      pending_request: nil,
      performed_automatically: false,
      skip_callbacks: false,
      entry_point: nil
    )

      new(
        installation,
        repositories: repositories,
        editor: editor,
        pending_request: pending_request,
        performed_automatically: performed_automatically,
        skip_callbacks: skip_callbacks,
        entry_point: entry_point
      ).perform
    end

    def self.append(installation, repositories: nil, editor:, performed_automatically: false, skip_callbacks: false, entry_point: nil)
      new(
        installation,
        repositories: repositories,
        editor: editor,
        pending_request: nil,
        performed_automatically: performed_automatically,
        skip_callbacks: false,
        entry_point: entry_point,
        appending: true
      ).append
    end

    def initialize(
      installation,
      repositories:,
      editor: nil,
      pending_request: nil,
      performed_automatically: false,
      skip_callbacks: false,
      appending: false,
      entry_point:
    )
      @installation                   = installation
      @target                         = installation.target
      @repositories                   = repositories
      @editor                         = editor
      @pending_request                = pending_request
      @performed_automatically        = performed_automatically
      @skip_callbacks                 = skip_callbacks
      @appending                      = appending
      @entry_point                    = entry_point
      @original_repository_selection  = ActiveRecord::Base.connected_to(role: :reading) { installation.repository_selection }
    end

    def current_repositories
      @current_repositories ||= ActiveRecord::Base.connected_to(role: :reading) { installation.repositories }
    end

    def requesting_all_repositories?
      @repositories.blank?
    end

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def installed_on_target?
      @installed_on_target ||= installation.installed_on_all_repositories?
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    def perform
      current_repositories # cache current repositories before making changes.
      validate_editor_has_permission

      ApplicationRecord::Permissions.transaction do
        if requesting_all_repositories?
          install_on_all_repositories
        else
          # We need install before uninstalling to ensure
          # we don't interrupt access to the repositories.
          install_on_repositories
          uninstall_unused_repositories
        end
      end

      bust_and_set_cache

      GitHub.dogstats.increment("integration_installation.update", tags: ["result:success", "type:permissions"])
      after_updated_callbacks unless skip_callbacks?

      Result.success(installation)
    rescue Result::Error => e
      tags = ["result:failed", "type:permissions"]
      tags << "reason:#{e.reason}" if e.reason.present?
      GitHub.dogstats.increment("integration_installation.update", tags: tags)

      case e.reason
      # To not break existing flows, we are not raising this as an error to
      # customers.
      #
      # See https://github.com/github/ecosystem-apps/issues/6028
      when :all_to_all_repo_selection
        Result.success(installation)
      else
        Result.failed(e.message, e.reason)
      end
    end

    def append
      ActiveRecord::Base.connected_to(role: :reading) do
        return Result.success(installation) if installed_on_target? # This installation covers all repositories
        validate_editor_has_permission

        bust_cache

        ApplicationRecord::Permissions.transaction do
          install_on_repositories
        end

        GitHub.dogstats.increment("integration_installation.update", tags: ["result:success", "type:repositories"])
        after_updated_callbacks unless skip_callbacks?

        Result.success(installation)
      end
    rescue Result::Error => e
      tags = ["result:failed", "type:repositories"]
      tags << "reason:#{e.reason}" if e.reason.present?
      GitHub.dogstats.increment("integration_installation.update", tags: tags)
      Result.failed(e.message, e.reason)
    end

    def after_updated_callbacks
      instrument_installation_updated
      UpdateIntegrationInstallationRateLimitJob.perform_later(installation.id)
    end

    private

    def instrument_installation_updated
      if requesting_all_repositories?
        all_repository_ids = @target.associated_repository_ids(including: :owned, include_indirect_forks: false, include_oopfs: false)
        repository_ids_to_add = all_repository_ids - current_repositories.collect(&:id)
        installation.instrument_repositories_added(
          repository_ids_to_add,
          actor: editor, repository_selection: "all",
          performed_automatically: @performed_automatically
        )
      else
        installation.instrument_repositories_added(
          repositories_to_install.collect(&:id),
          actor: editor,
          repository_selection: "selected",
          requester_id: pending_request&.requester_id,
          performed_automatically: @performed_automatically
        )
        unless appending?
          installation.instrument_repositories_removed(repositories_to_remove.collect(&:id), actor: editor)
        end
      end
    end

    def bust_cache
      installation.clear_cached_permissions
    end

    def bust_and_set_cache
      bust_cache
      installation.set_cached_repository_selection
    end

    def validate_editor_has_permission
      # Subset of repositories -> installed on 'all' repositories.
      if requesting_all_repositories?
        raise Result::Error.new("Cannot change repository selection from 'all' to 'all'", :all_to_all_repo_selection) unless originally_granted_access_to_subset_of_repositories?

        result = IntegrationInstallation::Permissions.check(installation: installation,
                                                            actor:        editor,
                                                            action:      :install_all_repositories)

        return true if result.permitted?
        raise Result::Error.new(result.error_message, result.reason)
      end

      # Installed on 'all' repositories -> installed on a subset of repositories.
      if installed_on_target? && repositories_to_install.any?
        result = IntegrationInstallation::Permissions.check(installation: installation,
                                                            actor:        editor,
                                                            action:       :add_repositories,
                                                            repositories: repositories_to_install,
                                                            skip_installed_on_target_check: true)

        return true if result.permitted?
        raise Result::Error.new(result.error_message, result.reason)
      end

      # Updating the subset selection of repositories.
      added_repositories, removed_repositories = calculate_added_and_removed_repositories

      if added_repositories.empty? && removed_repositories.empty?
        result = IntegrationInstallation::Permissions.check(installation: installation,
                                                            actor:        editor,
                                                            action:      :install_all_repositories)

        return true if result.permitted?
        raise Result::Error.new(result.error_message, result.reason)
      end

      result = if added_repositories.any?
        IntegrationInstallation::Permissions.check(installation: installation,
                                                   actor:        editor,
                                                   action:       :add_repositories,
                                                   repositories: added_repositories)

      end

      if result.nil? || (result.permitted? && removed_repositories.any?)
        result = IntegrationInstallation::Permissions.check(installation: installation,
                                                            actor:        editor,
                                                            action:       :remove_repositories,
                                                            repositories: removed_repositories)
      end

      return true if result.permitted?
      raise Result::Error.new(result.error_message, result.reason)
    end

    def install_on_all_repositories
      grant_repository_permissions_on_target
      uninstall_from_repositories(current_repositories)
    end

    def originally_granted_access_to_subset_of_repositories?
      @original_repository_selection == "selected"
    end

    def install_on_repositories
      rows = repositories_to_install.flat_map do |repository|
        repository_permissions.map do |resource, action|
          subject = repository.resources.public_send(resource)
          ::Permissions::Service.app_attributes(actor: installation, subject: subject, action: action)
        end
      end

      ::Permissions::Service.grant_permissions(rows, entry_point: entry_point)
    end

    # Private: Remove this integration's access to a set
    # of repositories.
    #
    # repositories - The list of repositories to give remove access to.
    #
    # Examples
    #
    #   uninstall_from_repositories(repositories)
    #
    # Returns nothing.
    def uninstall_from_repositories(repositories)
      return if repositories.empty?

      ::Permissions::Service.revoke_permissions_granted_on_subjects(
        actor_ids:     [installation.ability_id],
        actor_type:    installation.ability_type,
        subject_ids:   repositories.map(&:id),
        subject_types: Repository::Resources.individual_type_prefixed_subject_types,
        entry_point: entry_point,
      )
    end

    def uninstall_unused_repositories
      # This removes permissions that were granted
      # such as access to protected branches.
      revoke_child_resources_for(repositories_to_remove)

      if installed_on_target?
        revoke_repository_permissions_on_target
      else
        uninstall_from_repositories(repositories_to_remove)
      end

      removed_repository_ids = repositories_to_remove.collect(&:id)

      SyncScopedIntegrationInstallationsJob.perform_later(installation, action: :repositories_removed, repository_ids: removed_repository_ids, entry_point: entry_point)
    end

    def repositories_to_install
      return @repositories_to_install if defined?(@repositories_to_install)
      @repositories_to_install = Array(repositories) if installed_on_target? || appending?
      @repositories_to_install ||= repositories - current_repositories
    end

    def repositories_to_remove
      current_repositories - repositories
    end

    def grant_repository_permissions_on_target
      rows = []

      rows = repository_permissions.map do |resource, action|
        subject = target.repository_resources.public_send(resource.to_s)
        ::Permissions::Service.app_attributes(actor: installation, subject: subject, action: action)
      end

      ::Permissions::Service.grant_permissions(rows, entry_point: entry_point)
    end

    def revoke_repository_permissions_on_target
      ::Permissions::Service.revoke_permissions_granted_on_subject(
        actor_id:      installation.ability_id,
        actor_type:    installation.ability_type,
        subject_id:    target.ability_id,
        subject_types: Repository::Resources.all_type_prefixed_subject_types,
        entry_point: @entry_point,
      )
    end

    def revoke_child_resources_for(repositories)
      revoke_protected_branch_access(repositories)
    end

    def revoke_protected_branch_access(repositories)
      ProtectedBranch.where(repository: repositories).in_batches do |relation|
        ::Permissions::Service.revoke_permissions_granted_on_subjects(
          actor_ids:     [installation.ability_id],
          actor_type:    installation.ability_type,
          subject_ids:   relation.pluck(:id),
          subject_types: ProtectedBranch::Resources.all_prefixed_subject_types,
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

    def calculate_added_and_removed_repositories
      flipper_enabled = GitHub.flipper[:installation_editor_current_repositories].enabled?(installation.integration)

      GitHub.dogstats.distribution_time("calculate_added_and_removed_repositories.duration", tags: ["flipper_enabled:#{flipper_enabled}"]) do
        if flipper_enabled
          repository_ids = repositories.map(&:id)
          currently_installed_repository_ids = installation.repository_ids
          added_repository_ids = repository_ids - currently_installed_repository_ids
          added_repositories = repositories.select { |repo| added_repository_ids.include?(repo.id) }

          if appending?
            removed_repositories = []
          else
            # remove any repositories that aren't in the repository_ids list
            removed_repository_ids = currently_installed_repository_ids - repository_ids
            removed_repositories = current_repositories.where(id: removed_repository_ids)
          end

          return added_repositories, removed_repositories
        else
          added_repositories = repositories - current_repositories
          removed_repositories = current_repositories - repositories

          return added_repositories, removed_repositories
        end
      end
    end
  end
end
