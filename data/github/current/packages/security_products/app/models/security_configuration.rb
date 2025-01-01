# typed: true
# frozen_string_literal: true

class SecurityConfiguration < ApplicationRecord::Notify
  include Instrumentation::Model
  include Permissions::Attributes::Wrapper

  self.permissions_wrapper_class = Permissions::Attributes::SecurityConfiguration
  self.ignored_columns += [:secret_scanning_push_protection_custom_message]

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
    secret_scanning_delegated_bypass
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
  enum :secret_scanning_delegated_bypass, FEATURE_STATES, prefix: true, validate: true
  enum :secret_scanning_validity_checks, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning_non_provider_patterns, FEATURE_STATES, prefix: true, validate: { allow_nil: true }
  enum :secret_scanning_generic_secrets, FEATURE_STATES, prefix: true, validate: { allow_nil: true }

  # These are the feature options that are stored in the database as JSON columns.
  FEATURE_OPTIONS = {
    dependency_graph_autosubmit_action_options: SecurityProduct::DependencyGraphAutosubmitAction::Options,
    code_scanning_options: CodeScanning::AutoCodeql::Options,
  }

  before_validation do
    # Ensure that we only persist relevant keys and include defaults for any non-defined keys.
    FEATURE_OPTIONS.each do |opts_attr, opts_class|
      T.bind(self, ActiveRecord::AttributeMethods)
      opts_values = read_attribute(opts_attr)
      write_attribute(opts_attr, opts_class.before_validation(opts_values))
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
      enforcement: T.nilable(Symbol),
      actor: T.nilable(User),
      options: T.any(
        T.nilable(T::Hash[Symbol, T.untyped]),
        ActionController::Parameters),
    ).returns(SecurityConfiguration)
  end
  def self.create_configuration(model_hash, default_for_new_public_repos, default_for_new_private_repos, enforcement, actor, options = {})
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
    if enforcement == :enforced
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
      bypass_reviewers = options[:secret_scanning_delegated_bypass][:reviewers].map do |reviewer|
        {
          owner_id: configuration.target_id,
          owner_scope: :ORGANIZATION_SCOPE,
          security_configuration_id: configuration.id,
          reviewer_id: reviewer["actorId"],
          reviewer_type: reviewer["actorType"] == "RepositoryRole" ? :ROLE : :TEAM,
        }
      end
      SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(
        configuration.target,
        configuration.id,
        bypass_reviewers,
        T.must(actor),
      )
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
      enforcement: T.nilable(Symbol),
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
      enqueue_configuration_jobs(current_target, actor, policy) unless type == :user
      update_secret_scanning_delegated_bypass(actor, options)
      create_or_update_defaults(current_target, default_for_new_public_repos, default_for_new_private_repos)
    else
      # This block handles:
      # - Updating the enterprise config from enterprise or org level
      # - Updating global config from enterprise or org level
      current_target = policies_target.nil? ? model_hash["target"] : policies_target
      policy = create_or_update_policy(enforcement, current_target)
      enqueue_configuration_jobs(current_target, actor, policy)
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
      secret_scanning_delegated_bypass: "not_set",
      secret_scanning_non_provider_patterns: "enabled",
      secret_scanning_validity_checks: "enabled"
    })
  end

  sig do
    params(
      actor: User,
      repository: Repository,
      organization: Organization,
      override_existing_config: T::Boolean,
      override_params: T::Hash[Symbol, String],
      reason: T.nilable(Symbol),
      skip_ghas_features: T::Boolean,
    ).returns(T::Boolean)
  end
  def apply_to_repository(
    actor,
    repository,
    organization,
    override_existing_config: false,
    override_params: {},
    reason: nil,
    skip_ghas_features: false
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

        # Create a new one if the repo config doesn't exist or was just detroyed
        if repo_config.nil? || repo_config.destroyed?
          RepositorySecurityConfiguration.create!(
            organization:,
            repository:,
            security_configuration: self,
            state: :attaching,
          )
        end
      end
    end

    ApplySecurityConfigurationToRepositoryJob.perform_later(
      actor_id: T.must(actor.id),
      repository_id: T.must(repository.id),
      security_configuration_id: self.id,
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

  sig { returns(T::Boolean) }
  def business?
    target_type == "Business"
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
    ALL_FEATURES.any? { send("#{_1}_previously_changed?") }
  end

  sig { returns(T::Boolean) }
  def secret_scanning_is_enabled?
    secret_scanning_enabled? && (secret_scanning_previously_was == "disabled" || secret_scanning_previously_was == "not_set")
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
      security_configuration_secret_scanning_delegated_bypass: secret_scanning_delegated_bypass,
      security_configuration_secret_scanning_validity_checks: secret_scanning_validity_checks,
      security_configuration_secret_scanning_non_provider_patterns: secret_scanning_non_provider_patterns,
    }.tap do |p|
      p[T.must(target).event_prefix] = target
    end
  end

  sig { params(enforcement: T.nilable(Symbol), target: T.any(User, Business)).returns(T.nilable(SecurityConfigurationPolicy)) }
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
        bypass_reviewers = options[:secret_scanning_delegated_bypass][:reviewers].map do |reviewer|
          {
            owner_id: self.target_id,
            owner_scope: :ORGANIZATION_SCOPE,
            security_configuration_id: self.id,
            reviewer_id: reviewer["actorId"],
            reviewer_type: reviewer["actorType"] == "RepositoryRole" ? :ROLE : :TEAM,
          }
        end
        SecretScanning::Services::DelegatedBypassService.update_bypass_reviewers_for_source(
          self.target,
          self.id,
          bypass_reviewers,
          T.must(actor),
        )
      end
    end
  end

  sig { params(target: T.any(Business, Organization), actor: User, policy: T.nilable(SecurityConfigurationPolicy)).void }
  def enqueue_configuration_jobs(target, actor, policy)
    if any_feature_previously_changed? || policy&.enforcement_previously_changed? || code_scanning_options_previously_changed?
      opts = any_feature_previously_changed? && secret_scanning_is_enabled? ? { publish_backfill_group_request: true } : {}

      case target
      when Business
        SecurityProductsEnablement::EnterpriseSecurityConfigurationJob.perform_later(
          security_configuration_id: id,
          enterprise_id: T.must(target.id),
          actor_id: T.must(actor.id),
          action: :update,
          options: opts,
        )
      when Organization
        SecurityProductsEnablement::OrganizationSecurityConfigurationJob.perform_later(
          security_configuration_id: id,
          organization_id: T.must(target.id),
          actor_id: T.must(actor.id),
          action: :update,
          repository_ids: nil,
          options: opts,
        )
      end
    end
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
    enable_ghas_changed? && enable_ghas_was == true && enable_ghas == false
  end

  def uses_action_minutes?
    dependency_graph_autosubmit_action_enabled? || code_scanning_enabled?
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
        self.secret_scanning_delegated_bypass = "disabled"
        self.secret_scanning_validity_checks = "disabled"
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
