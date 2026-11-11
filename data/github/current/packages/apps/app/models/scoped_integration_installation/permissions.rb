# typed: true
# frozen_string_literal: true

class ScopedIntegrationInstallation
  class Permissions
    attr_reader :installation, :repositories, :action, :permissions, :transient_version

    include GitHub::Memoizer

    class Result
      attr_reader :result, :reason

      def self.for(result, reason: nil)
        new(result, reason: reason)
      end

      HUMAN_READABLE_REASONS = {
        failed_to_write_permissions:          "Failed to grant permissions.",
        missing_parent:                       "A parent installation is required.",
        missing_repositories:                 "No repositories were provided.",
        permissions_added:                    "The permissions requested are not granted to this installation.",
        permissions_upgraded:                 "The level of access for permissions requested are not granted to this installation.",
        repositories_not_available_to_target: "There is at least one repository that does not exist or is not accessible to the parent installation.",
        invalid_action:                       "There is at least one permission action that is not supported. It should be one of: \"read\", \"write\" or \"admin\".",
        invalid_resource:                     "There is at least one permission resource that is not supported.",
        not_installed_on_all:                 "This installation is not installed on all repositories.",
        not_installed_on_selected:            "This installation is not installed on selected repositories.",
        suspended_parent:                     "The parent installation is suspended.",
        duplicate_repositories_selected:      "There is at least one repository that has been selected more than once. Please remove duplicate entries and try again."
      }.freeze

      def initialize(result, reason:)
        @result, @reason = result, reason
      end

      def permitted?
        @result
      end

      def error_message
        HUMAN_READABLE_REASONS.fetch(reason)
      end
    end

    def self.check(installation:, repositories: [], action:, permissions:)
      new(installation, repositories, action, permissions: permissions).check
    end

    def initialize(installation, repositories, action, permissions: {})
      @installation = installation
      @repositories = repositories
      @action       = action
      @permissions  = permissions
    end

    def check
      case action
      when :create
        can_create
      else
        result(false, :action_invalid)
      end
    end

    # Drop permissions the parent installation was not granted
    #
    # REF: https://github.com/github/ecosystem-apps/issues/2277
    #
    # As of https://github.com/github/github/pull/240959 GitHub Apps are uninstalled
    # during user to org transformations.
    memoize def valid_for_parent
      differ = PermissionsDiffer.new(previous_permissions: installation.permissions_or_cached_permissions, new_permissions: permissions)

      return permissions unless differ.added_permissions.any?

      permissions.reject do |key, _|
        differ.added_permissions.keys.include?(key)
      end
    end

    private

    def can_create
      return result(false, :missing_parent) if installation.nil?
      return result(false, :suspended_parent) if installation.suspended?

      # If there aren't any permissions then we won't be granting anything
      # other than a high rate limited public access token. But it seems like
      # something we should allow.
      return result(true) if permissions.none?

      permissions_check = validate_permissions
      return permissions_check unless permissions_check.permitted?

      # In the event that repository permissions are being requested,
      # go ahead and validate the users input. If the user has requested
      # repositories and didn't ask for repository permissions then it
      # would be a no-opt anyway.
      if repository_permissions_requested?
        if installing_on_all?
          return result(false, :not_installed_on_all) unless installation.installed_on_all_repositories?
        elsif installing_on_all_selected?
          return result(false, :not_installed_on_selected) unless installation.installed_on_selected_repositories?
        elsif repositories.any?
          requested_repository_ids = repositories.map(&:id)
          installed_repository_ids = installation.repository_ids(repository_ids: requested_repository_ids)

          # Are there any repositories that were requested
          # that are _not_ part accessible to the parent
          # installation?
          if (requested_repository_ids - installed_repository_ids).any?
            return result(false, :repositories_not_available_to_target)
          end
        else
          return result(false, :missing_repositories)
        end
      end

      result(true)
    end

    def validate_permissions
      check = validate_actions
      return check unless check.permitted?

      differ = PermissionsDiffer.new(
        previous_permissions: installation.version.default_permissions,
        new_permissions: permissions,
      )

      return result(false, :permissions_added) if differ.added_permissions.any?
      return result(false, :permissions_upgraded) if differ.upgraded_permissions.any?

      result(true)
    end

    def repository_permissions_requested?
      Repository::Resources.filter(permissions).any?
    end

    def installing_on_all?
      repositories == ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES
    end

    def installing_on_all_selected?
      repositories == ScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_SELECTED_REPOSITORIES
    end

    def validate_actions
      any_invalid_actions = permissions.values.any? { |action| !Permission.actions.key?(action) }
      any_invalid_actions ? result(false, :invalid_action) : result(true)
    end

    def result(value, reason = nil)
      Result.for(value, reason: reason)
    end
  end
end
