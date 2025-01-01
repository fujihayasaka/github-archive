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
  belongs_to :user, foreign_key: :organization_id, inverse_of: false

  validates_presence_of :organization_id

  # Notify Alive WebSocket subscribers if our state has changed:
  after_commit :notify_socket_subscribers, on: [:create, :update], if: :state_previously_changed?
  after_commit :instrument_update_event, on: :update
  after_commit :instrument_destroy_event, on: :destroy

  enum :state, { removed: 0, attached: 1, attaching: 2, failed: 3, updating: 4, enforced: 5, removed_by_enterprise: 6, detached: 7 }

  scope :applied, -> { where(state: %w(attached enforced)) }
  scope :applied_or_attaching, -> { where(state: %w(attached attaching enforced)) }

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
    return if feature == :token_scanning_validity_checks && !owner.feature_flag_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS, default: !GitHub.multi_tenant_enterprise?)

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

    # Skip removal for archived repositories when triggered by security configuration application
    if action_source == "security_configuration_enablement" && repository&.archived?
      return
    end

    case action_source
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
      T.must(security_configuration).code_security_sku_enabled ? "enabled" : "disabled"
    when :code_scanning_delegated_alert_dismissal
      T.must(security_configuration).code_scanning_delegated_alert_dismissal
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
    ApplySecurityConfigurationToRepositoryJob.perform_later(
      actor_id:,
      repository_id:,
      security_configuration_id:,
    )
  end

  sig { params(failure_reason: T.nilable(String)).returns(T.nilable(String)) }
  def audit_log_message(failure_reason)
    return nil unless failure_reason

    failure = SecurityProductsEnablement.enablement_failures_map[failure_reason]
    return failure["audit_log_message"] if failure && failure["audit_log_allowed"]

    "Failed to enable."
  end
end
