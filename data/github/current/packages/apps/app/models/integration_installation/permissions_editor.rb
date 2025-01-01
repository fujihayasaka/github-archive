# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  class PermissionsEditor
    attr_reader :installation,
                :target,
                :editor,
                :differ,
                :old_version,
                :new_version,
                :entry_point

    # Result from the IntegrationInstallation permission edit
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

      def cannot_auto_upgrade?
        return false if success?
        error.message == ::IntegrationInstallation::CANNOT_AUTO_UPGRADE_ERROR_MESSAGE
      end
    end

    # Public: Edit an integration's access to repositories
    #
    # integration - The Integration being installed.
    # editor:     - The User performing the installation edit.
    # version     - The IntegrationVersion used for permissions and events.
    # entry_point - Symbol, the unique identifier passed to the Permissions
    #               service for instrumentation purposes.
    #
    # Returns an IntegrationInstallation::Creator::Result.
    def self.perform(installation, editor:, version:, entry_point:)
      new(installation, editor: editor, version: version, entry_point: entry_point).perform
    end

    def initialize(installation, editor: nil, version:, entry_point:)
      @installation = installation
      @old_version  = installation.version
      @new_version  = version
      @editor       = editor
      @target       = installation.target
      @entry_point  = entry_point

      @differ = IntegrationVersion::Differ.perform(old_version: @old_version, new_version: @new_version)
    end

    def perform
      check = IntegrationInstallation::Permissions.check(
        installation: installation,
        actor:        editor,
        action:       :update_permissions,
        version:      new_version,
      )

      unless check.permitted?
        message = case check.reason
        when :incorrect_version
          "Version does not belong to integration"
        else
          "You do not have permission to edit integrations on #{target.display_login}"
        end

        raise Result::Error, message
      end

      # TODO: look into this cross-cluster transaction.
      ApplicationRecord::Permissions.transaction do
        IntegrationInstallation.transaction do
          set_repository_permissions            if target.is_a?(User) # this counts for orgs and users.
          set_permissions_of_type(Organization) if target.is_a?(Organization)
          set_permissions_of_type(Business)     if target.is_a?(Business)

          upgrade_permissions
          downgrade_permissions
          remove_permissions

          subscribe_to_events

          installation.update(integration_version_id: new_version.id, integration_version_number: new_version.number)
        end
      end

      bust_cache

      unless Apps::Privileged.capable?(:skip_version_update_audit_log, app: installation.integration)
        instrument_installation_version_changed
      end
      GitHub.dogstats.increment("integration_installation.update", tags: ["result:success", "type:permissions"])

      SyncScopedIntegrationInstallationsJob.perform_later(installation,
        action:      :permissions_updated,
        old_version: @old_version,
        new_version: @new_version,
        entry_point: entry_point
      )

      Result.success(installation)
    rescue Result::Error => e
      GitHub.dogstats.increment("integration_installation.update", tags: ["result:failed", "type:permissions"])
      Result.failed e.message
    end

    private

    def bust_cache
      installation.clear_cached_permissions
    end

    def downgrade_permissions
      downgraded_permissions = differ.permissions_downgraded
      return if downgraded_permissions.empty?

      permissions_with_read_access  = downgraded_permissions.select { |_resource, action| action == :read }
      permissions_with_write_access = downgraded_permissions.select { |_resource, action| action == :write }

      ::Permissions::Service.update_action_for_permissions(
        actor_ids: [installation.ability_id],
        actor_type: installation.ability_type,
        subject_types: IntegrationVersion::PermissionsExpander.expand(permissions_with_read_access),
        action: :read,
        entry_point: entry_point
      )

      ::Permissions::Service.update_action_for_permissions(
        actor_ids: [installation.ability_id],
        actor_type: installation.ability_type,
        subject_types: IntegrationVersion::PermissionsExpander.expand(permissions_with_write_access),
        action: :write,
        entry_point: entry_point
      )

      # In the event that the "contents" permission gets downgraded
      # we need to revoke any permissions granted to protected
      # branches.
      return unless downgraded_permissions.key?("contents")

      ::Permissions::Service.revoke_permissions_granted_on_actor(
        actor_id: installation.ability_id,
        actor_type: installation.ability_type,
        subject_types: ProtectedBranch::Resources.all_prefixed_subject_types,
        entry_point: entry_point,
      )
    end

    # Private: Give this integration access to a set of repositories.
    #
    # permissions - The Hash of String resource and Symbol action pairs,
    #               representing the level of permission to give the integration.
    #
    # Examples
    #
    #   install_on_repositories("statuses" => :write)
    #
    # Returns nothing.
    def install_on_repositories(permissions)
      transient_repository = Repository.new

      rows = installation.repository_ids.flat_map do |repository_id|
        permissions.map do |resource, action|
          # Instead of loading all of the Repository objects
          # just keep updating the id of a transient record
          # so that we can get the proper subject.
          transient_repository.id = repository_id
          subject = transient_repository.resources.public_send(resource)

          ::Permissions::Service.app_attributes(actor: installation, subject: subject, action: action)
        end
      end

      ::Permissions::Service.grant_permissions(rows, entry_point: entry_point)
    end

    def instrument_installation_version_changed
      options = {
        actor:       editor,
        actor_id:    editor.id,
        old_version: old_version.number,
        new_version: new_version.number,
      }

      IntegrationVersion::Differ::Result::ATTRIBUTES.each do |attr_method|
        next if differ.public_send(attr_method).empty?
        options[attr_method] = differ.public_send(attr_method)
      end

      installation.instrument(:version_updated, options)
    end

    # Internal: Remove the Abilities for an Integration's
    # IntegrationInstallations.
    #
    # Returns nothing.
    def remove_permissions
      subject_types = IntegrationVersion::PermissionsExpander.expand(differ.permissions_removed)
      return if subject_types.none?

      # In the event that we have to revoke the "contents"
      # permission we might need to revoke protected branch
      # permissions as well.
      if differ.permissions_removed.key?("contents")
        subject_types += ProtectedBranch::Resources.all_prefixed_subject_types
      end

      ::Permissions::Service.revoke_permissions_granted_on_actor(
        actor_id: installation.ability_id,
        actor_type: installation.ability_type,
        subject_types: subject_types,
      )
    end

    def set_permissions_for_all_repositories(permissions)
      rows = permissions.map do |resource, action|
        subject = target.repository_resources.public_send(resource.to_s)
        ::Permissions::Service.app_attributes(actor: installation, subject: subject, action: action)
      end

      ::Permissions::Service.grant_permissions(rows, entry_point: entry_point)
    end

    def set_permissions_of_type(target_type)
      rows = differ.permissions_of_type(target_type, action: :added).map do |resource, action|
        subject = target.resources.public_send(resource)
        ::Permissions::Service.app_attributes(actor: installation, subject: subject, action: action)
      end

      ::Permissions::Service.grant_permissions(rows, entry_point: entry_point)
    end

    def set_repository_permissions
      permissions_to_add = differ.permissions_of_type(Repository, action: :added)
      return if permissions_to_add.empty?

      if installation.installed_on_all_repositories?
        set_permissions_for_all_repositories(permissions_to_add)
      else
        install_on_repositories(permissions_to_add)
      end
    end

    def subscribe_to_events
      return if differ.events_unchanged?
      installation.update!(events: new_version.default_events)
    end

    def upgrade_permissions
      upgraded_permissions = differ.permissions_upgraded
      return if upgraded_permissions.empty?

      permissions_with_write_access = upgraded_permissions.select { |_resource, action| action == :write }
      permissions_with_admin_access = upgraded_permissions.select { |_resource, action| action == :admin }

      ::Permissions::Service.update_action_for_permissions(
        actor_ids: [installation.ability_id],
        actor_type: installation.ability_type,
        subject_types: IntegrationVersion::PermissionsExpander.expand(permissions_with_write_access),
        action: :write,
        entry_point: entry_point
      )

      ::Permissions::Service.update_action_for_permissions(
        actor_ids: [installation.ability_id],
        actor_type: installation.ability_type,
        subject_types: IntegrationVersion::PermissionsExpander.expand(permissions_with_admin_access),
        action: :admin,
        entry_point: entry_point
      )
    end
  end
end
