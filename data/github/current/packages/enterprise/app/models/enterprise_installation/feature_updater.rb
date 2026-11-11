# typed: true
# frozen_string_literal: true

class EnterpriseInstallation
  class FeatureUpdater
    # inputs
    attr_reader :enterprise_installation, :actor

    # Result from the EnterpriseInstallation feature update
    class Result
      class Error < StandardError; end

      def self.success(enterprise_installation) new(:success, enterprise_installation: enterprise_installation) end
      def self.failed(error) new(:failed, error: error) end

      attr_reader :error, :enterprise_installation

      def initialize(status, enterprise_installation: nil, error: nil)
        @status = status
        @enterprise_installation = enterprise_installation
        @error        = error
      end

      def success?
        @status == :success
      end

      def failed?
        @status == :failed
      end
    end

    # Public: Update an EnterpriseInstallation for requested feature updates.
    #
    # enterprise_installation   - The EnterpriseInstallation that is being updated.
    # actor:                    - The User performing the action.
    # non_perm_change_features: - A hash of arrays of features that don't require permission changes (thus,
    #                             are not tracked in installation settings versions) that have been added
    #                             or removed
    # entry_point:              - Symbol, a unique identifier recorded in
    #                             Permissions::Service::Entrypoint to trace writes to the permissions
    #                             cluster.
    #
    # Returns an EnterpriseInstallation::FeatureUpdater::Result.
    def self.perform(enterprise_installation, actor:, non_perm_change_features: { added: [], removed: [] }, entry_point:)
      new(enterprise_installation, actor: actor, non_perm_change_features: non_perm_change_features, entry_point: entry_point).perform
    end

    def initialize(enterprise_installation, actor:, non_perm_change_features:, entry_point:)
      @enterprise_installation  = enterprise_installation
      @actor                    = actor
      @non_perm_change_features = non_perm_change_features
      # Don't allow any non_perm_change_features :added or :removed arrays to be nil
      @non_perm_change_features[:added] ||= []
      @non_perm_change_features[:removed] ||= []
      @entry_point = entry_point
    end

    def perform
      validate_actor

      integration = enterprise_installation.github_app
      if integration.nil?
        raise Result::Error, "Enterprise server installation is not set up for GitHub Connect"
      end

      version = integration.latest_version
      installation_on_owner = enterprise_installation.integration_installation
      previous_version = installation_on_owner.version

      if previous_version.number != version.number
        update_integration_installation_version(installation_on_owner, version, @entry_point)
        edit_integration_installation_repositories(installation_on_owner, @entry_point)
        instrument_features_updated(previous_version, version)
        if enterprise_installation.owner.is_a?(Business)
          UpdatePrivateSearchOnEnterpriseOrgsJob.perform_later(
            enterprise_installation.owner.id,
            { entry_point: :enterprise_installation_feature_updater }
          )
        end
      end

      Result.success(enterprise_installation)
    rescue Result::Error => e
      Failbot.report(e)
      Result.failed e.message
    end

    private

    def update_integration_installation_version(installation, version, entry_point)
      result = installation.auto_update_version(editor: actor, version: version, entry_point: entry_point)
      return if result.success?

      raise Result::Error, result.error
    end

    def edit_integration_installation_repositories(installation, entry_point)
      return unless repository_installation_required?(installation)

      result = installation.edit(editor: actor, repositories: nil, entry_point: entry_point)
      return if result.success?

      raise Result::Error, result.error
    end

    def repository_installation_required?(installation)
      installation.integration.repository_installation_required?(installation.target) && installation.repositories.none?
    end

    def instrument_features_updated(previous_version, latest_version)
      diff = latest_version.diff(previous_version)
      permissions_added = diff.permissions_added
      permissions_removed = diff.permissions_removed
      features_added = enterprise_installation.features_for_github_app_permissions(permissions_added)
      features_removed = enterprise_installation.features_for_github_app_permissions(permissions_removed)
      enterprise_installation.instrument_features_updated(
        features_added.union(@non_perm_change_features[:added]),
        features_removed.union(@non_perm_change_features[:removed]),
        actor)
    end

    def validate_actor
      return if enterprise_installation.owner.adminable_by?(actor)

      raise Result::Error, "Actor does not have permissions to enable or disable connect features for enterprise installation #{enterprise_installation.id}"
    end
  end
end
