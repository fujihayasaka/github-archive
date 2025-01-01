# typed: true
# frozen_string_literal: true

class SecurityConfiguration < ApplicationRecord::Notify
  # don't forget that UnbundledSecurityConfiguration is a subclass of this model :)
  # overtime we should try to extract bundled specific logic into a BundledSecurityConfiguration subclass

  include Instrumentation::Model
  include Permissions::Attributes::Wrapper

  self.permissions_wrapper_class = Permissions::Attributes::SecurityConfiguration
  self.ignored_columns += [:secret_scanning_push_protection_custom_message]

  # If you see `NameError: wrong constant name global`, you're probably trying to
  # call target when target_type = "global".
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

  # Features that require either code_security_sku_enabled or bundled GHAS:
  CODE_SECURITY_FEATURES = %i[
    code_scanning
    code_scanning_delegated_alert_dismissal
  ].freeze

  # Features that require either secret_protection_sku_enabled or bundled GHAS:
  SECRET_PROTECTION_FEATURES = %i[
    secret_scanning
    secret_scanning_non_provider_patterns
    secret_scanning_push_protection
    secret_scanning_delegated_bypass
    secret_scanning_validity_checks
    secret_scanning_generic_secrets
    secret_scanning_delegated_alert_dismissal
  ].freeze

  # Bundled GHAS has access to all paid features:
  GHAS_FEATURES = CODE_SECURITY_FEATURES + SECRET_PROTECTION_FEATURES

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
  enum :code_scanning_delegated_alert_dismissal, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning, FEATURE_STATES, prefix: true, validate: true
  enum :secret_scanning_push_protection, FEATURE_STATES, prefix: true, validate: true
  enum :secret_scanning_delegated_bypass, FEATURE_STATES, prefix: true, validate: true
  enum :secret_scanning_validity_checks, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning_non_provider_patterns, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning_generic_secrets, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning_delegated_alert_dismissal, FEATURE_STATES, prefix: true, validate: { allow_nil: true }

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
      enforcement: T.nilable(SecurityConfigurationPolicy::Enforcement),
      actor: T.nilable(User),
      options: T.any(
        T.nilable(T::Hash[Symbol, T.untyped]),
        ActionController::Parameters),
    ).returns(SecurityConfiguration)
  end
  def self.create_configuration(model_hash:, default_for_new_public_repos:, default_for_new_private_repos:, enforcement:, actor:, options: {})
    configuration = create(model_hash)
    return configuration if configuration.errors.any?

    if !default_for_new_public_repos.nil? || !default_for_new_private_repos.nil?
      SecurityConfigurationDefault.create_or_update_defaults(
        target: model_hash["target"],
        default_for_new_public_repos: default_for_new_public_repos || false,
        default_for_new_private_repos: default_for_new_private_repos || false,
        security_configuration: configuration,
      )
    end

    # Only create policy records if enforcement is set to enforced on config creation
    if enforcement == SecurityConfigurationPolicy::Enforcement::Enforced
      SecurityConfigurationPolicy.create_or_update(
        target: model_hash["target"],
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

  sig do
    params(
      model_hash: T::Hash[String, T.untyped],
      actor: User,
      type: Symbol,
      policies_target: T.nilable(T.any(Business, User)),
      default_for_new_public_repos: T.nilable(T::Boolean),
      default_for_new_private_repos: T.nilable(T::Boolean),
      enforcement: T.nilable(SecurityConfigurationPolicy::Enforcement),
      options: T.any(
        T.nilable(T::Hash[Symbol, T.untyped]),
        ActionController::Parameters),
    ).returns(T::Boolean)
  end
  def update_configuration(
    model_hash,
    actor,
    type:,
    policies_target: nil,
    default_for_new_public_repos: nil,
    default_for_new_private_repos: nil,
    enforcement: nil,
    options: {}
  )
    # It's important to note that both GitHub recommended config and custom (Enterprise and org) configs can be updated by this method.
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

    case type
    when :organization, :user
      current_target = model_hash["target"]
      policy = create_or_update_policy(enforcement, current_target)
      enqueue_configuration_jobs(current_target, actor, policy, type)
      update_secret_scanning_delegated_bypass(actor, options)
      create_or_update_defaults(current_target, default_for_new_public_repos, default_for_new_private_repos)
    else
      # This block handles:
      # - Updating the enterprise config from enterprise or org level
      # - Updating global config from enterprise or org level
      current_target = policies_target.nil? ? model_hash["target"] : policies_target
      policy = create_or_update_policy(enforcement, current_target)
      enqueue_configuration_jobs(current_target, actor, policy, type)
      update_secret_scanning_delegated_bypass(actor, options)
      create_or_update_defaults(current_target, default_for_new_public_repos, default_for_new_private_repos)
    end

    true
  end

  def delete_configuration(actor)
    if secret_scanning_delegated_bypass_enabled?
      SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewers_for_source(
        self.target,
        self.id,
        actor,
      )
    end
    self.destroy
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
      validity_checks_state = GitHub.multi_tenant_enterprise? ? "not_set" : "enabled"
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

    ApplySecurityConfigurationToRepositoryJob.perform_later(
      actor_id: T.must(actor.id),
      repository_id: T.must(repository.id),
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

  sig { returns(T::Boolean) }
  def any_feature_previously_changed?
    ALL_FEATURES.any? { send("#{_1}_previously_changed?") } || code_scanning_options_previously_changed?
  end

  sig { returns(T::Boolean) }
  def secret_scanning_scan_triggering_feature_is_enabled?
    secret_scanning_is_enabled? || secret_scanning_generic_secrets_is_enabled? || secret_scanning_non_provider_patterns_is_enabled?
  end

  sig { returns(T::Boolean) }
  def secret_scanning_is_enabled?
    secret_scanning_enabled? && (secret_scanning_previously_was == "disabled" || secret_scanning_previously_was == "not_set")
  end

  sig { returns(T::Boolean) }
  def secret_scanning_generic_secrets_is_enabled?
    secret_scanning_generic_secrets_enabled? && (secret_scanning_generic_secrets_previously_was == "disabled" || secret_scanning_generic_secrets_was == "not_set")
  end

  sig { returns(T::Boolean) }
  def secret_scanning_non_provider_patterns_is_enabled?
    secret_scanning_non_provider_patterns_enabled? && (secret_scanning_non_provider_patterns_previously_was == "disabled" || secret_scanning_non_provider_patterns_previously_was == "not_set")
  end

  sig { returns(T::Boolean) }
  def secret_scanning_delegated_bypass_is_disabled_or_not_set?
    (secret_scanning_delegated_bypass_disabled? || secret_scanning_delegated_bypass_not_set?) && secret_scanning_delegated_bypass_previously_was == "enabled"
  end

  sig { returns(T::Boolean) }
  def enables_ghas_features?
    return true if enable_ghas
    GHAS_FEATURES.any? { attributes[_1.to_s] == "enabled" }
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

  sig { void }
  def notify_socket_subscribers
    return if target_type == "global"
    return if target_type == "Business" # TODO: Come back to this once we expand target_type / target_id to encapsulate Enterprises
    return if target_type == "User" # TODO: Come back to this once we expand target_type / target_id to encapsulate Users
    return unless target.present?

    publisher = SecurityProductsEnablement::LiveUpdatePublisher.new(T.cast(target, Organization))
    publisher.configuration_updates
  end

  sig { void }
  def instrument_create_configuration
    return if target.nil?
    instrument :create, target: target
  end

  sig { void }
  def instrument_update_configuration
    return if target.nil?
    instrument :update, target: target
  end

  def instrument_security_feature_changed(security_feature:, security_feature_state:)
    instrument :update, target: target, security_feature: security_feature, security_feature_state: security_feature_state
  end

  sig { void }
  def instrument_delete_configuration
    return if target.nil?
    instrument :delete, target: target
  end

  # Set prefix for audit log events, this is needed to correctly emit UnbundledSecurityConfiguration events
  sig { returns(String) }
  def event_prefix
    "security_configuration"
  end

  sig { returns(Hash) }
  def event_payload
    payload = {
      security_configuration_id: id,
      security_configuration_name: name,
      security_configuration_description: description,
      security_configuration_created_at: created_at,
      security_configuration_updated_at: updated_at,
      security_configuration_enable_ghas: enable_ghas,
      security_configuration_code_security_sku_enabled: code_security_sku_enabled,
      security_configuration_secret_protection_sku_enabled: secret_protection_sku_enabled,
      security_configuration_type: type,
      security_configuration_private_vulnerability_reporting: private_vulnerability_reporting,
      security_configuration_dependency_graph: dependency_graph,
      security_configuration_dependency_graph_autosubmit_action: dependency_graph_autosubmit_action_event_value,
      security_configuration_dependabot_alerts: dependabot_alerts,
      security_configuration_dependabot_security_updates: dependabot_security_updates,
      security_configuration_code_scanning: code_scanning,
      security_configuration_code_scanning_delegated_alert_dismissal: code_scanning_delegated_alert_dismissal,
      security_configuration_secret_scanning: secret_scanning,
      security_configuration_secret_scanning_push_protection: secret_scanning_push_protection,
      security_configuration_secret_scanning_delegated_bypass: secret_scanning_delegated_bypass,
      security_configuration_secret_scanning_validity_checks: secret_scanning_validity_checks,
      security_configuration_secret_scanning_non_provider_patterns: secret_scanning_non_provider_patterns,
      security_configuration_secret_scanning_generic_secrets: secret_scanning_generic_secrets,
      security_configuration_secret_scanning_delegated_alert_dismissal: secret_scanning_delegated_alert_dismissal,
    }

    case target
    when Business
      payload[:business] = target.display_login
      payload[:business_id] = target_id
    when Organization
      payload[:org] = target.display_login
      payload[:org_id] = target_id
    when User
      payload[:user] = target.display_login
      payload[:user_id] = target_id
    end

    payload
  end

  sig { params(enforcement: T.nilable(SecurityConfigurationPolicy::Enforcement), target: T.any(User, Business)).returns(T.nilable(SecurityConfigurationPolicy)) }
  def create_or_update_policy(enforcement, target)
    return unless enforcement

    SecurityConfigurationPolicy.create_or_update(target:, enforcement:, security_configuration_id: self.id)
  end

  sig { params(actor: User, options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), ActionController::Parameters),).void }
  def update_secret_scanning_delegated_bypass(actor, options)
    if secret_scanning_delegated_bypass_is_disabled_or_not_set?
      SecretScanning::Services::DelegatedBypassService.remove_bypass_reviewers_for_source(
        self.target,
        self.id,
        actor,
      )
    else
      if secret_scanning_delegated_bypass_enabled? &&
          !options.nil? &&
          options[:secret_scanning_delegated_bypass].present? &&
          options[:secret_scanning_delegated_bypass][:reviewers].present?
        update_secret_scanning_bypass_reviewers(options, actor)
      end
    end
  end

  sig { params(target: T.any(Business, User), actor: User, policy: T.nilable(SecurityConfigurationPolicy), type: Symbol).void }
  def enqueue_configuration_jobs(target, actor, policy, type)
    if any_feature_previously_changed? || policy&.enforcement_previously_changed?
      options = secret_scanning_scan_triggering_feature_is_enabled? ? { publish_backfill_group_request: true } : {}

      case type
      when :enterprise
        enqueue_enterprise_job(target, actor, options)
        enqueue_organization_job(target, actor, options) if target.is_a?(Organization)
      when :organization
        enqueue_organization_job(target, actor, options)
      when :user
        enqueue_user_job(target, actor, options)
      end
    end
  end

  sig { params(target: T.any(Business, User), actor: User, options: T::Hash[Symbol, T.untyped]).void }
  def enqueue_enterprise_job(target, actor, options)
    SecurityProductsEnablement::EnterpriseSecurityConfigurationJob.perform_later(
      security_configuration_id: id,
      enterprise_id: target.id,
      actor_id: actor.id,
      action: :update,
      options:
    )
  end

  sig { params(target: T.any(Business, User), actor: User, options: T::Hash[Symbol, T.untyped]).void }
  def enqueue_organization_job(target, actor, options)
    SecurityProductsEnablement::OrganizationSecurityConfigurationJob.perform_later(
      security_configuration_id: id,
      organization_id: target.id,
      actor_id: actor.id,
      action: :update,
      repository_ids: nil,
      options:
    )
  end

  sig { params(target: T.any(Business, User), actor: User, options: T::Hash[Symbol, T.untyped]).void }
  def enqueue_user_job(target, actor, options)
    SecurityProductsEnablement::UserSecurityConfigurationJob.perform_later(
      security_configuration_id: id,
      user_id: target.id,
      action: :update,
      repository_ids: nil,
      options:
    )
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

  sig { returns(T::Boolean) }
  def ghas_is_being_disabled?
    enable_ghas_changed? && enable_ghas == false && enable_ghas_was == true
  end

  # Does this configuration enables GHAS features, regardless if they're bundled or unbundled:
  sig { returns(T::Boolean) }
  def explicitly_enables_paid_features?
    !!enable_ghas || !!code_security_sku_enabled || !!secret_protection_sku_enabled
  end

  def uses_action_minutes?
    dependency_graph_autosubmit_action_enabled? || code_scanning_enabled?
  end

  sig { returns(UnbundledSecurityConfiguration) }
  def unbundle!
    raise ArgumentError, "Cannot unbundle global configurations" if global?
    raise ArgumentError, "Can only unbundle a SecurityConfiguration" unless instance_of?(SecurityConfiguration)

    unbundled = T.cast(becomes!(UnbundledSecurityConfiguration), UnbundledSecurityConfiguration)

    if enable_ghas
      unbundled.enable_ghas = false
      # Only enable CS / SP when it is actually used. Otherwise it should be `not_set`.
      unbundled.code_security_sku_enabled = CODE_SECURITY_FEATURES.any? { |feature| send("#{feature}_enabled?") } || nil
      unbundled.secret_protection_sku_enabled = SECRET_PROTECTION_FEATURES.any? { |feature| send("#{feature}_enabled?") } || nil
    end

    unbundled.save!

    unbundled
  end

  sig { params(billable_entity: Billing::Types::OrgOrBusiness, bundled_ghas: T::Boolean).void }
  def self.advanced_security_billing_toggled(billable_entity, bundled_ghas)
    existing_configs = T.let([], T::Array[SecurityConfiguration])

    logging_tags = {
      "code.namespace": self.name,
      "code.function": __method__,
      "gh.security_products_enablement.current_billing_state": bundled_ghas
    }

    if billable_entity.is_a?(Organization)
      logging_tags["gh.organization.id"] = billable_entity.id
      existing_configs = SecurityConfiguration.where(target: billable_entity).to_a
    elsif billable_entity.is_a?(Business)
      logging_tags["gh.business.id"] = billable_entity.id
      existing_configs = SecurityConfiguration.where(target: billable_entity).to_a
      existing_configs.concat(SecurityConfiguration.where(target_type: "User", target_id: billable_entity.organization_ids).to_a)
    end

    return if existing_configs.empty?

    logging_tags["gh.security_products_enablement.security_configuration_ids"] = existing_configs.map(&:id).join(",")

    GitHub.logger.with_named_tags(logging_tags) do
      GitHub.logger.info("Updating security configurations to match billing state")
      existing_configs.each do |config|
        self.transition_config(config, bundled_ghas)
      end
      GitHub.logger.info("Finished updating security configurations to match billing state")
    end
  end

  sig { params(configuration: SecurityConfiguration, bundled_ghas: T::Boolean).void }
  def self.transition_config(configuration, bundled_ghas)
    if bundled_ghas && configuration.instance_of?(UnbundledSecurityConfiguration)
      configuration.bundle!
    elsif !bundled_ghas && configuration.instance_of?(SecurityConfiguration)
      configuration.unbundle!
    end
  rescue ActiveRecord::RecordInvalid => e
    logging_tags = {
      "code.function": __method__,
      "gh.security_products_enablement.security_configuration_id": configuration.id,
      "exception": e,
    }
    GitHub.logger.info("Failed to transition security configuration", logging_tags)
    Failbot.report(e)
  end
  private_class_method :transition_config

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

  sig { params(feature: Symbol).returns(T::Boolean) }
  def feature_nil_or_disabled?(feature)
    feature = self[feature]
    feature.nil? || feature == "disabled"
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
    return nil if self.code_scanning_options.nil?

    self.code_scanning_options&.slice(
      "runner_type",
      "runner_label",
    )
  end

  # Returns that subset of code_scanning_options that relate to Code Scanning as a whole.
  # Feel free to make the sig broader if you need to include more options.
  sig { returns(T.nilable(T::Hash[String, T.nilable(T::Boolean)])) }
  def code_scanning_general_options
    return nil if self.code_scanning_options.nil?

    self.code_scanning_options.slice(
      "allow_advanced",
    )
  end

  sig { params(target: Organization).returns(T.nilable(SecurityConfiguration)) }
  def duplicate_and_enable_secret_scanning(target)
    # This configuration already has Secret Protection enabled!
    return nil if secret_scanning_enabled? && secret_scanning_push_protection_enabled?

    new_name = "#{name} (with Secret Protection)"
    target_attributes = attributes_for_duplication_and_secret_scanning_enablement(target:, name: new_name)

    # Using self.class allows us to use this method from inside the
    # UnbundledSecurityConfiguration model as well, keeping these queries
    # scoped to the appropriate configuration type.
    self.class.secret_scanning_enabled.where(target:).find_each do |config|
      return config if target_attributes == config.attributes_for_duplication_and_secret_scanning_enablement
    end

    if SecurityConfiguration.where(target:, name: new_name).exists?
      new_name = "#{name} (with Secret Protection - #{Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")})"
      target_attributes[:name] = new_name
    end

    with_write do
      # Using self.class ensures we create a security configuration of the
      # correct type, even from the UnbundledSecurityConfiguration model.
      new_config = self.class.new(target_attributes)
      new_config.description = description
      new_config.save!

      # Preserve enforcement status from the original configuration
      if enforced?(target)
        SecurityConfigurationPolicy.create_or_update(
          target: target,
          enforcement: SecurityConfigurationPolicy::Enforcement::Enforced,
          security_configuration_id: new_config.id,
        )
      end

      new_config
    end
  end

  # See UnbundledSecurityConfiguration#attributes_for_duplication_and_secret_scanning_enablement
  # for behavior when the security configuration belongs to an organization on unbundled GHAS.
  sig { overridable.params(target: Organization, name: String).returns(T::Hash[Symbol, T.untyped]) }
  protected def attributes_for_duplication_and_secret_scanning_enablement(target: self.target, name: self.name)
    {
      target:,
      name:,
      enable_ghas: true,
      code_scanning:,
      code_scanning_delegated_alert_dismissal:,
      code_scanning_options:,
      dependabot_alerts:,
      dependabot_security_updates:,
      dependency_graph:,
      dependency_graph_autosubmit_action:,
      dependency_graph_autosubmit_action_options:,
      private_vulnerability_reporting:,
      secret_scanning: "enabled",
      secret_scanning_delegated_alert_dismissal:,
      secret_scanning_delegated_bypass:,
      secret_scanning_generic_secrets:,
      secret_scanning_non_provider_patterns:,
      secret_scanning_push_protection: "enabled",
      secret_scanning_validity_checks:,
    }
  end

  sig { params(options: T.any((T::Hash[Symbol, T.untyped]), ActionController::Parameters), actor: User).void }
  def update_secret_scanning_bypass_reviewers(options, actor)
    bypass_reviewers = options[:secret_scanning_delegated_bypass][:reviewers].map do |reviewer|
      {
        owner_id: self.target_id,
        owner_scope: SecretScanning::Services::DelegatedBypassService.get_owner_scope_for_configuration(self),
        security_configuration_id: self.id,
        reviewer_id: reviewer["actorId"],
        reviewer_type: SecretScanning::Services::DelegatedBypassService.get_reviewer_type_from_actor_type(reviewer["actorType"])
      }
    end
    SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(
      self.target,
      self.id,
      bypass_reviewers,
      actor
    )
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
    if code_scanning != "enabled" || self.code_scanning_options["runner_type"].nil?
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



end
