# typed: true
# frozen_string_literal: true

class SecurityConfiguration < ApplicationRecord::Notify
  # don't forget that UnbundledSecurityConfiguration is a subclass of this model :)
  # overtime we should try to extract bundled specific logic into a BundledSecurityConfiguration subclass

  include Instrumentation::Model
  include Permissions::Attributes::Wrapper
  include SecurityConfiguration::AuditInstrumentation

  # Notify Alive WebSocket subscribers:
  after_commit :notify_socket_subscribers
  after_commit :instrument_create_configuration, on: :create, unless: :is_github_recommended_configuration?
  after_commit :instrument_update_configuration, on: :update, unless: :is_github_recommended_configuration?
  after_destroy_commit :instrument_delete_configuration
  # Defined in SecurityConfiguration::VersionManagement
  after_update :bump_version, if: :meaningful_change?
  include SecurityConfiguration::JobOrchestration
  include SecurityConfiguration::SecretScanningManagement
  include SecurityConfiguration::FeatureEnablementDuplication
  include SecurityConfiguration::BillingTransitions
  include SecurityConfiguration::VersionManagement

  self.permissions_wrapper_class = Permissions::Attributes::SecurityConfiguration
  self.ignored_columns += [:secret_scanning_push_protection_custom_message]

  # If you see `NameError: wrong constant name global`, you're probably trying to
  # call target when target_type = "global".
  belongs_to :target, polymorphic: true
  attr_readonly :target_type, :target_id

  has_many :repository_security_configurations, dependent: :delete_all, inverse_of: :security_configuration

  has_many :security_configuration_defaults, dependent: :delete_all, inverse_of: :security_configuration
  has_many :security_configuration_policies, dependent: :delete_all, inverse_of: :security_configuration

  FEATURE_STATES = { disabled: 0, enabled: 1, not_set: 2 }

  Registry = SecurityProductsEnablement::SecurityConfigurationRules::FeatureRegistry

  # Features that require either code_security_sku_enabled or bundled GHAS:
  CODE_SECURITY_FEATURES = T.let(Registry.features_for_sku(Registry::Sku::CodeSecurity).freeze, T::Array[Symbol])

  # Features that require either secret_protection_sku_enabled or bundled GHAS:
  SECRET_PROTECTION_FEATURES = T.let(Registry.features_for_sku(Registry::Sku::SecretProtection).freeze, T::Array[Symbol])

  # Bundled GHAS has access to all paid features:
  GHAS_FEATURES = T.let(Registry.paid_features.freeze, T::Array[Symbol])

  ALL_FEATURES = T.let(Registry.all_feature_keys.freeze, T::Array[Symbol])

  # ALL_FEATURES plus the boolean SKU columns (enable_ghas, code_security_sku_enabled, secret_protection_sku_enabled):
  ALL_FEATURES_WITH_SKUS = T.let(
    ([:enable_ghas, :code_security_sku_enabled, :secret_protection_sku_enabled] + ALL_FEATURES).freeze,
    T::Array[Symbol],
  )

  GH_CONFIG_NAME = "GitHub recommended"

  attribute :dependabot_malware_alerts, :integer

  # Feature enablement
  enum :private_vulnerability_reporting, FEATURE_STATES, prefix: true, validate: true
  enum :dependency_graph, FEATURE_STATES, prefix: true, validate: true
  enum :dependency_graph_autosubmit_action, FEATURE_STATES, prefix: true, validate: true
  enum :dependabot_alerts, FEATURE_STATES, prefix: true, validate: true
  enum :dependabot_security_updates, FEATURE_STATES, prefix: true, validate: true
  enum :dependabot_delegated_alert_dismissal, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :dependabot_malware_alerts, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :code_scanning, FEATURE_STATES, prefix: true, validate: true
  enum :code_scanning_delegated_alert_dismissal, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning, FEATURE_STATES, prefix: true, validate: true
  enum :secret_scanning_push_protection, FEATURE_STATES, prefix: true, validate: true
  enum :secret_scanning_delegated_bypass, FEATURE_STATES, prefix: true, validate: true
  enum :secret_scanning_validity_checks, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning_non_provider_patterns, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning_generic_secrets, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning_delegated_alert_dismissal, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning_extended_metadata, FEATURE_STATES, prefix: true, validate: { allow_nil: true }

  # These are the feature options that are stored in the database as JSON columns.
  FEATURE_OPTIONS = {
    dependency_graph_autosubmit_action_options: SecurityProduct::DependencyGraphAutosubmitAction::Options,
    # code_scanning_options here contains both general Code Scanning options
    # and those specific to AutoCodeQL.
    #
    # This is a different use of the term to in the API, where we have both `code_scanning_options`
    # (corresponding to the `code_scanning_general_options` method in this class) and
    # `code_scanning_default_setup_options`.
    code_scanning_options: CodeScanning::SecurityConfigurationOptions,
  }

  before_validation do
    # Ensure that we only persist relevant keys and include defaults for any non-defined keys.
    FEATURE_OPTIONS.each do |opts_attr, opts_class|
      T.bind(self, T.all(ActiveRecord::AttributeMethods, SecurityConfiguration))
      opts_values = read_attribute(opts_attr)
      updated_opts_values = opts_class.before_validation(opts_values)

      write_attribute(opts_attr, updated_opts_values)
    end
  end

  before_validation :clear_code_scanning_options_if_disabled
  before_validation :set_uninstalled_security_products_to_disabled_if_nil
  before_validation :disable_uninstalled_security_products_when_ghas_is_disabled
  before_validation :unique_name_across_org_and_enterprise

  RESERVED_NAMES = T.let(["GitHub recommended", "None", "No"].freeze, T::Array[String])

  normalizes :description, with: ->(description) { description.presence }

  validates :name, presence: true, length: { maximum: 100 }
  validates :name, uniqueness: { scope: [:target_type, :target_id] }
  validate :name_not_reserved
  validates :description, length: { maximum: 255 }
  validates :enable_ghas, inclusion: [true, false]

  validates_with SecurityProductsEnablement::SecurityConfigurationRules::Validator
  validates_with SecurityConfigurationOptionValidator, columns: FEATURE_OPTIONS
  validates_with SecurityConfiguration::SecurityProductAvailabilityOnCreateValidator, on: :create
  validates_with SecurityConfiguration::SecurityProductAvailabilityOnUpdateValidator, on: :update

  TargetType = T.type_alias { T.any(User, Business) }
  ModelHashType = T.type_alias { T::Hash[String, T.untyped] }

  sig do
    params(
      target: TargetType,
      model_hash: ModelHashType,
      default_for_new_public_repos: T.nilable(T::Boolean),
      default_for_new_private_repos: T.nilable(T::Boolean),
      enforcement: T.nilable(SecurityConfigurationPolicy::Enforcement),
      actor: T.nilable(User),
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), ActionController::Parameters),
    ).returns(SecurityConfiguration)
  end
  def self.create_configuration(target:, model_hash:, default_for_new_public_repos:, default_for_new_private_repos:, enforcement:, actor:, options: {})
    configuration = create(model_hash.merge(target:))
    return configuration if configuration.errors.any?

    if !default_for_new_public_repos.nil? || !default_for_new_private_repos.nil?
      SecurityConfigurationDefault.create_or_update_defaults(
        target:,
        default_for_new_public_repos: default_for_new_public_repos || false,
        default_for_new_private_repos: default_for_new_private_repos || false,
        security_configuration: configuration,
      )
    end

    # Only create policy records if enforcement is set to enforced on config creation
    if enforcement == SecurityConfigurationPolicy::Enforcement::Enforced
      SecurityConfigurationPolicy.create_or_update(
        target:,
        enforcement: enforcement,
        security_configuration_id: configuration.id,
      )
    end

    if configuration.secret_scanning_delegated_bypass_enabled? &&
        !options.nil? &&
        options[:secret_scanning_delegated_bypass].present? &&
        options[:secret_scanning_delegated_bypass][:reviewers].present?
      configuration.update_secret_scanning_bypass_reviewers(options, T.must(actor))
    end

    configuration
  end

  # Updates a security configuration and enqueues jobs to apply changes to repositories.
  #
  # @param repositories [SecurityProductsEnablement::RepositorySelection, nil] When provided, specifies which
  #   repositories should have this configuration applied. This triggers the :update_and_replace_repositories
  #   action instead of :update. Can only be used when updating at the organization level (either for an org
  #   config directly, or for enterprise/global configs with an org policies_target).
  sig do
    params(
      model_hash: ModelHashType,
      actor: User,
      repositories: T.nilable(SecurityProductsEnablement::RepositorySelection),
      policies_target: T.nilable(T.any(Business, User)),
      default_for_new_public_repos: T.nilable(T::Boolean),
      default_for_new_private_repos: T.nilable(T::Boolean),
      enforcement: T.nilable(SecurityConfigurationPolicy::Enforcement),
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), ActionController::Parameters),
    ).returns(T::Boolean)
  end
  def update_configuration(
    model_hash,
    actor,
    repositories: nil,
    policies_target: nil,
    default_for_new_public_repos: nil,
    default_for_new_private_repos: nil,
    enforcement: nil,
    options: {}
  )
    if global? && policies_target.nil?
      raise ArgumentError, "A policies_target must be provided when updating a global security configuration."
    end

    if repositories && !(target_type == User.name || policies_target.is_a?(Organization))
      raise ArgumentError, "repositories can only be provided when updating at the organization level"
    end

    # It's important to note that both GitHub recommended config and custom (Enterprise and org) configs can be updated by this method.
    # GH config is sometimes treated differently from custom configs.
    #
    # This method handles:
    # - Updating the settings of both GitHub recommended config and custom configs.
    # - Setting a config as default for new repos
    # - Setting the enforcement policy for a config
    if !global?
      update(model_hash)
      return false if errors.any?
    end

    # Resolve the target for policies, jobs, and defaults.
    # There are 2 distinct code paths:
    # - Organization-level configs (target_type == User.name): use the record's own target
    # - Enterprise/global configs: use policies_target (the org or business being configured) or fall back to the record's target
    if target_type == User.name
      current_target = target
    else
      current_target = policies_target || target
    end

    policy = create_or_update_policy(enforcement, current_target)
    enqueue_configuration_jobs(target: current_target, actor:, repositories:, policy:)
    update_secret_scanning_delegated_bypass(actor, options)
    create_or_update_defaults(current_target, default_for_new_public_repos, default_for_new_private_repos)

    true
  end

  def delete_configuration(actor)
    if secret_scanning_delegated_bypass_enabled?
      SecretScanning::Services::DelegatedBypassService.remove_bypassers_for_source(
        target,
        id,
        actor,
      )
    end
    destroy
  end

  sig do
    params(
      target: T.any(Business, User),
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

    validity_checks_state = "disabled"
    if GitHub.secret_scanning_validity_checks_available_on_instance?
      validity_checks_state = GitHub.single_or_multi_tenant_enterprise? ? "not_set" : "enabled"
    end

    extended_metadata_state = "disabled"
    if validity_checks_state != "disabled" && GitHub.secret_scanning_extended_metadata_available_on_instance?
      extended_metadata_state = GitHub.single_or_multi_tenant_enterprise? ? "not_set" : "enabled"
    end

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
      dependabot_delegated_alert_dismissal: "not_set",
      dependabot_malware_alerts: "not_set",
      code_scanning: "enabled",
      code_scanning_delegated_alert_dismissal: "not_set",
      secret_scanning: "enabled",
      secret_scanning_push_protection: "enabled",
      secret_scanning_delegated_bypass: "not_set",
      secret_scanning_non_provider_patterns: "enabled",
      secret_scanning_validity_checks: validity_checks_state,
      secret_scanning_generic_secrets: "not_set",
      secret_scanning_delegated_alert_dismissal: "not_set",
      code_security_sku_enabled: false,
      secret_protection_sku_enabled: false,
      secret_scanning_extended_metadata: extended_metadata_state,
    })
  end

  sig do
    params(
      repository: Repository,
      actor: User,
      override_existing_config: T::Boolean,
      override_params: T::Hash[Symbol, String],
      reason: T.nilable(Symbol),
      prevent_additional_sku_usage: T.nilable(T::Array[GitHub::Turboghas::SKU]),
    ).returns(T::Boolean)
  end
  def apply_to_repository(
    repository,
    actor:,
    override_existing_config: false,
    override_params: {},
    reason: nil,
    prevent_additional_sku_usage: nil
  )
    repo_config = repository.repository_security_configuration

    # If there is another config that is still attaching to the repo, we don't want to do anything
    return false if repo_config&.attaching?

    # If there is another config that is already attached to the repo, we don't want to do anything if
    # the override_existing_config flag is false
    # An archived repo should be considered attached and when it is unarchived, we want to apply the config again.
    return false if repo_config&.applied? && !override_existing_config && reason != :repo_unarchived

    # Delete the repo config if it exists, because we are going to create a new one
    # whose security products settings we want to enforce
    RepositorySecurityConfiguration.throttle_writes_with_retry do
      RepositorySecurityConfiguration.transaction do
        # Only delete the repo config if it exists and is not the same as the current config
        if repo_config
          if repo_config.security_configuration_id != id
            repo_config.destroy!
          else
            # otherwise touch it to update the updated_at timestamp
            repo_config.touch
          end
        end

        # Create a new one if the repo config doesn't exist or was just destroyed
        if repo_config.nil? || repo_config.destroyed?
          RepositorySecurityConfiguration.create!(
            repository:,
            organization_id: repository.owner_id,
            security_configuration: self,
            state: :attaching,
          )
        end
      end
    end

    additional_params = { override_params:, reason: }

    if prevent_additional_sku_usage && !prevent_additional_sku_usage.empty?
      additional_params[:prevent_additional_sku_usage] = prevent_additional_sku_usage
    end

    SecurityProductsEnablement.domain.configurations.enqueue_attachment(
      actor_id: actor.id,
      repository:,
      security_configuration_id: self.id,
      **additional_params
    )

    true
  end

  sig { overridable.returns(T::Boolean) }
  def bundled?
    true
  end

  sig { returns(T::Boolean) }
  def global?
    target_type == "global"
  end

  sig { returns(T::Boolean) }
  def business?
    target_type == "Business"
  end

  sig { returns(T::Boolean) }
  def organization?
    target_type == "User" && target.is_a?(Organization)
  end

  sig do
    params(
      target: T.any(Business, User),
    ).returns(T::Boolean)
  end
  def enforced?(target)
    if target.is_a?(Organization)
      business = target.business
      org_scoped_enforcement = enforced_for_target?(target)

      if org_scoped_enforcement.nil? && business
        enforced_for_target?(business) || false
      else
        org_scoped_enforcement || false
      end
    else
      enforced_for_target?(target) || false
    end
  end

  sig { params(owner_id: Integer).returns(T::Boolean) }
  def belongs_to_correct_target_id?(owner_id)
    return true if target_type == "global"

    owner_id == target_id
  end

  sig { returns(T::Boolean) }
  def belongs_to_enterprise?
    target_type == "Business"
  end

  sig { returns(T::Boolean) }
  def any_feature_previously_changed?
    ALL_FEATURES_WITH_SKUS.any? { send("#{_1}_previously_changed?") } || code_scanning_options_previously_changed?
  end

  sig { returns(T::Boolean) }
  def enables_ghas_features?
    return true if enable_ghas
    GHAS_FEATURES.any? { attributes[_1.to_s] == "enabled" }
  end

  sig { returns(T::Boolean) }
  def ghas_is_being_disabled?
    enable_ghas_changed? && enable_ghas == false && enable_ghas_was == true
  end

  # Does this configuration enable GHAS features, regardless if they're bundled or unbundled:
  sig { returns(T::Boolean) }
  def explicitly_enables_paid_features?
    !!enable_ghas || !!code_security_sku_enabled || !!secret_protection_sku_enabled
  end

  sig { returns(T::Boolean) }
  def uses_action_minutes?
    dependency_graph_autosubmit_action_enabled? || code_scanning_enabled?
  end

  sig { params(feature: Symbol).returns(T::Boolean) }
  def feature_nil_or_disabled?(feature)
    raise ArgumentError, "Unknown feature: #{feature}" unless ALL_FEATURES.include?(feature)
    value = self[feature]
    value.nil? || value == "disabled"
  end

  sig { params(feature: Symbol).returns(T::Boolean) }
  def feature_enabled?(feature)
    raise ArgumentError, "Unknown feature: #{feature}" unless ALL_FEATURES.include?(feature)
    self[feature] == "enabled"
  end

  sig { params(enforcement: T.nilable(SecurityConfigurationPolicy::Enforcement), target: T.any(User, Business)).returns(T.nilable(SecurityConfigurationPolicy)) }
  def create_or_update_policy(enforcement, target)
    return unless enforcement

    SecurityConfigurationPolicy.create_or_update(target:, enforcement:, security_configuration_id: id)
  end

  sig do
    params(
      target: T.any(Business, User),
      default_for_new_public_repos: T.nilable(T::Boolean),
      default_for_new_private_repos: T.nilable(T::Boolean)
    ).void
  end
  def create_or_update_defaults(target, default_for_new_public_repos, default_for_new_private_repos)
    return if default_for_new_public_repos.nil? && default_for_new_private_repos.nil?

    SecurityConfigurationDefault.create_or_update_defaults(
      target:,
      default_for_new_public_repos: default_for_new_public_repos || false,
      default_for_new_private_repos: default_for_new_private_repos || false,
      security_configuration: self,
    )
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

  sig { params(billable_entity: T.nilable(Billing::Types::Account)).returns(T.nilable(String)) }
  def description(billable_entity: nil)
    return super() unless is_github_recommended_configuration? && billable_entity && !billable_entity.advanced_security_products_bundled?

    "Suggested settings for Secret Protection and Code Security, managed by GitHub."
  end

  sig { params(billable_entity: T.nilable(Billing::Types::Account)).returns(T.nilable(T::Boolean)) }
  def enable_ghas(billable_entity: nil)
    return super() unless billable_entity && is_github_recommended_configuration? && !billable_entity.advanced_security_products_bundled?

    false
  end

  sig { params(billable_entity: T.nilable(Billing::Types::Account)).returns(T.nilable(T::Boolean)) }
  def code_security_sku_enabled(billable_entity: nil)
    return super() unless billable_entity && is_github_recommended_configuration? && !billable_entity.advanced_security_products_bundled?

    true
  end

  sig { params(billable_entity: T.nilable(Billing::Types::Account)).returns(T.nilable(T::Boolean)) }
  def secret_protection_sku_enabled(billable_entity: nil)
    return super() unless billable_entity && is_github_recommended_configuration? && !billable_entity.advanced_security_products_bundled?

    true
  end

  # Display a ternary SKU state value (true/false/nil) with proper text for stafftools
  sig { params(value: T.untyped).returns(String) }
  def display_sku_state(value)
    case value
    when true
      "Yes"
    when false
      "No"
    when nil
      "Not set"
    else
      "Unknown" # We shouldn't see this value, but just in case something goes really wrong
    end
  end

  # Returns that subset of code_scanning_options that relate to default setup.
  sig { returns(T.nilable(T::Hash[String, T.nilable(String)])) }
  def code_scanning_default_setup_options
    code_scanning_options&.slice(
      "runner_type",
      "runner_label",
    )
  end

  # Returns that subset of code_scanning_options that relate to Code Scanning as a whole.
  # Feel free to make the sig broader if you need to include more options.
  sig { returns(T.nilable(T::Hash[String, T.nilable(T::Boolean)])) }
  def code_scanning_general_options
    code_scanning_options&.slice("allow_advanced")
  end

  private

  # You probably want to use #enforced? instead of this method.
  # This method only checks the target, it doesn't handle
  # enterprise or org level inheritance of enforcement.
  #
  # This method returns nil if there is no enforcement policy for the target, otherwise it returns the enforcement policy.
  sig do
    params(
      target: T.any(Business, User),
    ).returns(T.nilable(T::Boolean))
  end
  def enforced_for_target?(target)
    target_type = target.is_a?(Business) ? "Business" : "User"

    SecurityConfigurationPolicy.find_by(
      target_type:,
      target_id: target.id,
      security_configuration_id: id
    )&.enforced?
  end

  def clear_code_scanning_options_if_disabled
    if code_scanning != "enabled" || code_scanning_options["runner_type"].nil?
      self.code_scanning_options = { "runner_type" => "not_set", "runner_label" => nil }
    end
  end

  def set_uninstalled_security_products_to_disabled_if_nil
    # Ensure that when we create this record, we set "disabled" for any features that are for an
    # uninstalled security product
    SecurityProductsEnablement::SecurityProductsManager.new.services.each do |service, is_installed|
      next if is_installed || self[service].present?
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

      if !code_scanning_delegated_alert_dismissal_disabled? && !manager.code_scanning_delegated_alert_dismissal_enabled?
        self.code_scanning_delegated_alert_dismissal = "disabled"
      end

      if !secret_scanning_disabled? && !manager.secret_scanning_enabled?
        self.secret_scanning = "disabled"
        self.secret_scanning_non_provider_patterns = "disabled"
        self.secret_scanning_push_protection = "disabled"
        self.secret_scanning_delegated_bypass = "disabled"
        self.secret_scanning_validity_checks = "disabled"
        self.secret_scanning_generic_secrets = "disabled"
        self.secret_scanning_delegated_alert_dismissal = "disabled"
      end
    end
  end

  def unique_name_across_org_and_enterprise
    return if target_id == 0 # Skip global config

    if target_type == "User"
      org = Organization.find_by(id: target_id)
      return if org&.business.nil?

      if SecurityConfiguration.where(target: T.must(org).business, name:).exists?
        errors.add(:name, "has already been taken by an enterprise configuration")
      end
    elsif target_type == "Business"
      business = Business.find_by(id: target_id)
      return unless business

      org_ids = T.must(business).organization_ids

      if SecurityConfiguration.where(target_type: "User", target_id: org_ids, name:).exists?
        errors.add(:name, "has already been taken by an organization in enterprise")
      end
    end
  end

  def name_not_reserved
    config_name = name&.strip
    return if target_type == "global"

    if RESERVED_NAMES.include?(config_name)
      errors.add(:name, "#{config_name} is a reserved configuration name")
    end
  end
end
