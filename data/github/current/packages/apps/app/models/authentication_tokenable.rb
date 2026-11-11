# typed: true
# frozen_string_literal: true

module AuthenticationTokenable
  extend T::Helpers
  extend ActiveSupport::Concern

  # Public: Generates a new AuthenticationToken for this record and
  # returns the token's plaintext value for use in making authenticated API
  # requests.
  #
  # Returns a String.
  def generate_token(code_path: nil)
    T.bind(self, T.any(IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))
    ServerToServerTokens.domain.create(self.id, T.must(self.class.name), create_span_attributes)
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
