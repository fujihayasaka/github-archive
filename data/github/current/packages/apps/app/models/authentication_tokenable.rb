# typed: true
# frozen_string_literal: true

module AuthenticationTokenable
  extend T::Helpers
  extend ActiveSupport::Concern

  # Public: Generates a new authentication token for this record and
  # returns a result containing the token's plaintext value for use in making
  # API requests.
  #
  # code_path  - An optional String that represents where the token creation is
  #              being called from. Used for stats and availability.
  # redis_with_mysql_fallback - The Boolean determining if the caller wants to dual write the
  #              token to Redis and MySQL or just Redis with a MySQL fallback.
  #
  # Returns a GH::Result wrapping a CreateResult (which includes the plaintext
  # token and related metadata).
  def generate_token(code_path: nil, redis_with_mysql_fallback: false)
    T.bind(self, T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))
    integration_id = use_s2s_stateless_token? ? self.integration&.id : nil

    if redis_with_mysql_fallback
      ServerToServerTokens.domain.create_redis_with_mysql_fallback(self.id, T.must(self.class.name), create_span_attributes, code_path: code_path)
    else
      ServerToServerTokens.domain.create(self.id, T.must(self.class.name), create_span_attributes, integration_id: integration_id, code_path: code_path)
    end
  end

  # Whether to create a stateless S2S token via authnd instead of a persisted one.
  # Gated by the :server_to_server_authnd_stateless_tokens feature flag, which can
  # be targeted per-app (integration actor) for granular rollout control across
  # stamps and app populations.
  private def use_s2s_stateless_token?
    T.bind(self, T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))
    integration = self.integration
    return false unless integration

    FeatureFlag.vexi.enabled?(:server_to_server_authnd_stateless_tokens, integration, default: false)
  end

  # Obtain all of the available attributes for `authenticatable` that we can send to Datadog (for create requests)
  #
  # Returns a Hash.
  def create_span_attributes
    T.bind(self, T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))

    span_attributes = {
      "gh.authentication_token.authenticatable.id" => self.id,
      "gh.authentication_token.authenticatable.type" => self.class.name,
    }

    if self.respond_to?(:target_id) && self.respond_to?(:target_type)
      span_attributes["gh.installation.target.id"] = self.target_id
      span_attributes["gh.installation.target.type"] = self.target_type
    end

    if self.respond_to?(:parent)
      span_attributes["gh.parent_installation.id"] = T.cast(self, ScopedIntegrationInstallation).parent&.id
    end

    if self.respond_to?(:integration)
      integration = self.integration
      span_attributes["gh.integration.id"] = integration&.id
    end

    span_attributes
  end

  def valid_for_current_tenant?
    return true unless GitHub.multi_tenant_enterprise?

    T.bind(self, T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))
    GitHub::CurrentTenant.get == self.resolve_tenant
  end
end
