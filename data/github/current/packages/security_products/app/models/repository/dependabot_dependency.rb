# typed: strict
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
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def automated_security_updates_configurable_by?(actor)
    automated_security_updates_visible_to?(actor) && vulnerability_alerts_enabled?
  end

  # Whether to show Dependabot security updates to the given actor in the UI
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def automated_security_updates_visible_to?(actor)
    return false unless GitHub.dependabot_enabled?
    return false unless actor

    automated_security_updates_authorized_for?(actor)
  end

  # Whether the given actor *would* be authorized to see ASU
  # for this repository
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def automated_security_updates_authorized_for?(actor)
    can_view_vulnerability_alerts?(actor)
  end

  sig { returns(T::Boolean) }
  def dependabot_installed?
    dependabot_install.present?
  end

  # Whether to show Dependabot (scheduled updates beta) to the given actor in
  # the UI
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def automated_dependency_updates_visible_to?(actor)
    return false unless GitHub.dependency_graph_enabled?
    return false unless GitHub.dependabot_enabled?
    return false unless actor

    repository.writable_by?(actor)
  end

  sig { returns(T::Boolean) }
  def dependabot_api_error_pages_enabled?
    FeatureFlag.vexi.enabled_or_raise?(:dependabot_api_error_pages, repository) || # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      FeatureFlag.vexi.enabled_or_raise?(:dependabot_api_error_pages, repository.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  sig { returns(T.nilable(IntegrationInstallation)) }
  def dependabot_install
    return @dependabot_install if defined?(@dependabot_install)

    reload_dependabot_install
  end

  sig { returns(T.nilable(IntegrationInstallation)) }
  def reload_dependabot_install
    @dependabot_install = T.let(@dependabot_install, T.nilable(IntegrationInstallation))
    return @dependabot_install = nil unless GitHub.dependabot_github_app

    @dependabot_install = IntegrationInstallation.
      with_repository(self).
      find_by(integration_id: GitHub.dependabot_github_app.id)
  end

  sig { returns(T.nilable(String)) }
  def fetch_dependabot_config
    return @dependabot_config if defined?(@dependabot_config)
    @dependabot_config = T.let(@dependabot_config, T.nilable(String))

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

  sig { returns(T::Boolean) }
  def dependabot_config_file_exists?
    fetch_dependabot_config.present?
  end

  sig { returns(T::Boolean) }
  def dependabot_version_updates_enabled?
    T.bind(self, Repository)
    dependabot_config_file_exists? &&
      SecurityProduct::DependabotConfigFile.new(self).enabled?
  end

  sig { returns(T::Boolean) }
  def dependabot_config_file_enabled?
    T.bind(self, Repository)
    SecurityProduct::DependabotConfigFile.new(self).enabled?
  end

  sig { returns(T::Boolean) }
  def dependabot_enabled?
    (vulnerability_updates_enabled? || dependabot_version_updates_enabled?) &&
    !dependabot_updates_paused?
  end

  # Returns true if innersource repository alerting is enabled for this repository, its owner, or its business.
  sig { returns(T::Boolean) }
  def innersource_alerting_enabled?
    T.bind(self, Repository)
    return false if GitHub.enterprise? # Innersource alerting is not supported for GHES
    return false unless FeatureFlag.vexi.enabled?(:innersource_alerting, business, owner, self, default: false)

    # Innersource advisories require a GHAS Code Security entitlement (Team or Enterprise plan).
    AdvisoryDB::Innersource.code_security_entitled?(org_or_business: organization) ||
      AdvisoryDB::Innersource.code_security_entitled?(org_or_business: business)
  end

  sig { returns(T::Boolean) }
  memoize def dependabot_updates_paused?
    Repository::DependabotServiceManager.new(self).paused?
  end
end
