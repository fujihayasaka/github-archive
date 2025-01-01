# typed: true
# frozen_string_literal: true

# The Dependabot module collects service-specific jobs and helpers
module Dependabot
  autoload :AutomaticInstallationCheck, "dependabot/automatic_installation_check"
  autoload :RepositoryAccess, "dependabot/repository_access"
  autoload :Twirp, "dependabot/twirp"
  autoload :UpdateJob, "dependabot/update_job"
  autoload :Versioning, "dependabot/versioning"

  # This configuration pattern is set in our installation trigger
  # in stafftools:
  #   https://admin.github.com/stafftools/automatic-apps
  #
  # If you change this pattern, please update the trigger as well!
  CONFIG_FILE_PATH_PATTERN = /\A\.github\/dependabot\.ya?ml\z/

  TEMPLATE = <<~YAML.freeze
    # To get started with Dependabot version updates, you'll need to specify which
    # package ecosystems to update and where the package manifests are located.
    # Please see the documentation for all configuration options:
    # https://docs.github.com/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file

    version: 2
    updates:
      - package-ecosystem: "" # See documentation for possible values
        directory: "/" # Location of package manifests
        schedule:
          interval: "weekly"
  YAML

  # Checks if a given file path matches Dependabot's expected file path
  def self.recognized_config_path?(path:)
    path =~ CONFIG_FILE_PATH_PATTERN
  end

  def self.repository_manifests_changed(repository:, reason: nil, push_id: nil)
    return unless repository.vulnerability_alerts_enabled?

    # If Dependabot is not available, we should just dispatch the alert update and return
    unless GitHub.dependabot_enabled? && GitHub.dependabot_github_app
      UpdateRepositoryVulnerabilityAlertsJob.enqueue_for_repository(repository, { reason: reason, push_id: push_id })
      return
    end

    automatic_install_check = AutomaticInstallationCheck.new(repository)
    if automatic_install_check.should_install?
      # The Security Alerts jobs will be called once the install is completed.
      AutomaticAppInstallation.trigger(
        type: :dependency_graph_initialized, # this is a legacy name from when this was only called at initialization
        originator: repository,
        actor: repository.owner,
      )

      GitHub.dogstats.increment("dependabot.manifest_detection.install.created")
    else
      # Delegate to the Security Alerts job to update the Repository's alerts.
      UpdateRepositoryVulnerabilityAlertsJob.enqueue_for_repository(repository, { reason: reason, push_id: push_id })
    end
  end

  # Initializes Dependabot for the Dependabot security updates feature
  # specifically.
  def self.enroll_for_security_updates(repository:)
    if repository.dependabot_installed?
      # If Dependabot is already installed, we just need to enroll it
      # so we build PRs for any open alerts
      Dependabot::RepositoryEnrollJob.enqueue(repository)
    else
      # Otherwise, we need to trigger an installation which will perform
      # the enroll as a callback.
      AutomaticAppInstallation.trigger(
        type: :automatic_security_updates_initialized,
        originator: repository,
        actor: repository.owner,
      )
    end
  end

  # Initializes Dependabot for a one-off update.
  def self.enroll_for_single_update(dependency_update:)
    AutomaticAppInstallation.trigger(
      type: :dependency_update_requested,
      originator: dependency_update,
      actor: dependency_update.repository,
    )
  end

  # This is the subset of AdvisoryDB::Ecosystems.supported that are supported by Dependabot
  # Security Updates.
  #
  # It currently correlates to AdvisoryDB::Ecosystems.dependency_graph_supported, but this
  # may not always be the case.
  SECURITY_UPDATES_SUPPORTED = %w(
    rubygems
    npm
    pip
    maven
    nuget
    composer
    go
    rust
    actions
    pub
    swift
  )

  def self.security_updates_supported?(package_ecosystem:)
    SECURITY_UPDATES_SUPPORTED.include?(package_ecosystem.downcase)
  end

  # These values map to icons in public/images/icons/dependabot/*.svg
  def self.serialize_package_ecosystem(package_ecosystem:)
    case package_ecosystem
    when :ACTIONS then "actions"
    when :BUNDLER then "bundler"
    when :CARGO then "cargo"
    when :COMPOSER then "composer"
    when :DEVCONTAINERS then "devcontainers"
    when :DOCKER then "docker"
    when :DOCKER_COMPOSE then "docker-compose"
    when :DOTNET_SDK then "dotnet-sdk"
    when :ELM then "elm"
    when :ERLANG then "erlang"
    when :GITHUB_ACTIONS then "actions"
    when :GITSUBMODULE then "gitsubmodule"
    when :GOMOD then "gomod"
    when :GRADLE then "gradle"
    when :HELM then "helm"
    when :MAVEN then "maven"
    when :MIX then "mix"
    when :NPM then "npm"
    when :NUGET then "nuget"
    when :PIP then "pip"
    when :PUB then "pub"
    when :RUST_TOOLCHAIN then "rust-toolchain"
    when :SWIFT then "swift"
    when :TERRAFORM then "terraform"
    when :UV then "uv"
    when :VCPKG then "vcpkg"
    else "unknown"
    end
  end

  def self.short_manifest_file_path(full_manifest_path)
    parts = full_manifest_path.split("/")
    if parts.count > 3
      parts.last(2).join("/").prepend(parts.first, "/…/")
    else
      full_manifest_path
    end
  end

  def self.version_class_for(ecosystem)
    case ecosystem.downcase.to_sym
    when :composer
      Dependabot::Versioning::Composer::Version
    when :erlang
      Dependabot::Versioning::Hex::Version
    when :actions
      Dependabot::Versioning::GithubActions::Version
    when :go
      Dependabot::Versioning::GoModules::Version
    when :maven
      Dependabot::Versioning::Maven::Version
    when :npm
      Dependabot::Versioning::NpmAndYarn::Version
    when :nuget
      Dependabot::Versioning::Nuget::Version
    when :pip
      Dependabot::Versioning::Python::Version
    when :pub
      Dependabot::Versioning::Pub::Version
    when :rust
      Dependabot::Versioning::Cargo::Version
    when :rubygems
      Dependabot::Versioning::Bundler::Version
    else
      # For Global Advisories API, falling back on base class will be sufficient for querying
      Dependabot::Versioning::Version
    end
  end

  def self.dependabot_autofix_available_for?(actor)
    return true if FeatureFlag.vexi.enabled?(:dependabot_autofix, default: false)
    return true if actor.feature_flag_enabled_or_raise?(:dependabot_autofix) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    if actor.respond_to?(:owner)
      return true if actor.owner.feature_flag_enabled_or_raise?(:dependabot_autofix) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    false
  end
end
