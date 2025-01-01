# typed: true
# frozen_string_literal: true

class IntegrationVersion
  class Differ
    attr_reader :old_version, :new_version, :permissions_differ

    class Result
      ATTRIBUTES = %i(
        events_added
        events_removed
        events_unchanged
        permissions_added
        permissions_downgraded
        permissions_removed
        permissions_unchanged
        permissions_upgraded
        single_file_paths_added
        single_file_paths_removed
        single_file_paths_unchanged
        content_references_added
        content_references_removed
        content_references_unchanged
      ).freeze

      attr_reader(*ATTRIBUTES)

      def initialize(options = {})
        ATTRIBUTES.each do |attribute|
          instance_variable_set("@#{attribute}", options[attribute])
        end
      end

      ATTRIBUTES.each do |attribute|
        next if attribute.to_s =~ %r{\A\S+_unchanged\z}

        define_method "#{attribute}?" do
          !instance_variable_get("@#{attribute}").empty?
        end
      end

      def events_changed?
        events_added? || events_removed?
      end

      def events_unchanged?
        !events_changed?
      end

      def permissions_changed?
        permissions_added? || permissions_downgraded? || permissions_removed? || permissions_upgraded?
      end

      def permissions_unchanged?
        !permissions_changed?
      end

      def single_file_paths_changed?
        single_file_paths_added? || single_file_paths_removed?
      end

      def single_file_paths_unchanged?
        !single_file_paths_changed?
      end

      def content_references_unchanged?
        !(content_references_added? || content_references_removed?)
      end

      def unchanged?
        events_unchanged? && permissions_unchanged? && single_file_paths_unchanged? && content_references_unchanged?
      end

      # Public: Can the old version be upgraded to the
      # new version without a User giving the ok?
      #
      # include_user_permissions - The option to include User::Resources
      #                            as permissions (default false).
      #
      # Returns a Boolean.
      #
      # Used by scoped integration installations, we might want
      # to unify this method with IntegrationInstallation::Permissions#can_auto_upgrade
      # REF: https://github.com/github/github/pull/121489#issuecomment-314437904
      def auto_upgradeable?(include_user_permissions: false)
        return false if single_file_paths_added?
        return false if content_references_added?
        return true unless permissions_added? || permissions_upgraded?

        return false if include_user_permissions

        # Are the permissions that were added only User/resource permissions?
        permissions = permissions_added.keys.delete_if do |resource|
          User::Resources.subject_types.include?(resource)
        end

        return false if permissions.any?

        # Are the permissions that were upgraded only User/resource permissions?
        permissions = permissions_upgraded.keys.delete_if do |resource|
          User::Resources.subject_types.include?(resource)
        end

        return false if permissions.any?

        true
      end

      # Public: List a permissisions acted upon of
      # a certain type.
      #
      # Examples:
      #
      # diff.permissions_of_type(Repository, action: added)
      # # => { "metadata" => :read }
      #
      # Returns a Hash.
      def permissions_of_type(resource_type, action:)
        permissions = self.send("permissions_#{action}")
        return {} if permissions.empty?

        subject_types = "#{resource_type}::Resources".constantize.send(:subject_types)

        permissions.select do |resource, _action|
          subject_types.include?(resource)
        end
      end
    end

    def self.perform(old_version:, new_version:)
      new(old_version: old_version, new_version: new_version).perform
    end

    def initialize(old_version:, new_version:)
      @old_version = old_version
      @new_version = new_version
      @permissions_differ = ::PermissionsDiffer.new(
        previous_permissions: old_version.default_permissions,
        new_permissions: new_version.default_permissions
      )
    end

    def perform
      Result.new({
        events_added:               added_events,
        events_removed:             removed_events,
        events_unchanged:           unchanged_events,
        permissions_added:          added_permissions,
        permissions_downgraded:     downgraded_permissions,
        permissions_removed:        removed_permissions,
        permissions_unchanged:      unchanged_permissions,
        permissions_upgraded:       upgraded_permissions,
        single_file_paths_added:      added_single_file_paths,
        single_file_paths_removed:    removed_single_file_paths,
        single_file_paths_unchanged:  unchanged_single_file_paths,
        content_references_added:     added_content_references,
        content_references_removed:   removed_content_references,
        content_references_unchanged: unchanged_content_references,
      })
    end

    delegate :added_permissions,
             :downgraded_permissions,
             :removed_permissions,
             :unchanged_permissions,
             :upgraded_permissions,
             to: :permissions_differ

    private

    def added_events
      new_version.default_events - old_version.default_events
    end

    def removed_events
      old_version.default_events - new_version.default_events
    end

    def unchanged_events
      new_version.default_events & old_version.default_events
    end

    def added_single_file_paths
      new_version.single_file_paths - old_version.single_file_paths
    end

    def removed_single_file_paths
      old_version.single_file_paths - new_version.single_file_paths
    end

    def unchanged_single_file_paths
      new_version.single_file_paths & old_version.single_file_paths
    end

    def added_content_references
      added_keys = new_version.default_content_references.keys - old_version.default_content_references.keys
      new_version.default_content_references.slice(*added_keys)
    end

    def removed_content_references
      removed_keys = old_version.default_content_references.keys - new_version.default_content_references.keys
      old_version.default_content_references.slice(*removed_keys)
    end

    def unchanged_content_references
      changed_keys = added_content_references.keys + removed_content_references.keys
      old_version.default_content_references.except(*changed_keys)
    end
  end
end
