# typed: true
# frozen_string_literal: true

class SecurityConfiguration < ApplicationRecord::Notify
  extend T::Sig

  include Instrumentation::Model
  include Permissions::Attributes::Wrapper

  self.permissions_wrapper_class = Permissions::Attributes::SecurityConfiguration

  belongs_to :target, polymorphic: true

  # Notify Alive WebSocket subscribers:
  after_commit :notify_socket_subscribers
  after_commit :instrument_create_configuration, on: :create, unless: :is_github_recommended_configuration?
  after_commit :instrument_update_configuration, on: :update, unless: :is_github_recommended_configuration?
  after_destroy_commit :instrument_delete_configuration

  has_many :repository_security_configurations, dependent: :delete_all, inverse_of: :security_configuration

  has_many :security_configuration_defaults, dependent: :delete_all, inverse_of: :security_configuration
  has_many :security_configuration_policies, dependent: :delete_all, inverse_of: :security_configuration

  FEATURE_STATES = { disabled: 0, enabled: 1, not_set: 2 }

  GHAS_FEATURES = %i[
    code_scanning
    secret_scanning
    secret_scanning_non_provider_patterns
    secret_scanning_push_protection
    secret_scanning_validity_checks
  ].freeze

  ALL_FEATURES = %i[
    enable_ghas
    private_vulnerability_reporting
    dependency_graph
    dependency_graph_autosubmit_action
    dependabot_alerts
    dependabot_security_updates
  ].freeze + GHAS_FEATURES

  GH_CONFIG_NAME = "GitHub recommended"

  # Feature enablement
  enum :private_vulnerability_reporting, FEATURE_STATES, prefix: true, validate: true
  enum :dependency_graph, FEATURE_STATES, prefix: true, validate: true
  enum :dependency_graph_autosubmit_action, FEATURE_STATES, prefix: true, validate: true
  enum :dependabot_alerts, FEATURE_STATES, prefix: true, validate: true
  enum :dependabot_security_updates, FEATURE_STATES, prefix: true, validate: true
  enum :code_scanning, FEATURE_STATES, prefix: true, validate: true
  enum :secret_scanning, FEATURE_STATES, prefix: true, validate: true
  enum :secret_scanning_push_protection, FEATURE_STATES, prefix: true, validate: true
  enum :secret_scanning_validity_checks, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning_non_provider_patterns, FEATURE_STATES, prefix: true, validate: { allow_nil: true }

  # Feature options
  FEATURE_OPTIONS = {
    dependency_graph_autosubmit_action_options: SecurityProduct::DependencyGraphAutosubmitAction::Options
  }

  before_validation do
    # Ensure that we only persist relevant keys and include defaults for any non-defined keys.
    FEATURE_OPTIONS.each do |opts_attr, opts_class|
      T.bind(self, ActiveRecord::AttributeMethods)
      opts_values = read_attribute(opts_attr)
      write_attribute(opts_attr, opts_class.before_validation(opts_values))
    end
  end

  before_validation :set_uninstalled_security_products_to_disabled_if_nil
  before_validation :disable_uninstalled_security_products_when_ghas_is_disabled

  validates :name, presence: true, length: { maximum: 100 }
  validates :name, uniqueness: { scope: [:target_type, :target_id] }
  validates :description, presence: true, length: { maximum: 255 }
  validates :enable_ghas, inclusion: [true, false]

  validates_with SecurityConfigurationValidator
  validates_with SecurityConfigurationOptionValidator, columns: FEATURE_OPTIONS
  validates_with SecurityConfiguration::SecurityProductAvailabilityOnCreateValidator, on: :create
  validates_with SecurityConfiguration::SecurityProductAvailabilityOnUpdateValidator, on: :update

  sig do
    params(
      model_hash: T::Hash[String, T.untyped],
      default_for_new_public_repos: T.nilable(T::Boolean),
      default_for_new_private_repos: T.nilable(T::Boolean),
      enforcement: T.nilable(Symbol),
    ).returns(SecurityConfiguration)
  end
  def self.create_configuration(model_hash, default_for_new_public_repos, default_for_new_private_repos, enforcement)
    configuration = create(model_hash)
    return configuration if configuration.errors.any?

    if !default_for_new_public_repos.nil? || !default_for_new_private_repos.nil?
      SecurityConfigurationDefault.create_or_update_defaults(
        target: model_hash["target"],
        default_for_new_public_repos: default_for_new_public_repos || false,
        default_for_new_private_repos: default_for_new_private_repos || false,
        security_configuration_id: T.must(configuration.id),
      )
    end

    # Only create policy records if enforcement is set to enforced on config creation
    if enforcement == :enforced
      SecurityConfigurationPolicy.create_or_update(
        target: model_hash["target"],
        enforcement: enforcement,
        security_configuration_id: T.must(configuration.id),
      )
    end

    configuration
  end

  sig do
    params(
      model_hash: T::Hash[String, T.untyped],
      actor: User,
      default_for_new_public_repos: T.nilable(T::Boolean),
      default_for_new_private_repos: T.nilable(T::Boolean),
      enforcement: T.nilable(Symbol),
    ).returns(T::Boolean)
  end
  def update_configuration(model_hash, actor, default_for_new_public_repos: nil, default_for_new_private_repos: nil, enforcement: nil)
    # It's important to note that both GitHub recommended config and custom configs can be updated by this method.
    # GH config is sometimes treated differently from custom configs.
    #
    # This method handles:
    # - Updating the settings of both GitHub recommended config and custom configs.
    # - Setting a config as default for new repos
    # - Setting the enforcement policy for a config

    if !global?
      update(model_hash)
      return false if self.errors.any?
    end

    policy =
      if enforcement
        SecurityConfigurationPolicy.create_or_update(
          target: model_hash["target"],
          enforcement: enforcement,
          security_configuration_id: T.must(self.id),
        )
      end

    if any_feature_previously_changed? || policy&.enforcement_previously_changed?
      options = any_feature_previously_changed? && secret_scanning_is_enabled? ? { publish_backfill_group_request: true } : {}

      SecurityProductsEnablement::OrganizationSecurityConfigurationJob.perform_later(
        security_configuration_id: T.must(id),
        organization_id: model_hash["target"].id,
        actor_id: T.must(actor.id),
        action: :update,
        repository_ids: nil,
        options:
      )
    end

    return true if default_for_new_public_repos.nil? && default_for_new_private_repos.nil?

    SecurityConfigurationDefault.create_or_update_defaults(
      target: model_hash["target"],
      default_for_new_public_repos: default_for_new_public_repos || false,
      default_for_new_private_repos: default_for_new_private_repos || false,
      security_configuration_id: T.must(id),
    )
    true
  end

  sig do
    params(
      target: User,
    ).returns(Symbol)
  end
  def enforcement(target)
    enforced?(target) ? :enforced : :not_enforced
  end

  sig { returns(T.nilable(SecurityConfiguration)) }
  def self.github_recommended_configuration
    # Replace this with `.first!` if it truly is available in all cases
    SecurityConfiguration.where(target_type: "global", target_id: 0).first
  end

  sig { returns(T::Boolean) }
  def is_github_recommended_configuration?
    target_type == "global" && target_id == 0
  end

  sig { returns(T.any(FalseClass, SecurityConfiguration)) }
  def self.create_github_recommended_configuration
    return false if SecurityConfiguration.exists?(target_type: "global", target_id: 0)

    create!({
      target_type: "global",
      target_id: 0,
      name: GH_CONFIG_NAME,
      description: "Suggested settings for Dependabot, secret scanning, and code scanning.",
      enable_ghas: true,
      private_vulnerability_reporting: GitHub.private_vulnerability_reporting_enabled? ? "enabled" : "disabled",
      dependency_graph: "enabled",
      dependency_graph_autosubmit_action: "not_set",
      dependabot_alerts: "enabled",
      dependabot_security_updates: "not_set",
      code_scanning: "enabled",
      secret_scanning: "enabled",
      secret_scanning_push_protection: "enabled",
      secret_scanning_non_provider_patterns: "enabled",
      secret_scanning_validity_checks: "enabled"
    })
  end

  sig { returns(Integer) }
  def repositories_count
    repository_security_configurations.applied.count
  end

  sig do
    params(
      actor: T.nilable(User),
      repository_id: Integer,
      organization_id: Integer,
      override_existing_config: T::Boolean,
      override_params: T::Hash[Symbol, String],
      reason: T.nilable(Symbol),
      skip_ghas_features: T::Boolean,
    ).returns(T::Boolean)
  end
  def apply_to_repository(
    actor,
    repository_id,
    organization_id,
    override_existing_config: false,
    override_params: {},
    reason: nil,
    skip_ghas_features: false
  )
    repo_config = RepositorySecurityConfiguration.find_by(repository_id: repository_id)

    # If there is another config that is still attaching to the repo, we don't want to do anything
    return false if repo_config&.attaching?

    # If there is another config that is already attached to the repo, we don't want to do anything if
    # the override_existing_config flag is false
    return false if repo_config&.applied? && !override_existing_config

    # Delete the repo config if it exists, because we are going to create a new one
    # whose security products settings we want to enforce
    RepositorySecurityConfiguration.throttle_writes_with_retry do
      RepositorySecurityConfiguration.transaction do
        repo_config&.destroy

        # Create configuration for the repo
        RepositorySecurityConfiguration.create!(
          organization_id:,
          repository_id: repository_id,
          security_configuration_id: self.id,
          state: :attaching
        )
      end
    end

    ApplySecurityConfigurationToRepositoryJob.perform_later(
      actor_id: actor&.id,
      repository_id: repository_id,
      security_configuration_id: T.must(self.id),
      override_params:,
      reason:,
      skip_ghas_features:,
    )

    true
  end

  sig { returns(T::Boolean) }
  def global?
    target_type == "global"
  end

  sig do
    params(
      target: User,
    ).returns(T.nilable(T::Boolean))
  end
  def enforced?(target)
    SecurityConfigurationPolicy.find_by(target_id: target.id, security_configuration_id: id)&.enforced?
  end

  sig { returns(T::Boolean) }
  def any_feature_previously_changed?
    ALL_FEATURES.any? { send("#{_1}_previously_changed?") }
  end

  sig { returns(T::Boolean) }
  def secret_scanning_is_enabled?
    secret_scanning_enabled? && (secret_scanning_previously_was == "disabled" || secret_scanning_previously_was == "not_set")
  end

  sig { returns(T::Boolean) }
  def enables_ghas_features?
    return true if enable_ghas
    GHAS_FEATURES.any? { attributes[_1.to_s] == "enabled" }
  end

  sig { params(owner_id: Integer).returns(T::Boolean) }
  def belongs_to_repository_owner_id?(owner_id)
    return true if target_type == "global"

    # TODO: Once we expand target_type / target_id to encapsulate Enterprises, we'll need to expand this method to
    #   check ownership there. For now, we'll just compare owner_id and target_id because we only support org owners.
    owner_id == target_id
  end

  sig { void }
  def notify_socket_subscribers
    return if target_type == "global"
    return unless target.present?

    publisher = SecurityProductsEnablement::LiveUpdatePublisher.new(T.cast(target, Organization))
    publisher.configuration_updates
  end

  def instrument_create_configuration
    return if target.nil?
    instrument :create, target: target
  end

  def instrument_update_configuration
    return if target.nil?
    instrument :update, target: target
  end

  def instrument_security_feature_changed(security_feature:, security_feature_state:)
    instrument :update, target: target, security_feature: security_feature, security_feature_state: security_feature_state
  end

  def instrument_delete_configuration
    return if target.nil?
    instrument :delete, target: target
  end

  def event_payload
    payload = {
      security_configuration_id: id,
      security_configuration_name: name,
      security_configuration_description: description,
      security_configuration_created_at: created_at,
      security_configuration_updated_at: updated_at,
      security_configuration_enable_ghas: enable_ghas,
      security_configuration_private_vulnerability_reporting: private_vulnerability_reporting,
      security_configuration_dependency_graph: dependency_graph,
      security_configuration_dependency_graph_autosubmit_action: dependency_graph_autosubmit_action_event_value,
      security_configuration_dependabot_alerts: dependabot_alerts,
      security_configuration_dependabot_security_updates: dependabot_security_updates,
      security_configuration_code_scanning: code_scanning,
      security_configuration_secret_scanning: secret_scanning,
      security_configuration_secret_scanning_push_protection: secret_scanning_push_protection,
      security_configuration_secret_scanning_validity_checks: secret_scanning_validity_checks,
      security_configuration_secret_scanning_non_provider_patterns: secret_scanning_non_provider_patterns,
    }.tap do |p|
      p[T.must(target).event_prefix] = target
    end
  end

  # For this feature, we want to mask the enablement state if the labeled_runner option is enabled
  # in order to avoid emiting an unbound JSON column which may contain a number of values that are
  # not implicitly relevant to the Audit Log.
  sig { returns(T.nilable(String)) }
  def dependency_graph_autosubmit_action_event_value
    if dependency_graph_autosubmit_action_enabled? && dependency_graph_autosubmit_action_options["labeled_runners"]
      "enabled_for_labeled_runners"
    else
      dependency_graph_autosubmit_action
    end
  end

  sig { returns(T::Boolean) }
  def ghas_is_being_disabled?
    enable_ghas_changed? && enable_ghas_was == true && enable_ghas == false
  end

  private

  def set_uninstalled_security_products_to_disabled_if_nil
    # Ensure that when we create this record, we set "disabled" for any features that are for an
    # uninstalled security product
    SecurityProductsEnablement::SecurityProductsManager.new.services.each do |service, is_installed|
      next if service == :dependabot_vea || is_installed || self[service].present?
      self[service] = "disabled"
    end
  end

  def disable_uninstalled_security_products_when_ghas_is_disabled
    # If GHAS is being disabled, we need to ensure that any uninstalled GHAS security products are set to "disabled"
    if ghas_is_being_disabled?
      manager = SecurityProductsEnablement::SecurityProductsManager.new

      if !code_scanning_disabled? && !manager.code_scanning_default_setup_enabled?
        self.code_scanning = "disabled"
      end

      if !secret_scanning_disabled? && !manager.secret_scanning_enabled?
        self.secret_scanning = "disabled"
        self.secret_scanning_non_provider_patterns = "disabled"
        self.secret_scanning_push_protection = "disabled"
        self.secret_scanning_validity_checks = "disabled"
      end
    end
  end
end
