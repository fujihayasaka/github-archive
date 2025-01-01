# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OIDCProviderType < Platform::Enums::Base
      description "The OIDC identity provider type"

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "AAD", "Azure Active Directory", value: "azure"
    end
  end
end
