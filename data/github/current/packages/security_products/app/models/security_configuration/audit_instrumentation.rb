# typed: strict
# frozen_string_literal: true

# Encapsulates audit logging, event payload construction, and WebSocket
# notification logic for security configurations.
module SecurityConfiguration::AuditInstrumentation
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { SecurityConfiguration }

  sig { void }
  def notify_socket_subscribers
    # WebSocket notifications only support Organization targets today.
    # The underlying channel infrastructure is polymorphic, but LiveUpdatePublisher
    # and the enterprise frontend controller need updates to support Business targets.
    # "global" configs have no meaningful subscriber.
    return if %w[global Business User].include?(target_type)
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

  sig { params(security_feature: T.untyped, security_feature_state: T.untyped).void }
  def instrument_security_feature_changed(security_feature:, security_feature_state:)
    instrument :update, target: target, security_feature:, security_feature_state:
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

  sig { returns(T::Hash[Symbol, T.untyped]) }
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
      security_configuration_dependabot_delegated_alert_dismissal: dependabot_delegated_alert_dismissal,
      security_configuration_dependabot_malware_alerts: dependabot_malware_alerts,
      security_configuration_code_scanning: code_scanning,
      security_configuration_code_scanning_delegated_alert_dismissal: code_scanning_delegated_alert_dismissal,
      security_configuration_secret_scanning: secret_scanning,
      security_configuration_secret_scanning_push_protection: secret_scanning_push_protection,
      security_configuration_secret_scanning_delegated_bypass: secret_scanning_delegated_bypass,
      security_configuration_secret_scanning_validity_checks: secret_scanning_validity_checks,
      security_configuration_secret_scanning_non_provider_patterns: secret_scanning_non_provider_patterns,
      security_configuration_secret_scanning_generic_secrets: secret_scanning_generic_secrets,
      security_configuration_secret_scanning_delegated_alert_dismissal: secret_scanning_delegated_alert_dismissal,
      security_configuration_secret_scanning_extended_metadata: secret_scanning_extended_metadata,
    }

    case target
    when Business
      payload[:business] = target.display_login
      payload[:business_id] = target_id
    when Organization
      payload[:org] = target.display_login
      payload[:org_id] = target_id
    end

    payload
  end
end
