# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IdentityProviderConfigurationState < Platform::Enums::Base
      description "The possible states in which authentication can be configured with an identity provider."

      value "ENFORCED", "Authentication with an identity provider is configured and enforced."
      value "CONFIGURED", "Authentication with an identity provider is configured but not enforced."
      value "UNCONFIGURED", "Authentication with an identity provider is not configured."
    end
  end
end
