# typed: true
# frozen_string_literal: true

class SiteScopedIntegrationInstallation
  class Permissions
    attr_reader :integration, :target, :repositories, :action, :permissions

    class Result
      attr_reader :result, :reason

      def self.for(result, reason: nil)
        new(result, reason: reason)
      end

      HUMAN_READABLE_REASONS = {
        missing_integration:           "A parent integration is required.",
        missing_target:                "A target is required.",
        missing_repositories:          "No repositories were provided.",
        permissions_added_or_upgraded: "The permissions requested are not granted to this integration.",
        repositories_not_available:    "There is at least one repository that does not exist.",
        #TODO: REMOVE with feature flag multiple_targets removal
        repositories_not_available_to_target: "There is at least one repository that does not exist or is not accessible by the target.",
        invalid_action:                "There is at least one permission action that is not supported. It should be one of: \"read\", \"write\" or \"admin\".",
        invalid_resource:              "There is at least one permission resource that is not supported.",
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

    def self.check(integration:, target:, repositories:, action:, permissions: {})
      new(integration, target, repositories, action, permissions: permissions).check
    end

    def initialize(integration, target, repositories, action, permissions: {})
      @integration  = integration
      @target       = target
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

    private

    def can_create
      return result(false, :missing_integration)  if integration.blank?
      return result(false, :missing_target)       if target.blank?

      permissions_check = validate_permissions
      return permissions_check unless permissions_check.permitted?

      # Make sure the requested repositories exist
      repos_check = validate_repositories
      return repos_check unless repos_check.permitted?

      if repository_permissions_requested? && !installing_on_all? && repositories.empty?
        return result(false, :missing_repositories)
      end

      result(true)
    end

    def validate_permissions
      begin
        @transient_version = integration.versions.build.tap do |v|
          v.default_permissions = permissions
        end
      rescue ArgumentError
        return result(false, :invalid_action)
      end

      # Ensure the requested permissions are for valid resources
      if !@transient_version.valid? && @transient_version.errors.include?("default_permission_records.resource")
        return result(false, :invalid_resource)
      end

      # Ensure the permissions are not being added or upgraded
      # from the parent integration
      differ = IntegrationVersion::Differ.perform(
        old_version: integration.latest_version,
        new_version: @transient_version,
      )

      unless differ.auto_upgradeable?
        return result(false, :permissions_added_or_upgraded)
      end

      result(true)
    end

    def validate_repositories
      return result(true) if installing_on_all? || repositories.blank?

      repository_ids = repositories.map(&:id).uniq

      # Are there any requested repos that don't belong to the target?
      unavailable_repos = ActiveRecord::Base.connected_to(role: :reading) do
        target.repositories.where(id: repository_ids).count != repository_ids.count
      end

      if unavailable_repos
        return result(false, :repositories_not_available_to_target)
      end

      result(true)
    end

    def repository_permissions_requested?
      return false if @transient_version.nil?
      @transient_version.any_permissions_of_type?(Repository)
    end

    def installing_on_all?
      repositories == SiteScopedIntegrationInstallation::Creator::INSTALL_ON_ALL_REPOSITORIES
    end

    def result(value, reason = nil)
      Result.for(value, reason: reason)
    end
  end
end
