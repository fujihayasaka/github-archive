# typed: true
# frozen_string_literal: true

module Repository::DependabotDependency
  extend T::Helpers

  requires_ancestor { Repository }

  extend ActiveSupport::Concern
  include Configurable::RepositoryDependencyUpdates
  include Configurable::RepositoryVulnerabilityAlerts
  include GitHub::Memoizer

  DEPENDABOT_CONFIG_FILE_PATHS = %w(.github/dependabot.yml .github/dependabot.yaml).freeze

  included do
    T.bind(self, T.class_of(Repository))

    has_many :dependency_updates, class_name: :RepositoryDependencyUpdate,
      inverse_of: :repository
    destroy_dependents_in_background :dependency_updates
  end

  # Whether the give actor is allowed to opt in/out of Dependabot security updates in the UI and
  # the API
  def automated_security_updates_configurable_by?(actor)
    automated_security_updates_visible_to?(actor) && vulnerability_alerts_enabled?
  end

  # Whether to show Dependabot security updates to the given actor in the UI
  def automated_security_updates_visible_to?(actor)
    return false unless GitHub.dependabot_enabled?
    return false unless actor

    automated_security_updates_authorized_for?(actor)
  end

  # Whether the given actor *would* be authorized to see ASU
  # for this repository
  def automated_security_updates_authorized_for?(actor)
    can_view_vulnerability_alerts?(actor)
  end

  def dependabot_installed?
    dependabot_install.present?
  end

  # Whether to show Dependabot (scheduled updates beta) to the given actor in
  # the UI
  def automated_dependency_updates_visible_to?(actor)
    return false unless GitHub.dependency_graph_enabled?
    return false unless GitHub.dependabot_enabled?
    return false unless actor

    repository.writable_by?(actor)
  end

  def dependabot_api_error_pages_enabled?
    FeatureFlag.vexi.enabled_or_raise?(:dependabot_api_error_pages, repository) || # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      FeatureFlag.vexi.enabled_or_raise?(:dependabot_api_error_pages, repository.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def dependabot_install
    return @dependabot_install if defined?(@dependabot_install)

    reload_dependabot_install
  end

  def reload_dependabot_install
    return @dependabot_install = nil unless GitHub.dependabot_github_app

    @dependabot_install = IntegrationInstallation.
      with_repository(self).
      find_by(integration_id: GitHub.dependabot_github_app.id)
  end

  def fetch_dependabot_config
    return @dependabot_config if defined?(@dependabot_config)

    if self.branch_exists?(self.default_branch)
      DEPENDABOT_CONFIG_FILE_PATHS.each do |path|
        if self.includes_file?(path, self.default_branch)
          # Memoize the result and return it immediately:
          return @dependabot_config = path
        end
      end
    end

    # There's no file, set this to nil so we won't look again:
    @dependabot_config = nil
  end

  def dependabot_config_file_exists?
    fetch_dependabot_config.present?
  end

  def dependabot_version_updates_enabled?
    T.bind(self, Repository)
    dependabot_config_file_exists? &&
      SecurityProduct::DependabotConfigFile.new(self).enabled?
  end

  def dependabot_config_file_enabled?
    T.bind(self, Repository)
    SecurityProduct::DependabotConfigFile.new(self).enabled?
  end

  def dependabot_enabled?
    (vulnerability_updates_enabled? || dependabot_version_updates_enabled?) &&
    !dependabot_updates_paused?
  end

  memoize def dependabot_updates_paused?
    Repository::DependabotServiceManager.new(self).paused?
  end
end
