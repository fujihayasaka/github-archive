# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationCredentialAuthorizationCredential < Platform::Enums::Base

      # Represents the possible values for the `credential_type` field on OrganizationCredentialAuthorization instances
      # Possible values:
      #
      # - Personal Access Token
      # - Public Key

      description "The possible values for OrganizationCredentialAuthorization.credential_type."
      visibility :under_development

      value "PERSONAL_ACCESS_TOKEN", "The Organization Credential Authorization is for a Personal Access Token."
      value "PUBLIC_KEY", "The Organization Credential Authorization is for a Public SSH Key"
    end
  end
end
