# typed: true
# frozen_string_literal: true

# RepositorySecurityConfiguration represents the relationship between a
# SecurityConfiguration and a repository to which it is, was, or failed
# to be, attached.
# It records the state of the attachment and failure reason if any.
# See also SecurityConfiguration#apply_to_repository.
class RepositorySecurityConfiguration < ApplicationRecord::Notify
  include Permissions::Attributes::Wrapper
  include Instrumentation::Model
  include GitHub::Memoizer

  self.permissions_wrapper_class = Permissions::Attributes::RepositorySecurityConfiguration

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :security_configuration, inverse_of: :repository_security_configurations
  belongs_to :user, foreign_key: :organization_id, inverse_of: false # rubocop:disable GitHub/UseBelongsToDomain
  has_one :repository_security_center_config, foreign_key: :repository_id, primary_key: :repository_id, inverse_of: :repository_security_configuration

  validates_presence_of :organization_id

  # Notify Alive WebSocket subscribers if our state has changed:
  after_commit :notify_socket_subscribers, on: [:create, :update], if: :state_previously_changed?
  after_commit :instrument_update_event, on: :update
  after_commit :instrument_destroy_event, on: :destroy

  class State < T::Enum
    enums do
      Removed = new(:removed)
      Attached = new(:attached)
      Attaching = new(:attaching)
      Failed = new(:failed)
      Updating = new(:updating)
      Enforced = new(:enforced)
      RemovedByEnterprise = new(:removed_by_enterprise)
      Detached = new(:detached)
    end
  end

  STATES = T.let({
    removed: 0,
    attached: 1,
    attaching: 2,
    failed: 3,
    updating: 4,
    enforced: 5,
    removed_by_enterprise: 6,
    detached: 7,
  }.freeze, T::Hash[Symbol, Integer])

  enum :state, STATES

  # States considered "active" for Quick Setup repository selection.
  # These represent attachments that are currently applied or in-progress.
  # Used by QuickSetupService and OrganizationSecurityConfigurationJob.
  #
  # Repositories with attachments in these states are returned as selected
  # in the Quick Setup UI. Failed/removed attachments are intentionally
  # excluded: they won't appear as selected, and won't be detached
  # when users update their repository selection.
  #
  # Tech debt: we probably want to add `updating` to the `applied_or_attaching` scope
  # and using that instead of this separate scope.
  scope :active_for_quick_setup, -> { where(state: %w(attached enforced attaching updating)) }

  scope :not_failed, -> { where.not(state: :failed) }
  scope :not_enforced, -> { where.not(state: :enforced) }

  scope :applied, -> { where(state: %w(attached enforced)) }
  scope :applied_or_attaching, -> { where(state: %w(attached attaching enforced)) }

  # Scope by owner: for Organization, filters by organization_id; for Business, returns all (no org filter).
  # Note: Does NOT handle GitHub Recommended Configuration, which uses the `user` column instead.
  scope :for_owner, ->(owner) { owner.is_a?(Organization) ? where(organization_id: owner.id) : all }

  # returns true if the RepositorySecurityConfiguration is either attached or enforced
  sig { returns(T::Boolean) }
  def applied?
    attached? || enforced?
  end

  sig { params(action: String, feature: Symbol, owner: User, action_source: T.nilable(String), force: T::Boolean).void }
  def remove_if_possible(action:, feature:, owner:, action_source: nil, force: false)
    return unless SecurityProduct::ServiceManager::SERVICES_IN_SECURITY_CONFIGURATION.include?(feature)
    return if feature == :token_scanning_generic_secrets && !owner.feature_flag_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS, default: true)
    return if feature == :dependency_graph_autosubmit_action && !GitHub.dependency_graph_autosubmit_action_enabled?

    # Object may be stale, reload it to ensure we have the latest state.
    self.reload

    if !(applied? || failed?)
      if attaching?
        GitHub.logger.warn(
          "Aborting: Attempting to detach a configuration that is being attached",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository_id,
          "gh.security_products_enablement.repository_security_configuration_id": id,
          "gh.security_products_enablement.action": action,
          "gh.security_products_enablement.feature": feature,
        )
      end

      return
    end

    config_value = get_feature_value(feature)
    return if config_value == "not_set"
    return if action == config_value && !force

    case action_source
    when "security_configuration_enablement"
      # Skip removal for archived repositories when triggered by security configuration application
      removed! unless repository&.archived?
    when "sku_unbundling_transition"
      # During SKU unbundling transitions, don't detach security configurations.
      # The billing model is changing (bundled → split SKUs) and repo-level features
      # are being enabled to match, so a temporary mismatch with the security config
      # (e.g., GitHub Recommended Config with code_security_sku_enabled: false) is
      # expected and should not trigger detachment.
      nil
    when "enterprise_bulk_enablement"
      removed_by_enterprise!
    else
      removed!
    end
  end

  sig { params(feature: Symbol).returns T::Boolean }
  def feature_not_set?(feature)
    return true unless SecurityProduct::ServiceManager::SERVICES_IN_SECURITY_CONFIGURATION.include?(feature)
    get_feature_value(feature) == "not_set"
  end

  sig { params(feature: Symbol).returns T.nilable(String) }
  def get_feature_value(feature)
    case feature
    when :private_vulnerability_reporting
      T.must(security_configuration).private_vulnerability_reporting
    when :dependency_graph
      T.must(security_configuration).dependency_graph
    when :dependency_graph_autosubmit_action
      T.must(security_configuration).dependency_graph_autosubmit_action
    when :vulnerability_alerts
      T.must(security_configuration).dependabot_alerts
    when :vulnerability_updates
      T.must(security_configuration).dependabot_security_updates
    when :token_scanning
      T.must(security_configuration).secret_scanning
    when :token_scanning_validity_checks
      T.must(security_configuration).secret_scanning_validity_checks
    when :token_scanning_push_protection
      T.must(security_configuration).secret_scanning_push_protection
    when :token_scanning_delegated_bypass
      T.must(security_configuration).secret_scanning_delegated_bypass
    when :token_scanning_delegated_closures
      T.must(security_configuration).secret_scanning_delegated_alert_dismissal
    when :token_scanning_lower_confidence_patterns
      T.must(security_configuration).secret_scanning_non_provider_patterns
    when :token_scanning_generic_secrets
      T.must(security_configuration).secret_scanning_generic_secrets
    when :auto_codeql
      T.must(security_configuration).code_scanning
    when :advanced_security
      T.must(security_configuration).enable_ghas ? "enabled" : "disabled"
    when :code_security
      val = T.must(security_configuration).code_security_sku_enabled
      if val.nil?
        "not_set"
      else
        val ? "enabled" : "disabled"
      end
    when :code_scanning_delegated_alert_dismissal
      T.must(security_configuration).code_scanning_delegated_alert_dismissal
    when :dependabot_delegated_alert_dismissal
      T.must(security_configuration).dependabot_delegated_alert_dismissal
    when :dependabot_malware_alerts
      T.must(security_configuration).dependabot_malware_alerts
    when :token_scanning_partner_metadata
      T.must(security_configuration).secret_scanning_extended_metadata
    end
  end

  sig { void }
  def notify_socket_subscribers
    return unless repository.present?
    repo = T.must_because(repository) { "validated presence with guard clause" }
    return unless repo.owner&.organization?

    return unless security_configuration.present?
    security_config = T.must_because(security_configuration) { "validated presence with guard clause" }

    publisher = SecurityProductsEnablement::LiveUpdatePublisher.new(T.cast(repo.owner, Organization))
    publisher.repository_status(
      repository_id: T.must(repo.id),
      status: state,
      failure_reason:,
      config_id: security_config.id
    )
  end

  def instrument_destroy_event
    # only create an audit log when a user removes a configuration
    return if user.nil?
    instrument :removed, target: user
  end

  def instrument_update_event
    return if user.nil?
    return if self.previous_changes.keys.one? && self.previous_changes.keys.first == "updated_at"

    if attached?
      instrument :applied, target: user
    elsif enforced?
      instrument :applied, target: user
    elsif failed?
      instrument :failed, target: user
    elsif removed? || removed_by_enterprise?
      instrument :removed_by_settings_change, target: user
    end
  end

  def event_payload
    {
      target: user,
      repo: repository,
      security_configuration_id:,
      security_configuration_name: security_configuration&.name,
      repository_security_configuration_state: destroyed? ? nil : state,
      repository_security_configuration_failure_reason: audit_log_message(failure_reason)
    }.tap do |p|
      p[T.must(user).event_prefix] = user
    end
  end

  def enqueue_reapply_job(actor_id:)
    repository = self.repository
    return if repository.nil?

    SecurityProductsEnablement.domain.configurations.enqueue_attachment(
      actor_id:,
      repository:,
      security_configuration_id:,
    )
  end

  sig { params(failure_reason: T.nilable(String)).returns(T.nilable(String)) }
  def audit_log_message(failure_reason)
    return nil unless failure_reason

    SecurityProductsEnablement.domain.failures.audit_log_message_for(failure_reason)
  end
end
