# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Business
  # Enterprise level enablement for Public Monitoring Alerts.
  # Gates whether an enterprise receives and can view alerts for secrets
  # authored by its members in public repositories outside the enterprise.
  #
  class PublicMonitoring
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.public_monitoring.user_enabled"

    sig { params(business: Business).void }
    def initialize(business)
      @business = business
      @token_scanning = T.let(SecretScanning::Features::Business::TokenScanning.new(@business), SecretScanning::Features::Business::TokenScanning)
    end

    # True when the enterprise meets the hard prerequisites for Public
    # Monitoring Alerts: not on GHES, has token scanning available, and has
    # the GHAS or Secret Protection license. This is the upstream gate of
    # `enabled?` and `settings_available?` — neither flag nor opt-in can
    # override it.
    sig { returns(T::Boolean) }
    def feature_available?
      return false if GitHub.enterprise?
      return false unless @token_scanning.feature_available?
      @business.advanced_security_purchased? || @business.secret_protection_purchased?
    end

    # True when the enterprise admin should see the Public Monitoring Alerts
    # opt-in toggle in Additional Settings. Requires `feature_available?` plus
    # the alert settings flag — the rollout gate for who can configure the
    # feature. Exposed separately from `enabled?` because we deliberately do
    # not yank the feature from a customer who has already opted in if the
    # rollout flag is later disabled. The legacy preview flag is intentionally
    # excluded here: preview tenants are force-enabled and don't need a
    # toggle.
    sig { returns(T::Boolean) }
    def settings_available?
      feature_available? && alert_settings_flag_enabled?
    end

    # True when the enterprise has Public Monitoring Alerts turned on.
    # Requires `feature_available?` plus EITHER the legacy preview flag (which
    # force-enables grandfathered tenants during the rollout transition) OR
    # the enterprise admin opt-in stored on `Business#config`. Intentionally
    # does NOT depend on the alert settings flag — once a customer opts in,
    # disabling that flag won't take the feature away from them. This is the
    # gate every alerts-surface (UI / API / nav / TSS RPC) should consult.
    sig { returns(T::Boolean) }
    def enabled?
      feature_available? && (preview_flag_enabled? || @business.config.enabled?(CONFIG_KEY_USER_ENABLED))
    end

    # True when the enterprise has access to the Public Monitoring REST and
    # webhook surfaces. Requires `enabled?` plus the API/webhooks feature flag.
    sig { returns(T::Boolean) }
    def enabled_for_apis_webhooks?
      return false unless enabled?
      feature_flag_enabled_in_hierarchy?(@business, FeatureFlags::PUBLIC_MONITORING_APIS_WEBHOOKS)
    end

    # Records the enterprise admin's opt-in to receive Public Monitoring Alerts.
    sig { params(actor: User).void }
    def enable(actor:)
      @business.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end

    # Clears the enterprise admin's opt-in to Public Monitoring Alerts.
    sig { params(actor: User).void }
    def disable(actor:)
      @business.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    private

    sig { returns(T::Boolean) }
    def preview_flag_enabled?
      feature_flag_enabled_in_hierarchy?(@business, FeatureFlags::PUBLIC_MONITORING_PREVIEW)
    end

    sig { returns(T::Boolean) }
    def alert_settings_flag_enabled?
      feature_flag_enabled_in_hierarchy?(@business, FeatureFlags::PUBLIC_MONITORING_ALERT_SETTINGS)
    end
  end
end
